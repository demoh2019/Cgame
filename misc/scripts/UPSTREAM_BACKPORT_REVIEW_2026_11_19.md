# Godot upstream PR triage — 2026-11-19

Target: `demoh2019/Cgame` `develop`. Compare upstream PR source hunks with the
existing fork before applying; only cherry-pick targeted hunks that match exactly.
Open upstream PRs are not treated as released upstream code, and may change.

## Ported in this batch

| Upstream PR | Area | Why |
| --- | --- | --- |
| [#125326](https://github.com/godotengine/godot/pull/125326) | Editor FileSystemDock | Keep directory paths with exactly one trailing separator after a file/folder is deleted, except `res://`. |
| [#125347](https://github.com/godotengine/godot/pull/125347) | AudioStreamPlayer3D | Refresh 3D panning for playback offset 0 and store the last processed mix count after updating panning. |
| [#125356](https://github.com/godotengine/godot/pull/125356) | GDScript editor | Retain loaded script path in subscript type inference; useful for code completion and type resolution. |
| [#125324](https://github.com/godotengine/godot/pull/125324) | RenderingServerDefault | Duplicate Image before queueing an asynchronous texture update, keeping a copy-on-write pixel snapshot. |

## Confirmed already applied, skipped

- [#125593](https://github.com/godotengine/godot/pull/125593):
  `current_frame_is_data` WebSocket control-frame guard and interleaved Ping test already exist in `develop`.
- [#125582](https://github.com/godotengine/godot/pull/125582):
  `SurfaceTool::SIMPLIFY_ERROR_CLAMPED` LOD option already exists in `develop`.

## Review / not included

- [#125575](https://github.com/godotengine/godot/pull/125575):
  undoable instance placeholder changes affect scene state and require editor/manual undo testing.
- [#125587](https://github.com/godotengine/godot/pull/125587):
  already has a separate fork PR; avoid conflicting duplicated patch.

## Regression coverage

- Two **new native C++** `[Image]` tests in `tests/core/io/test_image.cpp`:
  original-image mutations leave the queued snapshot unchanged; multiple
  snapshots represent independent pixel generations (RGB8 and RGBA8 cases).
- Eleven **fast, source-level guards** in
  `misc/scripts/tests/test_upstream_backports_20261119.py` check the exact
  editor/audio/GDScript/rendering backport invariants and presence of native tests.
  These detect accidental reversion, but do **not** prove runtime behavior.
- `.github/workflows/upstream-backport-regression.yml` runs those guards on
  relevant PR/push changes with Python 3.13.

Run source checks:
```sh
python3 -m unittest discover -s misc/scripts/tests -p test_upstream_backports_20261119.py -v
```

For engine runtime verification, build the fork and run the native C++ test
target filtered by `[Image]` plus the relevant full editor/runtime smoke tests.
No local Godot engine compilation was available while preparing this backport;
do not claim native tests passed until CI runs them.
