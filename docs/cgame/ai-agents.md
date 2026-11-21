# AI agents: Cgame MCP server and agent CLI

How Claude Code, Codex and other MCP clients drive this repository: fast discovery, structured JSON,
undoable editor edits, low token use. Everything below was written against the MCP spec revision
2025-06-18 (JSON-RPC 2.0; stdio and Streamable HTTP transports); the server also accepts 2025-03-26
and 2024-11-05 clients.

## Two entry points

| Entry point | Needs editor | What it gives |
| --- | --- | --- |
| `game/addons/cgame_mcp/` (editor plugin) | yes | Full MCP server: scene editing, selection, run/stop, screenshots, logs, plus all code tools. |
| `game/scripts/tools/agent_cli.gd` | no (headless Godot) | Same code-intelligence tools as one-line JSON on stdout. |
| `tools/cgame_mcp_stdio.py` | optional | stdio MCP bridge: forwards to the editor if it runs, otherwise serves the headless subset. |

## Setup

1. Enable the plugin once: Project > Project Settings > Plugins > "Cgame MCP", or add
   `"res://addons/cgame_mcp/plugin.cfg"` to `[editor_plugins] enabled=` in `game/project.godot`.
2. Open the project in the editor (`bin/godot.macos.editor.arm64 --editor --path game`). The Output panel
   prints `Cgame MCP: http://127.0.0.1:<port>/mcp`.
3. The port is random unless `CGAME_MCP_PORT` (env) or ProjectSettings `cgame_mcp/port` is set. It is written to
   `user://cgame_mcp_port.txt` and to `game/.cgame_mcp.json` (`{"port","url","pid","auth",...}`); the bridge reads
   the latter. Do not commit `game/.cgame_mcp.json` (add it to `game/.gitignore`).
4. Optional auth: start the editor with `CGAME_MCP_TOKEN=secret`; clients send `Authorization: Bearer secret`.
   The bridge forwards its own `CGAME_MCP_TOKEN` env var.

### Claude Code

The repo-root `.mcp.json` already registers the bridge (stdio). Check with `claude mcp list`, approve the
project server when asked. Manual equivalent:

```
claude mcp add cgame -- python3 tools/cgame_mcp_stdio.py
```

Direct HTTP (no bridge) once the editor runs, using the port from `game/.cgame_mcp.json`:

```
claude mcp add --transport http cgame-editor http://127.0.0.1:<port>/mcp
```

### Codex (example only, nothing is written for you)

Add to `~/.codex/config.toml`, with the absolute repo path:

```toml
[mcp_servers.cgame]
command = "python3"
args = ["/ABSOLUTE/PATH/TO/Cgame/tools/cgame_mcp_stdio.py"]
# env = { CGAME_MCP_TOKEN = "secret", GODOT_BIN = "/ABSOLUTE/PATH/TO/Cgame/bin/godot.macos.editor.arm64" }
```

### Any other client

stdio: run `python3 tools/cgame_mcp_stdio.py` (newline-delimited JSON-RPC). HTTP: `POST http://127.0.0.1:<port>/mcp`
with `Content-Type: application/json`. Smoke test:

```
curl -s -X POST http://127.0.0.1:<port>/mcp -d '{"jsonrpc":"2.0","id":1,"method":"tools/list"}'
curl -s http://127.0.0.1:<port>/health
```

Bridge environment: `CGAME_MCP_URL` (override discovery), `CGAME_MCP_TOKEN`, `GODOT_BIN` (headless mode binary),
`CGAME_MCP_FORCE_HEADLESS=1`. `python3 tools/cgame_mcp_stdio.py --selftest` prints what it found.

## Tools

Node paths are relative to the edited scene root (`.` or empty = root). Every list tool takes `limit`.

| Tool | Purpose |
| --- | --- |
| `editor_state` | Version, open scenes, playing, selection count |
| `scene_tree` | Flat `path [Type] @script` list; `root`, `depth`, `filter`, `limit`, `offset` (`next_offset` paginates) |
| `node_get` | Type, script, groups, children, non-default props (`props` to pick, `all` for everything) |
| `node_set_property` | Undoable. Value is JSON or a Godot literal string (`"Vector3(1,2,3)"`, `"res://a.tres"`); `[x,y,z]` works for vectors and colors |
| `node_create` / `node_delete` / `node_move` | Undoable create (class or scene), delete (never the root), reparent/reorder/rename |
| `scene_open` / `scene_save` | Open a scene; save (or save-as with `path`) |
| `selection_get` / `selection_set` | Editor selection by path |
| `find_nodes` | By `type` (inheritance aware), `name` substring, `group`, `under` |
| `resource_inspect` | Properties of a `res://` resource or of a node's resource property |
| `script_check` / `check_scripts` | Parse errors with line numbers (also from `source` text); batch over files, dirs or `all`. Warnings count as errors |
| `class_docs` / `classes` | ClassDB methods/properties/signals for a native class, or the public API of a script under `scripts/` (by file name) |
| `project_search` | Limited grep over `res://` (`regex`, `ext`, `dir`) |
| `find_symbol` | Definition sites in GDScript and `modules/cgame_*` C++ |
| `project_map` / `native_status` | Orientation: folders, addons, modules, suites; which native classes exist in this binary and which facades fall back |
| `run_scene` / `stop_scene` | Play `current`, `main` or a scene path |
| `screenshot` | PNG saved under `user://cgame_mcp/shots` (path returned); `thumbnail:true` adds a 320px JPEG block |
| `logs_tail` | Editor Output panel (includes game output) or the editor-process log ring; `filter`, `level`, `lines` |
| `run_tests` | Child headless Godot, parses `TOTAL`/`FAIL` into JSON; does not block the editor |
| `perf_snapshot` | Editor-process Performance monitors |

MCP resources: `cgame://AGENTS.md`, `cgame://CLAUDE.md`, `cgame://docs/<page>.md` for every `docs/cgame/*.md`.

Headless-only subset (bridge without editor): `script_check`, `check_scripts`, `class_docs`, `classes`,
`project_search`, `find_symbol`, `project_map`, `native_status`, `run_tests`. Anything else returns an error
that says the editor is needed.

### Examples

```json
{"name":"scene_tree","arguments":{"depth":2,"filter":"light","limit":30}}
{"name":"node_set_property","arguments":{"path":"Sun","property":"light_energy","value":2.5}}
{"name":"node_create","arguments":{"type":"OmniLight3D","parent":"Lights","name":"Lamp","properties":{"position":[0,3,0]}}}
{"name":"script_check","arguments":{"path":"res://scripts/shared/htn_planner.gd"}}
{"name":"run_tests","arguments":{"suites":["test_ai_planners","test_gear_durability"]}}
```

### Agent CLI (no editor, no MCP)

```
godot --headless --path game --script res://scripts/tools/agent_cli.gd -- <command> [args]
```

Commands: `check <paths|all>`, `tests <suites|all>`, `suites`, `classes <filter>`, `api <Name> [member]`, `map [--full]`,
`find <symbol>`, `grep <text> [--ext .gd] [--regex] [--dir res://x] [--limit N]`, `native-status`, `help`.
One line of JSON on stdout; exit code 0 ok, 1 problems found, 2 usage error. Shared logic lives in
`game/scripts/tools/agent_lib.gd`.

## Token-saving tips

- Start with `project_map` (about 1 KB) and the `cgame://AGENTS.md` resource instead of listing directories.
- `scene_tree` with `depth`, `filter` and `limit`; then `node_get` with `props:[...]`.
- `find_symbol`/`class_docs` before opening files; `project_search` with `ext` and `limit`.
- After every GDScript edit call `script_check` on that file only. Run `check_scripts all` once at the end.
- `run_tests` with specific suite names; the response lists only failing suites and the first 60 `FAIL` lines.
- Use `screenshot` without `thumbnail` unless you really need to look at pixels; the path is enough for a human.

## Safety

- The server listens on `127.0.0.1` only, rejects non-local `Host`/`Origin` headers (DNS rebinding) and supports a bearer token.
- Scene edits use `EditorUndoRedoManager` with the scene as history context: Ctrl+Z in the editor reverts them.
  Nothing is saved until `scene_save`. The scene root cannot be deleted.
- There is deliberately no arbitrary-code or shell tool. `run_tests` and the CLI only start the same Godot binary
  with the repository's own scripts.
- `screenshot` target `screen` captures the OS screen (macOS asks for Screen Recording permission).
- Tools act on the editor process; `perf_snapshot` and `logs_tail source=editor` do not see a separately running game
  (the Output panel does include its prints).

## Limits and notes

- Transport is request/response only (no SSE stream, no server-initiated messages, no sessions); `GET /mcp` returns 405.
- The server is polled from the editor main loop; an unfocused editor may answer with some latency.
- `script_check` compiles the on-disk source in isolation. Cross-script type errors that depend on a stale in-editor
  cache are reported after the editor reloads the file.
- Protocol details follow the MCP specification (modelcontextprotocol.io). No third-party MCP server code is included or ported.
