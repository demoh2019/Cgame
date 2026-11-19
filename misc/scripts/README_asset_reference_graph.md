# Asset Reference Graph (offline dependency and impact inspection)

Find the assets a file **depends on** and the scenes, scripts, and other text
resources that **refer to it**. This is an initial, command-line slice of the
asset reference/dependency viewers provided by other game engines.

The tool is read-only, uses Python's standard library, and requires neither a
Godot editor build nor imported assets. It shares the path scanning and quoted
`res://` reference parser with `project_asset_audit.py`.

## Examples

Trace direct dependencies of a scene:

```sh
python3 misc/scripts/asset_reference_graph.py /path/to/project \
  --asset res://scenes/level.tscn --direction dependencies
```

Find every static referrer of a texture, including indirect referrers (impact
analysis):

```sh
python3 misc/scripts/asset_reference_graph.py /path/to/project \
  --asset res://art/grass.png --direction referencers --depth -1
```

Export a graph that Graphviz can render as SVG:

```sh
python3 misc/scripts/asset_reference_graph.py /path/to/project \
  --asset res://scenes/level.tscn --direction both --depth 2 \
  --format dot > references.dot
dot -Tsvg references.dot -o references.svg
```

JSON is also available (`--format json`). Each reference contains its
`source`, `target` and original text-resource `line` number; graph arrows
always point **from the referring asset to its dependency**. The CLI supports
`--exclude 'vendor/*'` (repeatable) and `--max-text-bytes N`, like the auditor.

Depth defaults to `1` (direct neighbors). `0` selects only the asset; `-1`
traverses all reachable links, with cycle detection. `--direction both` walks
in both directions but does not reverse the arrows in the result. The output
is sorted deterministically. Exit code `0` means the query ran successfully;
`2` means invalid options, missing project, or unknown/excluded asset. A query
may succeed even if the project has missing references: run the auditor to
check those.

## Scope and limitations

- The graph contains only existing, exactly cased files and static, quoted
  `res://` paths in the text extensions supported by `project_asset_audit.py`.
- Missing assets, invalid paths, generated cache directories, and excluded or
  symlinked files do not generate edges. To diagnose the former, run
  `python3 misc/scripts/project_asset_audit.py /path/to/project`.
- Dynamic paths, `uid://`, binary resource formats, C#-computed references,
  script references produced at runtime, and imported external dependencies
  are **not** resolved. These limitations mean the graph is not a complete
  dependency database or a replacement for editor resource loading.
- Text files over 8 MiB (by default) and unreadable/invalid UTF-8 text
  resources are not inspected for references. Other assets remain selectable.
- This is currently an offline CLI utility, **not yet an interactive dock or
  visual editor plugin**. Rendering DOT requires an optional Graphviz install.

## Tests

```sh
python3 -m unittest discover -s misc/scripts/tests -p 'test_asset_reference_graph.py' -v
```

Tests cover forward/reverse reachability, traversal depth and cycles, duplicate
occurrences, deterministic JSON/DOT, escaping, exclusions, comments, path
validation, symlink security, Unicode names, and CLI errors. They also run in
`.github/workflows/project-asset-audit.yml` on relevant changes.
