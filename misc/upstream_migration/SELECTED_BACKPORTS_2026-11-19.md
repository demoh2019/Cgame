# Godot upstream PR integrations — 19 November 2026

Target: `demoh2019/Cgame` / `develop`. Source PRs: `godotengine/godot`.
This log covers selected bug fixes and usability improvements, **not** a bulk merge of thousands of upstream PRs.

## Implemented in this pass

| Upstream PR | Relevant source | Reason |
| --- | --- | --- |
| [#125330](https://github.com/godotengine/godot/pull/125330) | `modules/visual_shader/editor/visual_shader_editor_plugin.cpp` | Hide built-in Input nodes that cannot be used inside VisualShader groups |
| [#124095](https://github.com/godotengine/godot/pull/124095) | `editor/editor_node.cpp` | Always prefill Save Resource As file path for a resource that already has a path, even when its extension needs no conversion |
| [#125539](https://github.com/godotengine/godot/pull/125539) | `scene/main/window.cpp` | Recalculate embedded window order when toggling Always on Top |
| [#125071](https://github.com/godotengine/godot/pull/125071) | `modules/gdscript/gdscript_parser.*`, `gdscript_warning.cpp` | Detect unreachable statements after `break` and `continue`; do not propagate conditional `continue` to a parent suite and create false positives |
| [#125318](https://github.com/godotengine/godot/pull/125318) + [#125325](https://github.com/godotengine/godot/pull/125325) | `editor/scene/3d/path_3d_editor_plugin.{cpp,h}` | Reset stale Path3D subgizmo point selections when a curve is deleted or the point count changes; integrated as a single consistent implementation |

Note: [#125125](https://github.com/godotengine/godot/pull/125125) (persisted animation track grouping) and [#125347](https://github.com/godotengine/godot/pull/125347) (3D audio mix count) were already present on `develop` when checked; their patches were **not applied again**.

Merged upstream fixes already present and skipped: #125530, #125237, #125488, #125527 (AudioServer), #124878, and #125394.

## Regression tests and verification

- `misc/scripts/tests/test_upstream_gdscript_editor_prs.py`: 49 structural/source-contract test cases for the relevant code paths (including previously adopted fixes). These checks guard refactor invariants, but **do not establish runtime correctness**.
- Five `.gd`/`.out` integration fixtures under `modules/gdscript/tests/scripts/parser/warnings/`: unreachable code after `break`, after `continue`, correct behavior after conditional `break`/`continue`, and a single warning for multiple unreachable statements in a block.
- `.github/workflows/upstream-gdscript-editor-prs.yml` runs the structural checks on Python 3.10 and 3.13, then builds a native Linux Cgame editor with `tests=yes` and exercises GDScript's integration suite plus a headless editor import smoke run.

Local offline commands:

```sh
python3 -m unittest discover -s misc/scripts/tests -p test_upstream_gdscript_editor_prs.py -v
```

After building Cgame with tests enabled:

```sh
scons platform=linuxbsd target=editor dev_build=yes tests=yes debug_symbols=no -j2
./bin/godot.linuxbsd.editor.dev.x86_64 --headless --test --test-suite="*GDScript*"
```

**Status:** All listed source changes have been committed to `develop`. The native engine build, compilation, integration tests, platform-specific editor behavior and CI results are *not yet confirmed*. Review the GitHub Actions workflow before claiming the fixes are production-validated. Because upstream PRs can still change, monitor review comments and adjust downstream code accordingly.

## Backport policy

Prefer small independent fixes; verify a PR is absent in `develop` before writing, avoid touching incompatible terrain/AI implementations, preserve existing public engine APIs, and require real native build/test evidence before considering cross-platform editor changes fully validated.
