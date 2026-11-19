# AI Game Builder — review-first repair context

`ai_repair_context.py` converts the **failed** JSON report from
`ai_project_smoke.py` into a small, structured, offline repair task with
classified diagnostics and optional file excerpts. It is a reusable building
block for the editor AI Repair UI, not an autonomous agent or a model client.

## Usage

```sh
python3 misc/scripts/ai_project_smoke.py /my/game --godot godot \
  --approve-execution > failed-smoke.json
python3 misc/scripts/ai_repair_context.py /my/game --report failed-smoke.json \
  > repair-context.json
# Explicitly permit one .gd file excerpt around the reported error line:
python3 misc/scripts/ai_repair_context.py /my/game --report failed-smoke.json \
  --allow-source res://scripts/player.gd > repair-context-with-source.json
python3 -m unittest discover -s misc/scripts/tests -p test_ai_repair_context.py -v
```

The first command **can execute project scripts** during Godot import. Use only
with a trusted project or a real security sandbox; `--approve-execution` is
mandatory. The **second command does not execute** Godot, scripts, processes,
or network calls, and never changes the project or contacts an AI provider.

The output schema `cgame.ai_repair_context.v1` includes per-error `stage`,
`kind`, bounded `message`, optional validated `path` and `line`, and opt-in
`source_excerpt`. At most 30 hints are included; full error/warning totals
from the smoke report remain in `summary`. Error text is **untrusted model
input**, not commands. A missing or successful report is rejected.

By default **no source code is read or included**. To include code, explicitly
list up to four `res://` paths; only `.gd`, `.tscn`, `.tres` and `.gdshader`
files are supported. Text files larger than 32 KiB, symlinks, hidden paths,
binary or invalid UTF-8 files, and out-of-project paths are never read. A
match with a reported line yields at most five lines/1,200 characters. Note:
**diagnostic messages and selected source snippets can themselves contain
private information**. Review the entire JSON before sending it to a model.

The intended AI loop is **validate -> inspect repair-context -> propose patch
-> review diff -> approve -> apply -> validate again**, with separate tools
handling patch safety, rollback, invocation budgets, and real editor
integration. No automatic edits or upload are added by this change.
