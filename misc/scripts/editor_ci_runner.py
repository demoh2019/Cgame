#!/usr/bin/env python3
"""Run a versioned matrix of Godot editor/import/script/scene smoke tests."""

import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import time

FORMAT_VERSION = 1
MAX_CASES = 256
MAX_MANIFEST_BYTES = 256 * 1024
NAME_RE = re.compile(r"[A-Za-z0-9_.-]{1,64}\Z")
KINDS = {"import", "script", "scene"}


class MatrixError(ValueError):
    """Invalid test matrix or unsafe case configuration."""


def _object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise MatrixError(f"Duplicate JSON key: {key}")
        result[key] = value
    return result


def _relative_path(raw):
    if not isinstance(raw, str) or not raw or "\\" in raw or ":" in raw or raw.startswith("/"):
        raise MatrixError(f"Unsafe relative path: {raw!r}")
    parts = raw.split("/")
    if any(p in ("", ".", "..") or p.endswith((" ", ".")) or any(ord(c) < 32 for c in p) for p in parts):
        raise MatrixError(f"Unsafe relative path: {raw!r}")
    return Path(*parts)


def _resolve_under(root, relative):
    target = root / relative
    # Reject a symlink even when it points to another path inside the root.
    current = root
    for part in relative.parts:
        current = current / part
        if current.is_symlink():
            raise MatrixError(f"Symlink in test path: {relative.as_posix()}")
    resolved = target.resolve()
    if not resolved.is_relative_to(root.resolve()):
        raise MatrixError(f"Test path escapes manifest directory: {relative.as_posix()}")
    return resolved


def load_matrix(manifest):
    manifest = Path(manifest)
    if not manifest.is_file() or manifest.is_symlink():
        raise MatrixError("Manifest must be a regular file")
    if manifest.stat().st_size > MAX_MANIFEST_BYTES:
        raise MatrixError("Manifest too large")
    try:
        doc = json.loads(manifest.read_text(encoding="utf-8"), object_pairs_hook=_object)
    except (UnicodeError, json.JSONDecodeError) as error:
        raise MatrixError(f"Invalid JSON: {error}") from error
    if not isinstance(doc, dict) or set(doc) != {"format", "cases"} or type(doc["format"]) is not int or doc["format"] != FORMAT_VERSION:
        raise MatrixError("Unsupported matrix format")
    cases = doc["cases"]
    if not isinstance(cases, list) or not 1 <= len(cases) <= MAX_CASES:
        raise MatrixError("Expected 1..256 test cases")
    root = manifest.resolve().parent
    names = set()
    checked = []
    for case in cases:
        if not isinstance(case, dict) or not {"name", "kind", "project", "timeout_seconds"} <= set(case):
            raise MatrixError("Case requires name, kind, project and timeout_seconds")
        kind = case["kind"]
        valid = {"name", "kind", "project", "timeout_seconds"} | ({"entry"} if kind == "script" else {"entry", "frames"} if kind == "scene" else set())
        if not isinstance(kind, str) or kind not in KINDS or set(case) != valid:
            raise MatrixError(f"Unexpected case fields or kind: {kind!r}")
        name = case["name"]
        if not isinstance(name, str) or not NAME_RE.fullmatch(name) or name in names:
            raise MatrixError(f"Invalid or duplicate test name: {name!r}")
        names.add(name)
        timeout = case["timeout_seconds"]
        if type(timeout) is not int or not 1 <= timeout <= 300:
            raise MatrixError("timeout_seconds must be an integer from 1 to 300")
        project = _resolve_under(root, _relative_path(case["project"]))
        if not project.is_dir() or not (project / "project.godot").is_file() or (project / "project.godot").is_symlink():
            raise MatrixError(f"Missing project.godot: {case['project']}")
        checked_case = {"name": name, "kind": kind, "project": str(project), "timeout_seconds": timeout}
        if kind != "import":
            entry = case["entry"]
            if not isinstance(entry, str) or not entry.startswith("res://"):
                raise MatrixError("Entry must be a res:// path")
            rel = _relative_path(entry[6:])
            if rel.suffix != (".gd" if kind == "script" else ".tscn"):
                raise MatrixError("Entry has unexpected extension")
            if not _resolve_under(project, rel).is_file():
                raise MatrixError(f"Missing scene/script: {entry}")
            checked_case["entry"] = entry
        if kind == "scene":
            frames = case["frames"]
            if type(frames) is not int or not 1 <= frames <= 1000:
                raise MatrixError("frames must be an integer from 1 to 1000")
            checked_case["frames"] = frames
        checked.append(checked_case)
    return checked


def run_case(case, godot):
    cmd = [godot, "--headless", "--path", case["project"]]
    if case["kind"] == "import":
        cmd.extend(["--editor", "--import"])
    elif case["kind"] == "script":
        cmd.extend(["--script", case["entry"]])
    else:
        cmd.extend(["--quit-after", str(case["frames"]), "--scene", case["entry"]])
    started = time.monotonic()
    with tempfile.TemporaryFile(mode="w+b") as log:
        try:
            result = subprocess.run(cmd, cwd=case["project"], stdout=log, stderr=subprocess.STDOUT,
                                    timeout=case["timeout_seconds"], check=False)
            status, code = ("passed", 0) if result.returncode == 0 else ("failed", result.returncode)
        except subprocess.TimeoutExpired:
            status, code = "timeout", None
        except OSError as error:
            status, code = "launch_error", None
            log.write(f"Could not start Godot: {error}".encode("utf-8", errors="replace"))
        log.seek(0)
        sample = log.read(8192).decode("utf-8", errors="replace")
    return {"name": case["name"], "kind": case["kind"], "status": status, "exit_code": code,
            "duration_seconds": round(time.monotonic() - started, 3), "output_excerpt": sample}


def run_matrix(manifest, godot):
    cases = load_matrix(manifest)
    results = [run_case(case, godot) for case in cases]
    passed = sum(r["status"] == "passed" for r in results)
    return {"format": FORMAT_VERSION, "passed": passed, "failed": len(results) - passed, "results": results}


def _write_report(path, report):
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temp = tempfile.mkstemp(prefix=".editor-ci-", dir=path.parent)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as stream:
            json.dump(report, stream, ensure_ascii=False, sort_keys=True, indent=2)
            stream.write("\n")
        os.replace(temp, path)
    finally:
        if os.path.exists(temp):
            os.unlink(temp)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("manifest", type=Path)
    parser.add_argument("--godot", default="godot", help="Path or name of a Godot editor executable")
    parser.add_argument("--report", type=Path, help="Optional JSON test report")
    args = parser.parse_args(argv)
    try:
        report = run_matrix(args.manifest, args.godot)
        if args.report:
            _write_report(args.report, report)
        print(json.dumps(report, ensure_ascii=False, sort_keys=True))
        return 0 if report["failed"] == 0 else 1
    except (MatrixError, OSError) as error:
        print(f"editor_ci_runner: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
