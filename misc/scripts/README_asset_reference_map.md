# Godot Asset Reference Map (CLI, experimental)

Read-only static resource dependency and **transitive source-file size** analyzer inspired by Unreal Engine's Reference Viewer / Size Map. This tool complements asset_size_map.py (whole-project budget and extension groups) rather than duplicating it. It imports that tool's scan_project to ensure the same filesystem safety checks.

## Examples

From an engine checkout:

~~~sh
python3 misc/scripts/asset_reference_map.py /path/to/game --root res://scenes/main.tscn
python3 misc/scripts/asset_reference_map.py /path/to/game --root res://scenes/main.tscn --root res://scenes/menu.tscn --format json > reference-report.json
python3 misc/scripts/asset_reference_map.py /path/to/game --root res://scenes/main.tscn --max-total-bytes 104857600
python3 -m unittest discover -s misc/scripts/tests -p test_asset_reference_map.py -v
~~~

The --root parameter accepts an explicit project-relative path or res:// path and can be repeated. For each root, the analyzer recursively follows **literal quoted res:// references** in .tscn, .tres, .gd, .cs, .gdshader, .gdshaderinc, .shader and .gdextension files. It reports:

- Total bytes and file count per selected root.
- A combined deduplicated source-file total (shared assets counted only once).
- JSON forward references, reverse references and a sorted complete list of reachable files and their byte sizes.
- Missing/invalid resource paths and path-case mismatches, with the actual filename when a case-only match exists.
- A CI-friendly combined size budget via --max-total-bytes.

JSON output is deterministic, excludes absolute paths and uses a versioned format: 1 object. Exit **0** means no missing/invalid references and budget passed; **1** means a reachable broken reference or budget overflow; **2** means analysis cannot be completed (unsafe project tree, invalid root, oversized/undecodable reachable text resource or invalid arguments). --max-text-bytes defaults to 8 MiB per parsed text file.

## Limits and security boundaries

This is **not an editor panel or a replacement for Godot's dependency loader**. It does not execute project scripts or import assets. File sizes are **source bytes on disk**, not export package size, GPU VRAM usage or runtime memory. Static-only scanning does not resolve uid:// references without associated res:// paths, runtime-generated resources, binary .res contents, packed archive internals or C# code-generated references. It may conservatively count res:// strings that occur outside actual resource-loading operations. Review diagnostic output before using it as a release gate. The scanner excludes common generated directories inherited from asset_size_map.py and rejects symlinks and case-insensitive filename collisions; it does not guarantee protection against a malicious process concurrently replacing directory entries.

## Testing

~~~sh
python3 -m py_compile misc/scripts/asset_reference_map.py misc/scripts/tests/test_asset_reference_map.py
python3 -m unittest discover -s misc/scripts/tests -p test_asset_reference_map.py -v
~~~
