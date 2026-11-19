# Scene Context Exporter (AI Game Builder foundation)

Unity's project-aware AI assistant can read scene hierarchy and dependencies. This
Godot fork now includes a **read-only, offline** scene hierarchy exporter that
provides a minimal, bounded, explicit scene snapshot for future AI tooling
([AI agent roadmap #73](https://github.com/demoh2019/Cgame/issues/73)).
This is not a live editor integration, autonomous editor agent, or general Godot
scene parser.

```sh
python3 misc/scripts/scene_context_export.py /path/to/godot-project \
  --scene res://scenes/main.tscn > scene-context.json
```

The output contains node **names, types, parents, nested-scene instances**,
external resource **paths/types**, a summary, and warnings for unavailable
nested scenes. Recursive `.tscn` dependencies follow `res://` or relative paths
(within the project) up to `--max-depth 2`. It never includes property values,
script source, or project configuration values; it never sends network requests
or executes GDScript. JSON key ordering and scene sorting are deterministic.

You must **explicitly** choose the project and scene. Treat resulting JSON as
potentially private metadata: review it before passing it to any AI provider.
File/directory symlinks are never followed; references outside the project,
remote URLs and unresolved `uid://` references are not opened. Missing or
unreadable nested scenes are reported as warnings; invalid/missing root scenes
fail with exit code 2.

Defaults are 32 scenes, 1000 total nodes, 1 MiB per scene, and nesting depth 2.
Override with `--max-scenes`, `--max-nodes`, `--max-scene-bytes` and
`--max-depth`. Limits prevent accidental huge AI context exports. The parser
only understands Godot 4 text scene headers (`[gd_scene]`, `[node]` and
`[ext_resource]`); binary resources, runtime-instantiated scenes and properties
aren't inspected. The tool is not a substitute for Godot's own parser or a
security boundary for untrusted project files.

## Regression tests

```sh
python3 -m unittest discover -s misc/scripts/tests -p test_scene_context_export.py -v
```

Tests cover scene hierarchy, recursive references, path/symlink protection,
UID limitations, malformed input, budgets, private-property omission, cycles,
and CLI behavior. The targeted GitHub Actions workflow runs on Python 3.9
and 3.13. Further work: native editor scene-tree bridge, opt-in selective AI
context, user-approved node editing with UndoRedo, and engine validation.
