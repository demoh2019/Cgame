# Godot upstream issue and pull-request mirror

This is a resumable **migration aid**, not a transparent GitHub transfer. The tool reads all upstream GitHub Issues/PRs (open and closed) into SQLite, then mirrors Issues to `demoh2019/godot`. Closed PRs become clearly labeled archival Issues, since the original merged/closed PR lifecycle and original authorship cannot be recreated in a different repository. With `--replay-open-prs`, it can attempt to replay **open** PR changes onto distinct fork branches and create **draft PRs**. Patch conflicts are either archived as Issues or reported as failures; nothing is merged into `master` automatically.

## Prerequisites

1. Enable GitHub **Settings → General → Features → Issues** in `https://github.com/demoh2019/godot/settings`. This feature is currently disabled in the fork and is required for importing Issues/archived PRs.
2. Python 3.10+, Git, local clone of `demoh2019/godot` for source-code PR replay, and a token with repository `Issues: write`, `Pull requests: write`, and `Contents: write` rights as appropriate. Keep the token in `GH_TOKEN`, **not in source control**.
3. Keep the SQLite database; it preserves mappings and scan cursors. The default location is `~/.cache/godot-upstream-mirror/tracker.sqlite3`. Back it up before long imports.

## Commands

```bash
# Scan the full issue + PR tracker history, including closed items.
python3 mirror_godot_tracker.py scan

# Progress and proposed next 50 items, without modifying GitHub.
python3 mirror_godot_tracker.py status
python3 mirror_godot_tracker.py sync --kind all --limit 50

# Enable Issues in the fork first, then import in small batches.
export GH_TOKEN='YOUR_GITHUB_TOKEN'
python3 mirror_godot_tracker.py sync --kind issues --limit 50 --apply

# Try open code PRs first (no archived/closed PR import).
python3 mirror_godot_tracker.py sync --kind prs --skip-closed-prs --limit 50 --apply --replay-open-prs --git-root /path/to/your/fork

# Then archive historical closed PRs as Issues while processing remaining records.
python3 mirror_godot_tracker.py sync --kind prs --limit 50 --apply --replay-open-prs --git-root /path/to/your/fork

# Repeat the sync command; the SQLite database prevents re-importing mapped items.
python3 -m unittest -v test_mirror_godot_tracker.py
```

Use `--limit 0` only if you understand that 123,000+ records will require many requests and multiple days, likely longer. The script defaults to **at least 9 seconds between content-changing requests**, with responses to GitHub rate-limit errors and no automatic retry for ambiguous writes. Lower limits, review a batch, then continue. A new full scan can refresh upstream metadata: `scan --reset`. Failed attempts to close imported Issues are journaled and repaired on the next `sync --apply`.

## Limitations and safeguards

- This does **not** transfer upstream issue/PR ownership, timestamps, reviews, reactions, assignees, milestones or GitHub PR merge status. It attributes original authors and links, with original labels stored in the description (not created as destination GitHub labels). Comments stay at the original URL, rather than being republished under another account.
- API listing may change while scanning. Scanning in ascending creation order and upserting on reset reduces duplication; use a rescan and reconcile periodically.
- Creating real open draft PRs requires the checkout to have enough Git history for `git merge-base`, source Git refs to be fetchable, and diffs to apply. Failed replays are recorded in SQLite; depending on mode they may be represented as archival Issues.
- Existing fork PRs referencing exactly one upstream PR are recognized and not recreated. Issues created by this tool carry a machine-readable marker. When a request fails after a successful GitHub POST, rerun to reindex the destination before retrying.
- **Do not** run untrusted upstream PR code; inspect and test it in CI before merging. Nothing in this tool merges upstream contributions automatically.
- This is a one-time/snapshot importer rather than a GitHub webhook-driven real-time mirror.
