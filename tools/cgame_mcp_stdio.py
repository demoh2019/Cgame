#!/usr/bin/env python3
"""stdio <-> HTTP bridge for the Cgame MCP server (Python 3 stdlib only).

Stdio-only MCP clients (Claude Code, Codex, ...) spawn this script. It forwards every JSON-RPC
message to the Godot editor plugin (addons/cgame_mcp, Streamable HTTP on 127.0.0.1). When no editor
is running it answers itself in "headless mode": a subset of tools that do not need the editor
is executed through `godot --headless --script res://scripts/tools/agent_cli.gd`.

Editor discovery, first match wins:
  1. env CGAME_MCP_URL (e.g. http://127.0.0.1:6010/mcp)
  2. game/.cgame_mcp.json written by the plugin ({"url": ..., "pid": ...})
Other env: CGAME_MCP_TOKEN (bearer token, must match the editor), GODOT_BIN (godot executable
for headless mode; default bin/godot.macos.editor.arm64 or `godot` on PATH),
CGAME_MCP_FORCE_HEADLESS=1 (never talk to an editor).

Messages on stdio are newline-delimited JSON (MCP stdio transport). Logs go to stderr only.
"""

import json
import os
import shutil
import subprocess
import sys
import urllib.error
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GAME = os.path.join(ROOT, "game")
CONFIG = os.path.join(GAME, ".cgame_mcp.json")
PROTOCOL = "2025-06-18"
SUPPORTED = ("2025-06-18", "2025-03-26", "2024-11-05")
HTTP_TIMEOUT = 900


def log(msg):
    sys.stderr.write("[cgame-mcp-bridge] %s\n" % msg)
    sys.stderr.flush()


def pid_alive(pid):
    try:
        os.kill(int(pid), 0)
        return True
    except (OSError, ValueError, TypeError):
        return False


def editor_url():
    if os.environ.get("CGAME_MCP_FORCE_HEADLESS") == "1":
        return None
    url = os.environ.get("CGAME_MCP_URL")
    if url:
        return url
    try:
        with open(CONFIG, "r", encoding="utf-8") as fh:
            info = json.load(fh)
        if info.get("pid") and not pid_alive(info["pid"]):
            return None  # stale file from a crashed editor
        return info.get("url")
    except (OSError, ValueError):
        return None


def post(url, payload):
    """POST one JSON-RPC message. Returns (status, body_text). Raises URLError if unreachable."""
    headers = {"Content-Type": "application/json", "Accept": "application/json, text/event-stream"}
    token = os.environ.get("CGAME_MCP_TOKEN")
    if token:
        headers["Authorization"] = "Bearer " + token
    req = urllib.request.Request(url, data=json.dumps(payload).encode("utf-8"), headers=headers, method="POST")
    try:
        with urllib.request.urlopen(req, timeout=HTTP_TIMEOUT) as resp:
            return resp.status, resp.read().decode("utf-8", "replace")
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode("utf-8", "replace")


# --------------------------------------------------------------------------------------------
# Headless mode
# --------------------------------------------------------------------------------------------

def _s(desc):
    return {"type": "string", "description": desc}


def _i(desc):
    return {"type": "integer", "description": desc}


def _b(desc):
    return {"type": "boolean", "description": desc}


def _arr(desc):
    return {"type": "array", "items": {"type": "string"}, "description": desc}


def _tool(name, desc, props, required=()):
    return {
        "name": name,
        "description": desc + " [headless: editor not running]",
        "inputSchema": {"type": "object", "properties": props, "required": list(required)},
        "annotations": {"readOnlyHint": True, "openWorldHint": False},
    }


HEADLESS_TOOLS = [
    _tool("script_check", "Parse a GDScript file; errors with line numbers (warnings are errors).",
          {"path": _s("res:// or game-relative script path")}, ["path"]),
    _tool("check_scripts", "Parse-check many scripts: files, dirs or 'all'.",
          {"paths": _arr("files/dirs or ['all']")}),
    _tool("class_docs", "ClassDB reflection for a class, or public API of a script under scripts/.",
          {"class": _s("class or script name"), "filter": _s("member substring"), "limit": _i("default 80")}, ["class"]),
    _tool("classes", "List ClassDB class names containing a filter.", {"filter": _s("substring"), "limit": _i("default 60")}),
    _tool("project_search", "Limited grep over res://.",
          {"pattern": _s("text or regex"), "regex": _b("regex mode"), "ext": _s("e.g. .gd"),
           "dir": _s("res:// subdir"), "limit": _i("default 40")}, ["pattern"]),
    _tool("find_symbol", "Where a func/const/class/signal is defined (scripts + modules/cgame_* C++).",
          {"symbol": _s("identifier"), "limit": _i("default 40")}, ["symbol"]),
    _tool("project_map", "Compact project map.", {"full": _b("list all suites")}),
    _tool("native_status", "Which modules/cgame_* classes exist in the godot binary; facade fallbacks.", {}),
    _tool("run_tests", "Run headless suites (names or ['all']); summary JSON.",
          {"suites": _arr("suite names or ['all']")}, ["suites"]),
]


def godot_bin():
    env = os.environ.get("GODOT_BIN")
    if env:
        return env
    for cand in ("bin/godot.macos.editor.arm64", "bin/godot.linuxbsd.editor.x86_64", "bin/godot.windows.editor.x86_64.exe"):
        p = os.path.join(ROOT, cand)
        if os.path.exists(p):
            return p
    return shutil.which("godot") or shutil.which("godot4")


def run_cli(args, timeout=300):
    binary = godot_bin()
    if not binary:
        return {"error": "no godot binary found; set GODOT_BIN"}
    cmd = [binary, "--headless", "--path", GAME, "--script", "res://scripts/tools/agent_cli.gd", "--"] + args
    try:
        proc = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
    except subprocess.TimeoutExpired:
        return {"error": "timed out after %ds" % timeout}
    for line in reversed(proc.stdout.splitlines()):
        line = line.strip()
        if line.startswith("{"):
            try:
                return json.loads(line)
            except ValueError:
                break
    return {"error": "no JSON from agent_cli (exit %d)" % proc.returncode, "stderr": proc.stderr[-400:]}


def headless_call(name, a):
    lim = ["--limit", str(int(a["limit"]))] if a.get("limit") else []
    if name == "script_check":
        return run_cli(["check", str(a.get("path", ""))])
    if name == "check_scripts":
        return run_cli(["check"] + [str(p) for p in (a.get("paths") or ["all"])])
    if name == "class_docs":
        return run_cli(["api", str(a.get("class", "")), str(a.get("filter", ""))] + lim)
    if name == "classes":
        return run_cli(["classes", str(a.get("filter", ""))] + lim)
    if name == "project_search":
        extra = []
        if a.get("regex"):
            extra.append("--regex")
        if a.get("ext"):
            extra += ["--ext", str(a["ext"])]
        if a.get("dir"):
            extra += ["--dir", str(a["dir"])]
        return run_cli(["grep", str(a.get("pattern", ""))] + extra + lim)
    if name == "find_symbol":
        return run_cli(["find", str(a.get("symbol", ""))] + lim)
    if name == "project_map":
        return run_cli(["map"] + (["--full"] if a.get("full") else []))
    if name == "native_status":
        return run_cli(["native-status"])
    if name == "run_tests":
        return run_cli(["tests"] + [str(s) for s in (a.get("suites") or ["all"])], timeout=1800)
    return {"error": "tool '%s' needs the Godot editor (not running). Start the editor with the cgame_mcp addon enabled." % name}


def headless_resources():
    out = []
    for f in ("AGENTS.md", "CLAUDE.md"):
        if os.path.exists(os.path.join(ROOT, f)):
            out.append({"uri": "cgame://" + f, "name": f, "mimeType": "text/markdown"})
    d = os.path.join(ROOT, "docs", "cgame")
    if os.path.isdir(d):
        for f in sorted(os.listdir(d)):
            if f.endswith(".md"):
                out.append({"uri": "cgame://docs/" + f, "name": "docs/cgame/" + f, "mimeType": "text/markdown"})
    return out


def headless_read(uri):
    rel = uri[len("cgame://"):] if uri.startswith("cgame://") else ""
    allowed = {r["uri"][len("cgame://"):] for r in headless_resources()}
    if rel not in allowed:
        return None
    with open(os.path.join(ROOT, rel if rel in ("AGENTS.md", "CLAUDE.md") else os.path.join("docs", "cgame", os.path.basename(rel))), "r", encoding="utf-8") as fh:
        text = fh.read()
    if len(text) > 60000:
        text = text[:60000] + "\n...[truncated]"
    return {"uri": uri, "mimeType": "text/markdown", "text": text}


def rpc_ok(i, result):
    return {"jsonrpc": "2.0", "id": i, "result": result}


def rpc_err(i, code, msg):
    return {"jsonrpc": "2.0", "id": i, "error": {"code": code, "message": msg}}


def headless_handle(msg):
    """Answer one JSON-RPC message locally. Returns a response dict or None."""
    if "id" not in msg or "method" not in msg:
        return None
    i, method, params = msg["id"], msg["method"], msg.get("params") or {}
    if method == "initialize":
        want = params.get("protocolVersion", PROTOCOL)
        return rpc_ok(i, {
            "protocolVersion": want if want in SUPPORTED else PROTOCOL,
            "capabilities": {"tools": {"listChanged": False}, "resources": {}},
            "serverInfo": {"name": "cgame-mcp-headless", "version": "1.0.0"},
            "instructions": "Godot editor is not running; only code-intelligence and test tools are available (headless). "
                            "Start the editor with addons/cgame_mcp enabled for scene tools.",
        })
    if method == "ping":
        return rpc_ok(i, {})
    if method == "tools/list":
        return rpc_ok(i, {"tools": HEADLESS_TOOLS})
    if method == "tools/call":
        res = headless_call(params.get("name", ""), params.get("arguments") or {})
        return rpc_ok(i, {"content": [{"type": "text", "text": json.dumps(res, separators=(",", ":"))}],
                          "isError": "error" in res})
    if method == "resources/list":
        return rpc_ok(i, {"resources": headless_resources()})
    if method == "resources/templates/list":
        return rpc_ok(i, {"resourceTemplates": []})
    if method == "resources/read":
        content = headless_read(params.get("uri", ""))
        return rpc_ok(i, {"contents": [content]}) if content else rpc_err(i, -32002, "resource not found")
    if method == "prompts/list":
        return rpc_ok(i, {"prompts": []})
    return rpc_err(i, -32601, "method not found: " + method)


# --------------------------------------------------------------------------------------------
# Main loop
# --------------------------------------------------------------------------------------------

def emit(obj):
    sys.stdout.write(json.dumps(obj, separators=(",", ":")) + "\n")
    sys.stdout.flush()


def forward(msg):
    """Send msg to the editor if reachable. Returns True when handled (response already emitted)."""
    url = editor_url()
    if not url:
        return False
    try:
        status, body = post(url, msg)
    except (urllib.error.URLError, OSError, ConnectionError):
        return False
    if status == 202 or not body.strip():
        return True
    if status == 401:
        if "id" in msg:
            emit(rpc_err(msg["id"], -32001, "editor rejected the token; set CGAME_MCP_TOKEN to match the editor's"))
        return True
    try:
        emit(json.loads(body))
    except ValueError:
        if "id" in msg:
            emit(rpc_err(msg["id"], -32603, "bad response from editor (HTTP %d)" % status))
    return True


def main():
    if "--selftest" in sys.argv:
        print(json.dumps({"root": ROOT, "editor_url": editor_url(), "godot": godot_bin()}))
        return 0
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        try:
            msg = json.loads(line)
        except ValueError:
            emit(rpc_err(None, -32700, "parse error"))
            continue
        msgs = msg if isinstance(msg, list) else [msg]
        for m in msgs:
            if not isinstance(m, dict):
                continue
            if forward(m):
                continue
            r = headless_handle(m)
            if r is not None:
                emit(r)
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        sys.exit(0)
