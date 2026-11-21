# Cgame: agent guide

Godot 4.8 engine fork ("Cgame") at the repo root, plus a game project in `game/` ("Albion After": persistent
open world, Albion-style tiers/zones/full loot, Days-After-style scavenging and zombies). Custom engine
modules live in `modules/cgame_*`; the game-side libraries are GDScript.

## Build (only when asked, it is slow)

- `scons` reads `custom.py` (platform=macos target=editor arch=arm64, accesskit=no, angle=no).
- Editor binary: `bin/godot.macos.editor.arm64`. Do not run full builds casually; engine C++ changes need the user's go-ahead.
- Several tests and facades behave differently on an older binary: `native_status` (MCP) or
  `agent_cli.gd native-status` shows which `Cgame*` native classes the current binary really has.

## Run, check, test (all headless, from the repo root)

```
B=bin/godot.macos.editor.arm64
$B --editor --path game                                              # editor (enable addons/cgame_mcp for MCP)
$B --headless --path game --script res://tests/run_one.gd -- test_name [test_name2]   # chosen suites (fast)
$B --headless --path game --script res://tests/run_all.gd           # everything (slow, CI does this)
$B --headless --path game --script res://scripts/tools/agent_cli.gd -- check scripts/shared/foo.gd
$B --headless --path game --check-only --script res://scripts/shared/foo.gd         # single-file parse check
```

Output ends with `TOTAL N checks, M failures`; failing lines start with `FAIL `. Suites are
`game/tests/test_*.gd`; runners are `game/tests/run_*.gd` (`run_graphics.gd` etc. are themed subsets).

## Agent CLI and MCP (prefer these over ad-hoc grep/find)

`agent_cli.gd` prints one JSON line: `check`, `tests`, `suites`, `classes`, `api`, `map`, `find`, `grep`,
`native-status`. The editor addon `game/addons/cgame_mcp` serves the same plus scene tools over MCP;
`tools/cgame_mcp_stdio.py` bridges stdio clients and `.mcp.json` registers it. Details: `docs/cgame/ai-agents.md`.

## Where things live (`game/`)

| Path | What |
| --- | --- |
| `scripts/shared/` (~570 files) | Engine-agnostic libraries used by client, server and tests: planners (HTN/GOAP/utility), mass entity, crowds, netcode, streaming, gameplay effects/attributes, world/PCG. Mostly `RefCounted`, static funcs, plain Dictionaries/packed arrays. |
| `scripts/client/` | Rendering, UI, audio, camera, atmosphere, input; entry scene `scripts/client/online_main.tscn`. |
| `scripts/server/` | Dedicated server (`server_main.gd`, `game_server.gd`, cluster/guild sync). |
| `scripts/native/` | Facades over `modules/cgame_*` native classes with GDScript fallbacks (`cgame_*_facade.gd`, `cgame_native.gd`). |
| `scripts/tools/` | Headless tools: perf, soak, readiness, docs generator, `agent_cli.gd`, `agent_lib.gd`. |
| `tests/` | `test_*.gd` suites (~570), `run_*.gd` runners, `test_case.gd` assertion helper, `e2e/`. |
| `addons/cgame_*` | Editor plugins (AI tools, graph editors, procgen, sequencer, terrain, world partition, MCP...). Enabled list is in `project.godot` `[editor_plugins]`. |
| `docs/`, `*.md` in `game/` | Per-feature design notes (one file per system). |
| `backend/`, `deploy/` | Nakama backend compose, server Dockerfile. |

Engine side: `modules/cgame_{ai,animation,audio,crowd,fluids,navigation,netcode,profiling,raytrace,softbody,streaming,vfx,virtual_geometry,worldgen}`;
each has `register_types.cpp` listing its `GDREGISTER_*CLASS` classes. Docs portal: `docs/cgame/README.md`
(generated API pages in `docs/cgame/api/`, status of each library in `experimental-systems.md`).

## GDScript conventions (verified in the code base)

- Typed GDScript, tabs for indentation. Warnings are treated as errors by project convention: type every variable,
  never `:=` from a Dictionary/Array lookup (Variant), mark intentional integer division with
  `@warning_ignore("integer_division")`, prefix unused params with `_`.
- Shared libraries have no `class_name`; load them with `const X = preload("res://scripts/shared/x.gd")`.
  Do not name things like native classes (shadowing is an error).
- Native modules are reached through facades in `scripts/native/` (`ClassDB.class_exists` checks), never by naming
  `Cgame*` classes directly in code that must still parse on a stock binary.
- Test suite shape: `extends RefCounted`, `const X = preload(...)`, `func run(t) -> void:` setting `t.current = "name"` then
  `t.check(cond, msg)`, `t.eq(actual, expected, msg)`, `t.near(a, b, tol, msg)`. Register new suites in `run_all.gd`
  (and a themed runner if one applies).
- Headless means no GPU: tests must not need rendering, network or downloaded asset packs.
- Large assets are not committed (see `game/.gitignore`); do not add binaries casually.

## Do / don't

- Do inspect before editing: `project_map`, `find_symbol`, `class_docs`, then read only the needed ranges.
- Do verify with the narrowest check: `script_check` on edited files, `run_tests` on the relevant suites. Say what you did not run.
- Do keep changes small and follow the nearest existing file's style. Add or extend a `test_*.gd` for new library behavior.
- Don't run `scons`, `run_all.gd` or soak/perf tools unless asked; CI covers them (`docs/cgame/ci.md`).
- Don't edit engine C++ for a game-level problem; don't touch `~/.claude`, `~/.codex` or other user-global config.
- Don't commit, push or open PRs unless asked. Branch/merge policy (the user wants finished work merged into `develop`) is the user's call.
- Don't commit secrets, `game/.cgame_mcp.json`, `.godot/` or generated import files.
- Never invent claims, metrics or performance numbers; docs say "library" vs "wired" deliberately.
