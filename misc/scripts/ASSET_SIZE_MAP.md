# Godot Asset Size Map (first milestone)

This read-only CLI is a lightweight counterpart to asset size-reporting features in large game editors. It scans a Godot project, groups asset disk sizes by extension, displays its largest files, and optionally fails CI when size budgets are exceeded. It never edits or imports game content.

~~~sh
python3 misc/scripts/asset_size_map.py /path/to/game --top 20
python3 misc/scripts/asset_size_map.py /path/to/game --format json --total-limit 104857600 --file-limit 10485760 --extension-limit .png=41943040 --extension-limit .ogg=20971520
~~~

All limits are **bytes**. The `--extension-limit` flag can be repeated, and `(none)=BYTES` covers extensionless files. `project.godot` is included. Exit code **0** means budgets passed, **1** means exceeded, and **2** means invalid input or incomplete scan. JSON reports use portable relative file paths and stable ordering. The `--top` limit may be 0–1000.

The scan excludes `.godot`, `.git`, `.hg`, `.svn`, and `__pycache__` directories, rejects symlinks, special files and case-insensitive path collisions (rather than silently undercounting), and does not follow directory symlinks. The tool measures **uncompressed on-disk source file bytes**; it does not estimate texture GPU memory, imported assets, package compression, runtime residency, dependency graphs or final export size. It is not a substitute for per-platform runtime profiling.

Run tests with:

~~~sh
python3 -m unittest discover -s misc/scripts/tests -p test_asset_size_map.py -v
~~~
