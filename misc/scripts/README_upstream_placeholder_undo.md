# Backport: Undo/Redo for Load as Placeholder in the scene tree

Based on upstream [godotengine/godot#125575](https://github.com/godotengine/godot/pull/125575) (upstream was open on 2026-11-19).

Before this patch, toggling **Load as Placeholder** from the scene-tree menu or selection wrote flags directly to scene instances. Those edits were not tracked correctly by the editor history and could not be reliably undone.

This backport uses `EditorUndoRedoManager` to record do/undo methods, refreshes the scene tree on both paths, and maintains the existing behavior of disabling **Editable Children** when placeholder loading is enabled. A scene-scoped action avoids ambiguity when the editable-children helper creates a nested history action. It keeps changes restricted to scene-tree editing and does not change the serialized scene resource format.

## Regression checks

```sh
python3 -m unittest discover -s misc/scripts/tests -p 'test_upstream_placeholder_undo.py' -v
```

Seven checks include direct inspection of **the actual C++ implementation** plus a compiled C++ harness that simulates selection, nested editor-history actions, reversing and reapplying placeholder flags, and null selections. The harness is not a complete Godot editor integration test. CI runs on Ubuntu and macOS; a production engine build and editor UI Undo/Redo exercise are still required before release.

## Native engine coverage

Four additional `[Node][PlaceholderUndo]` cases are registered in
`tests/scene/test_node.cpp` and exercise the actual Godot `UndoRedo` and
`Node::set_scene_instance_load_placeholder` implementations: enable, disable,
multi-node atomic change, and repeated history/undo/redo. The CI workflow also
builds the Linux Godot editor with `tests=yes` and runs these cases.

```sh
./bin/godot.linuxbsd.editor.dev.x86_64 --headless --test --test-case='*[Node][PlaceholderUndo]*'
```

The existing compiled harness exercises the editor toggle wiring but cannot
replace a manual interactive GUI check. The native suite does not instantiate
`EditorNode`; both are complementary, not proof of complete editor behavior.
