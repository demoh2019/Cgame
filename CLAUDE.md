@AGENTS.md

# Claude Code notes

- The `cgame` MCP server is registered in `.mcp.json` (stdio bridge `tools/cgame_mcp_stdio.py`). With the editor running and
  `addons/cgame_mcp` enabled you get scene tools; without it you still get `script_check`, `check_scripts`, `class_docs`,
  `find_symbol`, `project_search`, `project_map`, `native_status`, `run_tests` through headless Godot.
- Token discipline: call `project_map` once, use `find_symbol`/`class_docs` before reading files, pass `limit`, `depth`, `filter`.
  The MCP resource `cgame://AGENTS.md` and `cgame://docs/<page>.md` are cheaper than directory listings.
- After editing GDScript call `script_check` for that file; use `run_tests` with explicit suite names. Do not run `run_all.gd`
  or `scons` unless the user asks.
- Scene edits made through MCP are undoable in the editor and unsaved until `scene_save`.
- Prefer Haiku/Sonnet for mechanical discovery and test runs; keep the main context for decisions (see global rules).
- Full reference: `docs/cgame/ai-agents.md`.
