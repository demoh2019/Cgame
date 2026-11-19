# Scene Signal Graph: inspect Godot event wiring for AI Game Builder

Unity has event callbacks and Unreal has event graphs. In Godot, editor-wired `signal` connections carry similar gameplay flow information that an AI developer needs when understanding a scene. This tool provides **read-only structural signal topology** that complements the existing `scene_context_export.py` hierarchy and dependency summary.

```sh
python3 misc/scripts/scene_signal_graph.py /path/to/godot-game --scene res://scenes/main.tscn
python3 misc/scripts/scene_signal_graph.py /path/to/godot-game --scene res://scenes/main.tscn --format dot > scene-signals.dot
python3 misc/scripts/scene_signal_graph.py /path/to/godot-game --all-scenes --format json > scene-signals.json
python3 -m unittest discover -s misc/scripts/tests -p test_scene_signal_graph.py -v
```

The **JSON output** (`format: 1`) contains each selected scene, its root node name, a deterministic list of edges with `signal`, `from`, `to` and `method`, and `unresolved_endpoints`. Those are relative to the scene root: `.` means the root, `Player/Weapon` means a nested node. Unknown endpoints are reported instead of silently discarded, as they may belong to instanced scene nodes. The summary counts scenes, connections and unresolved endpoints. The **Graphviz DOT output** renders these connections as directed labeled edges, with escaped names and labels.

This script **does not** inspect arbitrary node properties or GDScript bodies, execute scripts, modify game files, or send network requests. It reads only chosen `.tscn` files, and uses the existing scene context exporter's attribute and path parsing helpers. Never share the result with an external model without reviewing potentially private scene names and method names.

The selection must be explicit (`--scene` repeated or `--all-scenes`). An all-scenes scan skips hidden directories, caches, VCS and addons. It rejects symlinks in selected scene paths or visible directories and prevents `..` traversal. Limits: at most 32 scenes, 512 KiB per scene, 2048 declared nodes and 8192 connections per scene, 512 KiB serialized output. Exceeding a limit returns exit code 2 rather than truncating partial JSON. Success exits 0.

**Limitations:** This is a static text-scene index, not an editor event debugger, a complete Godot parser or a Blueprint-like graphical editor. Dynamically connected signals, signals created in code, inherited scene behavior, and nested nodes inside external PackedScenes are not expanded; such references may appear as unresolved. Tests use temporary text-scene fixtures, not a running Godot engine. A complete AI Game Builder still requires editor integration and runtime validation.
