# Godot upstream OPEN Issues and OPEN Pull Requests mirror

This is a resumable **open-only migration aid** for `godotengine/godot` → `demoh2019/godot`. It never intentionally imports a closed Issue or a merged/closed PR. Its scanner reads the upstream GitHub Issues API with `state=open`, which includes open Issues and open PRs. It imports open Issues as Issues and, with explicit opt-in, replays open PR code into **draft PRs**; it does not silently turn PRs into metadata-only Issues. Nothing is merged into `master` automatically.

As of 2026-11-19, the source repository reported **13,425 open Issues** and **5,663 open PRs** (19,088 total). These are point-in-time counts, not guaranteed inventory sizes for future runs.

## Prerequisites

1. Enable **Settings → General → Features → Issues** at https://github.com/demoh2019/godot/settings to import Issues. If the feature is disabled, the Issue sync intentionally refuses to write. You can still import PR code with `--kind prs` and sufficient permissions.
2. Python 3.10+, Git, a sufficiently complete local checkout of the destination fork to replay PRs, and an authenticated token with `Issues: write` (for Issues), `Pull requests: write` and `Contents: write` (for code PRs). Keep the token in `GH_TOKEN`, **not in source control**.
3. Keep the SQLite state database. It stores source inventory, imported source→destination mappings, and pagination progress. The default is `~/.cache/godot-upstream-mirror/tracker.sqlite3`. Back it up before long runs.

## Commands

```bash
# Read ONLY currently open Issues and PRs from upstream. No GitHub writes.
python3 mirror_godot_tracker.py scan --reset
python3 mirror_godot_tracker.py status

# Dry-run: preview the next batch of open Issues.
python3 mirror_godot_tracker.py sync --kind issues --limit 50

# Enable Issues in the destination first, then import in reviewed batches.
export GH_TOKEN='YOUR_GITHUB_TOKEN'
python3 mirror_godot_tracker.py sync --kind issues --limit 50 --apply

# Dry-run: preview open PRs.
python3 mirror_godot_tracker.py sync --kind prs --limit 20

# Import real open code PRs as draft PRs. Patch conflicts are recorded as
# failures, not silently downgraded to ordinary Issues or merged to master.
python3 mirror_godot_tracker.py sync --kind prs --limit 20 --apply \
    --replay-open-prs --git-root /path/to/your/fork

# Previously failed items do not block subsequent batches. Retry them
# after resolving the reported errors:
python3 mirror_godot_tracker.py sync --kind issues --limit 20 --apply --retry-failures
python3 mirror_godot_tracker.py sync --kind prs --limit 5 --apply \
    --replay-open-prs --git-root /path/to/your/fork --retry-failures

# Repeat the sync commands. Existing mappings are skipped on each run.
# Re-scan (and prune closed items from the inventory) periodically.
python3 mirror_godot_tracker.py scan --reset

# Run regression tests (currently 36 cases).
python3 -m unittest -v test_mirror_godot_tracker.py
```

Do not pass `--apply` for a mixed `--kind all` batch that contains PRs without `--replay-open-prs` and `--git-root`; the script refuses to misrepresent code PRs as plain Issues. Use the separate Issue and PR commands above to diagnose failures independently.

## Scope and safeguards

- **Only upstream state `open` is eligible.** The scan also discards cached closed inventory on reset or when switching an older database to the open-only format. The sync query independently checks `state='open'`, including against stale SQLite data. Immediately before every create operation, it reads the current upstream Issue and skips items that have since closed. There is still a small unavoidable race between this final GET and the GitHub POST.
- `--reset` deletes the cached **source inventory**, not the imported mappings. It is safe to use after upgrading from the prior all-history scanner. Saved import mappings prevent re-importing already created destination records, and the destination is reindexed before writes after an interrupted run.
- Importing an open PR requires valid fetchable Git refs, a clean dedicated Git worktree and an applicable patch against the fork's target branch. Conflicts or inaccessible bases are failures to be reviewed, not metadata-only surrogate Issues. Check results and run CI before merging any imported PR.
- Original author names, source URLs, timestamps, and labels are included in the description as attribution. This script cannot recreate authorship, comments, reviews, reactions, notifications, assignees, milestones, or original GitHub IDs/history. It does not impersonate users.
- The imported items are a **snapshot**. The script does not automatically close a destination item if upstream closes later. Pagination over a changing set of open items can shift; repeat `scan --reset` before completion to reduce omissions.
- A full 19,088-record import needs many API requests and time; request throttling defaults to at least nine seconds between content-changing API calls. The importer guards ambiguous mutation retries, records failures, and defaults to dry-run. Failed items are skipped in the next normal batch so a deterministic failure cannot block thousands of later items; run with `--retry-failures` after repairing the root cause.
- The importer rejects negative `--limit` and `--max-pages` values. Already-closed destination copies are also reindexed so a lost SQLite database cannot recreate them.
- This PR contains the importer, **not a completed migration**. Do not claim successful import of all records or completed CI builds on the Godot engine.
