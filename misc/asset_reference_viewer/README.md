# Asset Reference Viewer — optional Godot/Cgame editor dock

A **read-only** editor dock for tracing static resource dependencies and reverse
references (`res://`). It complements the Python `misc/scripts/asset_reference_graph.py`
CLI with a native GDScript interface that works **without Python or network access**.

## Install / try it

1. Copy `addons/asset_reference_viewer` from this directory into your game's
   `res://addons/asset_reference_viewer` directory.
2. Enable **Project > Project Settings > Plugins > Asset Reference Viewer**.
3. Select an asset in the editor FileSystem dock, then click **Use selected file
   in FileSystem** in the new **Asset References** dock (or type its `res://` path).
4. Click **Refresh index**. Switch between **Dependencies**, **Referenced by**,
   or **Both directions**, and change depth (`1` immediate, `-1` all reachable).
5. Double-click any reference row to locate its referring file in FileSystem,
   or **Copy DOT** and paste the graph into a Graphviz viewer.

The directory itself contains a `project.godot` demonstration/test project with
this plugin enabled. Open `misc/asset_reference_viewer` as a Godot project to
see it without copying files elsewhere.

## Scope and engineering notes

- The analyzer enumerates existing files, including binary assets, and scans
  only supported text resources (`.tscn`, `.tres`, `.gd`, `.gdshader`, `.cs`, etc.)
  for complete quoted static `res://` literals. It records source, target and
  original line, and keeps exact case-sensitive path matches.
- Symlinked files/directories, generated `.godot`/`.import` folders and
  common dependency folders are not traversed. The index is built on demand;
  it is invalidated when the editor filesystem changes but **never** rescans
  automatically in a tight loop. A default 8 MiB per-text-file scan cap keeps
  pathological files from being loaded into memory.
- This is a textual dependency explorer, **not** an AST-based resolver,
  native scene dependency database, or full resource-reference viewer. It
  cannot resolve `uid://`, dynamically generated references, binary resources'
  internal links, dependency remapping, or imported runtime assets. Missing,
  case-mismatched, invalid or excluded paths produce **no edge**: run
  `misc/scripts/project_asset_audit.py` to diagnose those problems.
- The editor UI does not create/change project files and never executes
  inspected scripts or launches subprocesses. Copy DOT uses the clipboard.
- Large projects may have a noticeable synchronous scan delay. Future work:
  incremental indexing, native ResourceLoader dependency augmentation, and
  interactive graph layout/visual edges inside the dock.

## Tests / CI

With Godot 4.8 (or a compatible 4.x build) available:

```bash
godot --headless --path misc/asset_reference_viewer --script res://tests/test_graph_index.gd
godot --headless --editor --path misc/asset_reference_viewer --quit
```

Regression tests cover static literal parsing, comments, path validation,
case sensitivity, missing assets, duplicate lines, reverse/forward traversal,
cycles, depth limits, deterministic output, DOT escaping, generated-directory
exclusion, disk I/O and size limits. The GitHub Actions workflow repeats
these tests and checks that the editor starts with the plugin enabled.
