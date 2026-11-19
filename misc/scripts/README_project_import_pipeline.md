# Incremental Project Import Pipeline

A lightweight, opt-in asset import orchestrator for the Godot/Cgame editor. Its
purpose is to **avoid redundant headless imports in repeated builds and CI**,
not to replace Godot's own asset importer. It uses a content-hash inventory.
After a successful import, unchanged files reuse cached SHA-256 hashes if their
device, inode, mode, size, nanosecond mtime and ctime all match. Touching a file
without changing its contents still does not trigger a reimport.

## Usage

```shell
python3 misc/scripts/project_import_pipeline.py /path/to/my-godot-game --godot /path/to/godot --json
python3 misc/scripts/project_import_pipeline.py /path/to/my-godot-game --dry-run --json
python3 misc/scripts/project_import_pipeline.py /path/to/my-godot-game --force
python3 misc/scripts/project_import_pipeline.py /path/to/my-godot-game --verify-all
```

The project must contain `project.godot`. The script invokes the editor as
`godot --headless --path PROJECT --import` only if sources or engine version
changed, the imported cache is missing, or `--force` was supplied. This CLI
invocation is supported by Godot; imports are still performed by the engine.
The script never modifies project source files directly.

On successful import, the wrapper atomically saves source SHA-256 hashes,
file metadata fingerprints and the engine version into
`.godot/cgame-import-state.json`. Existing version-1 states are
intentionally invalidated once to populate version-2 fingerprints. The `.godot` directory
is ignored during hashing. Files under `.git`, `.hg`, `.svn`, `.venv`, `venv`,
`node_modules`, and `__pycache__` are excluded, too. Imported sidecar `.import`
settings elsewhere in the project are tracked. On an unchanged next run, the
expensive import command is skipped, but `godot --version` is still queried.

JSON output includes `needs_import`, `status` (`imported`, `skipped`, or
`dry_run`), sorted `added` / `changed` / `removed` lists, `reasons`, and
`files_scanned`. Exit code 0 means success or skip; 2 means invalid project,
Godot failure, unsupported symlink, timeout, or unsafe cache path. Failed or
racing imports never write a success state, so the next run retries.

This is **whole-project** import orchestration. It does not perform per-file
partial imports, manage distributed/shared caches, or guarantee CI performance
benefits unless `.godot` is retained between builds. A cold scan hashes O(total project source bytes); an unchanged warm scan
requires O(number of source files) metadata checks, without rereading source
file contents. The default fast path trusts filesystem metadata: an adversary
who can preserve all checked timestamps and inode metadata could cause a stale
hash cache hit. Use `--verify-all` for reproducible or security-sensitive
builds, which forces content verification on every scan. Do not run multiple
copies concurrently on the
same `.godot` cache. Symlinked inputs are rejected to avoid importing external
or untracked data.

## Tests

```shell
python3 -m unittest discover -s misc/scripts/tests -p 'test_project_import_pipeline.py' -v
```

The pure-Python tests use a fake Godot executable runner and do not exercise
Godot's importer itself. CI runs them on several Python versions and operating
systems. The actual import command should also be smoke-tested against a built
Godot editor before enabling this in production build automation.

## Related roadmap

Adds an independently usable first slice of issue #61, item 46, *Asset Pipeline
Automation*. The full roadmap item requires editor integration, asset
processors, per-file import controls, and production import smoke tests.
