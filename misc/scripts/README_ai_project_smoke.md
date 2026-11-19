# AI Game Builder — opt-in headless project smoke checks

A reusable validation step for [AI Game Builder epic #73](https://github.com/demoh2019/Cgame/issues/73). It stages a copy of a Godot game, runs **Godot's real import** against the copy and optionally starts its main scene for two headless frames. The command emits JSON suitable for AI repair proposals and CI gates, without modifying the original project tree.

## Run

```sh
# Default: import resources and parse project in a staged copy.
python3 misc/scripts/ai_project_smoke.py /path/to/game \
  --godot /path/to/godot --approve-execution > godot-smoke-report.json

# Additionally start the staged game's main scene for two frames.
python3 misc/scripts/ai_project_smoke.py /path/to/game \
  --godot /path/to/godot --approve-execution --run-game \
  --timeout 90 --max-copy-mib 512 --max-files 20000

python3 -m unittest discover -s misc/scripts/tests -p test_ai_project_smoke.py -v
```

`--import` is the official Godot headless import command. The optional game stage uses `--quit-after 2`; it is only a short smoke test, not a gameplay-quality test or a comprehensive GDScript type check. Diagnostics and process exit codes can reveal invalid imports/scripts, but successful exit does not prove correctness.

**Explicit execution permission is mandatory**. Godot may execute editor plugins, `@tool` scripts and project code during import and game launch, potentially including network or filesystem operations. This tool is **not a security sandbox**. Only run it for projects you explicitly trust or inside a separate secured execution environment. It does not autonomously execute model-generated code or grant model-selected tools.

## Safety and limits

- Copies the project to an OS-managed temporary directory, excluding generated cache/version-control directories (`.git`, `.godot`, `.import`, `.hg`, `.svn`, `__pycache__`). Rejects symlinks, special files, missing `project.godot`, file changes detected during copying, and oversized snapshots. Default maximum: 20,000 files / 512 MiB.
- Uses separate temporary HOME, cache, data and config directories and does not pass common API-key environment variables. This reduces accidental credential exposure but **does not** restrict project code's access to the host, network, user files, or other processes. Filesystem changes outside the temporary project cannot be rolled back by this utility.
- Requires a Godot editor executable accessible via `--godot`; no download, plugin installation, API call, or sandbox management is performed. Resolves the program without a shell and passes hardcoded command flags.
- Each stage has its own configurable timeout (up to 600 seconds). A timed-out Godot process is killed; the tool does not reliably terminate arbitrary child processes spawned by project scripts. The captured log is file-backed and fully scanned for diagnostics in bounded chunks; a sampled 64 KiB head/tail excerpt may omit middle lines, but cannot hide errors from check status.
- The JSON report contains per-stage status, errors/warnings, **total** `error_count` / `warning_count`, `diagnostics_truncated`, and snapshot totals. Each stage scans the **entire** Godot log using bounded reads, so parser errors buried in the middle of a large log still fail validation even when `output_truncated` is true. Only the first 30 diagnostic lines of each severity are returned, with total counts preserved. Temporary paths are redacted from captured diagnostic lines; user-generated messages can still contain private content, so **review reports before sending them to a model**.
- Exit status: `0` all requested stages passed, `1` Godot stage failed or timed out, `2` invalid inputs, refusal to execute without consent, or infrastructure failure.

## Structured diagnostics for AI repair

Each requested stage now also returns a bounded `diagnostics` array, in addition
to backward-compatible `errors` and `warnings` strings. For example:

```json
{"severity":"error","message":"SCRIPT ERROR: Parse Error: unknown identifier","resource":"res://ai_generated/scripts/player.gd","line":27}
```

Godot can report the location directly on the error line or on the following
`at:` line. A `column` field is included only when Godot supplies it.
Diagnostics keep at most 30 messages per severity; `error_count`,
`warning_count`, and `diagnostics_truncated` still communicate total failures.
The scanner reads the complete file-backed log without loading it into memory,
even when the stage's sampled log output is truncated.

This makes parse and resource errors actionable for an AI-assisted repair
preview, but **does not fix or execute arbitrary model suggestions**. The
`message` field is untrusted output and may contain private data or malicious
instructions. An editor integration must show any suggested changes for review
and ask permission before applying or executing them.
## Follow-up integration

Select **one** editor AI Game Builder implementation from the competing open addon/native PRs, then add a review-first "Validate generated project" button that calls this logic **only after explicit permission**. Feed bounded diagnostics into the existing AI repair preview. A secure sandbox and automated test/retry policy are separate future milestones of epic #73.
