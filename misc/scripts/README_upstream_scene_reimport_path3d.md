# Godot upstream PR backports: scene reimport and Path3D handles

Two targeted changes are integrated into Cgame from Godot upstream pull requests, with original contributor attribution preserved through the links below.

| Upstream source | Why it matters | Cgame files |
| --- | --- | --- |
| [godotengine/godot#125467](https://github.com/godotengine/godot/pull/125467) | Reimport an already-loaded scene even if there is no live instance in the edited scene. Prevents stale cached scene data when dragging reimported glTF/GLB assets into a new scene; relevant to AI-generated assets and scene reload. | `editor/editor_node.cpp`, `editor/editor_node.h` |
| [godotengine/godot#125410](https://github.com/godotengine/godot/pull/125410) | Only draw editable Path3D handles when the gizmo is *selected*, rather than merely when the Path3D is an editor target. Prevents ghost/transparent handles after deselection. | `editor/scene/3d/path_3d_editor_plugin.cpp` |

The changes originate from **open** upstream PRs at the time of adoption (2026-11-19); these are carefully scoped candidate fixes, **not** a statement that upstream merged them. The `editor_node.h` blob is byte-for-byte identical to its upstream PR version. Cgame's `editor_node.cpp` and Path3D editor file already contain unrelated edits; only the relevant upstream hunks were applied, preserving the rest of the fork.

## Verification

Run source-structure regression checks (31 tests):

```bash
python3 -m unittest discover -s misc/scripts/tests -p test_upstream_scene_reimport_path3d.py -v
```

The dedicated GitHub Actions workflow validates source contracts on two Python versions and additionally attempts to compile the **Cgame fork** editor and run a headless startup/import smoke check.

**Important:** Source-contract tests and a headless editor-startup check cannot prove that clicking the editor correctly reloads scenes or hides Path3D handles. These are editor-state bugs, so real interactive regression testing is required before considering them fully verified.

### Manual acceptance — reimport

1. Import a GLB scene; instantiate it once, then remove the instance while leaving the resource cached.
2. Change its import options (e.g., Apply Transform), reimport the source in the FileSystem dock.
3. Drag the imported asset into a fresh edited scene. Verify that the transformed mesh and related resources reflect the latest import rather than stale cached data.
4. Reimport again with and without an existing active instance; verify both paths and error logging.

### Manual acceptance — Path3D

1. Add Path3D with several curve points; select it and inspect editing handles.
2. Deselect in the 3D viewport; verify both regular and tilt handles disappear, not merely turn transparent.
3. Reselect and manipulate handles. Verify collision-line/path visuals remain functional.

## Other reviewed upstream fixes

These are already in Cgame `develop` and were **not duplicated**: [#125544](https://github.com/godotengine/godot/pull/125544) (dock width), [#125620](https://github.com/godotengine/godot/pull/125620) (display/navigation failure cleanup), [#125237](https://github.com/godotengine/godot/pull/125237) (WebSocket state reset), [#125466](https://github.com/godotengine/godot/pull/125466) (TileSet Undo/Redo context and source paths).

This incremental backport does not imply all upstream fixes have been audited or all integration tests are green. AI Game Builder issue #73 remains the primary product initiative.
