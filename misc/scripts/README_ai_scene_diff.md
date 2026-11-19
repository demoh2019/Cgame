# AI Game Builder: read-only scene change preview

This is a first independent **review-before-apply** building block for [issue #73](https://github.com/demoh2019/Cgame/issues/73). It compares the *same* `res://` text scene in an untouched Godot project and a separately staged candidate project. It reuses the existing `scene_context_export.py` reader. The original and staged projects are **never modified or executed** by this tool.

Unity AI supports planning and approving editor actions; Unreal's Diff tool compares changed assets. This script adds a **narrow offline comparison of scene structure**, not full editor integration or a replacement for either product.

## Use

```sh
python3 misc/scripts/ai_scene_diff.py /path/to/unchanged-game /path/to/staged-game \
  --scene res://scenes/main.tscn > scene-diff.json

# Show counts without disclosing individual node/resource names.
python3 misc/scripts/ai_scene_diff.py /path/to/unchanged-game /path/to/staged-game \
  --scene res://scenes/main.tscn --max-changes 0

# Restrict depth, number of scenes and JSON output size.
python3 misc/scripts/ai_scene_diff.py /path/to/unchanged-game /path/to/staged-game \
  --scene res://scenes/main.tscn --max-depth 1 --max-changes 50 \
  --max-output-bytes 8192
```

**Inputs must each contain `project.godot` and the selected `.tscn` file.** Keep the proposed version in a *separate staging copy*, not in the original project tree. This tool does not create the staging copy. It makes no AI/model requests or network calls and does not automatically apply a change. Review the report and source changes before deciding to apply anything.

## Output (`cgame.ai_scene_diff.v1`)

JSON has `root_scene`, `summary`, `changes`, `text_changed_scenes`, `warnings`, `truncated` and `schema` fields. Changes are deterministic, grouped by scene filename, then node parent/name or referenced resource path/type. Supported changes include:

- Added/removed nested scene resources, nodes and external resource references.
- Modified node type or referenced instance scene when **parent path + name** stay the same.
- Renames/reparents represented conservatively as **remove + add**, not inferred as moves.
- `text_changed_scenes` flags byte-level differences for files in both snapshots, **even when only property values have changed**. Actual property values and GDScript source code are never reported. Text changes may include line endings or resource IDs.
- Warnings for unavailable nested scenes (independently for before/after). Incomplete recursion can produce incomplete structural diffs. Check warnings before trusting results.

By default, the context reader inspects no more than **32 scenes, 1000 nodes total, 1 MiB per scene, depth 2** on each side. The preview includes at most **200 change records** and **128 KiB of compact JSON**. Override with `--max-scenes`, `--max-nodes`, `--max-scene-bytes`, `--max-depth`, `--max-changes`, `--max-output-bytes`. `--max-changes 0` returns summary-only output. Truncated output retains full counts; output metadata that cannot fit the explicit byte budget produces exit status 2 rather than an oversized report. Default and maximum budgets are validated. Exit status `0` indicates that a preview was produced, **not** that the proposed game compiles or runs; status `2` indicates invalid input or a failed inspection.

## Safety / known limits

This is a **metadata-only, static text-scene comparison**. Only names, types, parent paths, instance references and external resource paths/types are disclosed; **node names and paths themselves may be private**. Review JSON before sharing with an AI provider. No property values, credential-looking script bodies or untrusted scene code are loaded into the output. Symbolic-link project roots, scene paths and project manifest files are rejected; resource path traversal is rejected by the existing scene reader. This reader is best-effort and does **not** provide a full filesystem sandbox against concurrent writes, malicious file replacement or changing the project while a scan runs.

Binary scenes, dynamic resource loads, `uid://`-only references, arbitrary GDScript code, non-`.tscn` files, property-level diffs and run-time nodes are not indexed. Identical duplicate external-resource declarations are collapsed; duplicate node identities are rejected rather than guessed. A before/after comparison may show modifications to scene text without a structural change because property text is deliberately hidden. **Do not auto-apply edits based on this report.** Continue to use Godot's native importer, parser, editor preview and headless smoke checks before approving AI changes.

## Test locally

```sh
python3 -m py_compile misc/scripts/ai_scene_diff.py misc/scripts/tests/test_ai_scene_diff.py
python3 -m unittest discover -s misc/scripts/tests -p test_ai_scene_diff.py -v
python3 -m unittest discover -s misc/scripts/tests -p test_scene_context_export.py -v
```

The targeted workflow tests both scripts on Linux, Windows and macOS with Python 3.9 and 3.13. No Godot binary, model subscription or external Python packages are required.
