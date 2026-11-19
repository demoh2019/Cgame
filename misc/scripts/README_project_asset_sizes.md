# Godot source-asset size report

Small, dependency-free project size audit inspired by asset-size diagnostics in other game engines. It works offline and can enforce size budgets in CI.

```bash
python3 misc/scripts/project_asset_sizes.py /path/to/godot/project --top 20
python3 misc/scripts/project_asset_sizes.py /path/to/godot/project --max-total-mib 500 --max-file-mib 32 > size-report.json
python3 -m unittest discover -s misc/scripts/tests -p test_project_asset_sizes.py -v
```

The command reports the number and total bytes of regular source files, size totals by extension and top-level directory, and the largest files. Output is stable, sorted JSON without timestamps or absolute paths. Exit code `0` means no budget exceeded, `1` means a size limit was exceeded, and `2` means invalid parameters or an incomplete/untrusted scan.

`.git`, `.godot`, `.import`, `.hg`, `.svn`, and `__pycache__` are excluded. Symlinks and special files abort scanning instead of silently undercounting. Place redirected reports **outside the project** to avoid including the report itself on later scans. Budgets use binary mebibytes (1 MiB = 1,048,576 bytes), and values equal to the limit pass.

**Scope:** Sizes are of project files **on disk before export**. This is not a packed build report, runtime RAM/VRAM estimator, texture decoder, dependency graph, or Unreal-style interactive Size Map. Export compression, resource conversion, and engine packaging can change final size. The CLI provides an auditable first increment for asset-budget automation; editor integration and exported-build analysis are future work.
