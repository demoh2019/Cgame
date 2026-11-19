# AI Game Builder: review-first edits in an isolated project copy

This optional Python 3.9+ standard-library tool is a foundational increment for [AI Game Builder #73](https://github.com/demoh2019/Cgame/issues/73). It permits **model-proposed edits to existing text resources** without editing the original Godot project. A strict, versioned plan supports create, modify and delete operations, checks SHA-256 preconditions to prevent stale edits, and produces a bounded unified diff. `--stage` explicitly creates an independently reviewable copy. No AI provider, network access or Godot executable is required.

## Usage

```sh
# Preview (default: read-only; output is JSON with per-file actions, SHA-256 and diff):
python3 misc/scripts/ai_project_patch.py /my/game /my/proposal.json > review.json

# Explicitly assemble a separate working copy after reviewing the diff:
python3 misc/scripts/ai_project_patch.py /my/game /my/proposal.json --stage /my/game-candidate

# An additional, explicitly approved step may validate the staged project:
python3 misc/scripts/ai_project_smoke.py /my/game-candidate --godot godot --approve-execution

# Regression tests:
python3 -m unittest discover -s misc/scripts/tests -p test_ai_project_patch.py -v
```

Sample proposal:

```json
{
  "format": 1,
  "changes": [
    {"path": "scenes/bonus.tscn", "expected_sha256": null, "content": "[gd_scene format=3]\n[node name=\"Bonus\" type=\"Node2D\"]\n"},
    {"path": "scripts/player.gd", "expected_sha256": "<64 lowercase hex chars from the original file>", "content": "extends Node2D\n"},
    {"path": "scripts/old.gd", "expected_sha256": "<64 lowercase hex chars from the original file>", "delete": true}
  ]
}
```

The sample SHA placeholders must be replaced by actual file SHA-256 digests. Files must already exist for modify/delete, and must not exist for create. At most 20 operations are allowed, with 96 KiB of UTF-8 text per proposed file. Only `.gd`, `.tscn`, `.tres`, `.gdshader`, `.json`, `.md`, `.txt` and `.svg` are writable. System files such as `project.godot`, hidden paths, `addons/`, and `ai_generated/` are blocked. Symlinks, path traversal, case conflicts and tool scripts are rejected.

## Important safety limits

- **No execution or automatic application.** The source project remains untouched; the staged target must not exist and must live outside the source tree. Rejects stale hashes and source changes during copy; any failed staged build removes its temporary copy.
- The old project is copied with build caches and VCS directories excluded. Limit: 20,000 files and 512 MiB. Stage from a trusted filesystem with an exclusive staging destination; use immutable source snapshots against adversarial filesystem races.
- Review diffs are bounded to 16,000 characters. They may contain secrets present in selected project files; review before sharing output with an AI provider. No project data is transmitted by this tool.
- **Not a sandbox.** The tool does not validate GDScript syntax, embedded scripts, runtime behavior, external dependencies, scenes or resource compatibility. `@tool` is conservatively blocked, but static checks cannot prove generated code safe. Never execute untrusted proposals; use `ai_project_smoke.py` only with deliberate approval in a secured environment.
- This CLI is not yet integrated into the editor's Apply button or UndoRedo stack. It intentionally does not overwrite project files. Discard the staged copy to undo the candidate.
