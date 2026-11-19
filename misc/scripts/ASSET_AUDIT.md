# Asset preflight validation for Godot projects

`asset_audit.py` is a dependency-free, read-only CLI tool for detecting asset mistakes **before** importing projects in the Godot editor or shipping a build. It is intended as an initial building block for the asset pipeline automation roadmap (feature #46). It does not alter Godot's import pipeline, generate assets or replace editor validation.

## Usage

```sh
python3 misc/scripts/asset_audit.py /path/to/your/game
python3 misc/scripts/asset_audit.py /path/to/your/game --format github --fail-on warning
python3 misc/scripts/asset_audit.py /path/to/your/game --format json --output audit.json
python3 misc/scripts/asset_audit.py /path/to/your/game --exclude 'thirdparty/*' --no-cycles
```

Requires Python 3.10+ and a directory containing `project.godot`. Default exit status is 1 for errors, 0 otherwise. `--fail-on warning` also fails for dependency cycles or unreadable text files; `--fail-on none` always exits 0 after successfully scanning. `--format github` outputs GitHub Actions annotations and escapes potentially unsafe characters from file paths/messages.

## Checks

- `MISSING_RESOURCE`: explicitly referenced `res://` path does not exist, including a dangling symlink.
- `CASE_MISMATCH`: resource exists but its file name has different case than in the reference. This is a common cross-platform regression.
- `CASE_COLLISION`: two different assets map to the same case-folded path.
- `INVALID_URI`: empty, parent-traversing, non-canonical or Windows-style `res://` path.
- `OUTSIDE_PROJECT`: a symlink would resolve an asset reference outside the project directory.
- `UNRESOLVABLE_RESOURCE`: a resource path cannot be resolved (for example, a symlink loop).
- `DEPENDENCY_CYCLE`: a static resource/script dependency cycle spanning multiple files (warning, because some cycles may be intentional).
- `UNREADABLE_TEXT`: a text resource could not be decoded (warning).

Scans scene and text resource metadata, explicit `load("res://...")` and `preload("res://...")` calls in GDScript, shader and C# files, plus `main_scene` and icon paths in `project.godot`. Binary assets are treated as path targets, not parsed. `.godot`, `.git`, `.svn`, `.hg` and `__pycache__` are ignored. `--exclude` supports repeatable case-sensitive glob patterns relative to the project root.

**Limitations:** runtime-calculated paths, `uid://` references, imported resource internals, indirect GDExtension library paths, external packages, material/shader semantics and engine import correctness require editor/integration checks. A result without errors does **not** guarantee the game runs correctly. Use `godot --headless --editor --path PROJECT --quit` as a follow-up validation step where the engine is available.

## Tests

```sh
python3 -m unittest discover -s misc/scripts/tests -p 'test_asset_audit.py' -v
```

The regression suite covers paths, quoted literals and comments, dynamic `load()` paths, case sensitivity, UTF-8/unicode, symlink traversal, resource graph cycles (including long chains), API and CLI exit statuses, text/JSON/GitHub Actions output, and deterministic ordering. This tool and tests run with Python alone; no engine build is needed for the script itself.
