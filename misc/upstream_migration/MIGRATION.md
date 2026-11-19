# Godot upstream issue and PR migration

Source: `godotengine/godot` → destination: `demoh2019/Cgame`.

This repository is already a fork with matching upstream `master` history, so **merged upstream PR code should not be cherry-picked again**. Backports to this fork target `develop`, while source PRs are selected from upstream `master`. A GitHub PR must have a diff against its target branch: historical merged/closed upstream PRs cannot be faithfully recreated as ordinary open PRs in the fork. They can be archived as **closed issues** or exported to JSONL. Open PRs with clean patches can be submitted as **draft PRs** for review and CI.

## Prerequisites

1. In the destination GitHub repository, enable **Settings → General → Features → Issues**. GitHub currently returns `410: Issues has been disabled in this repository` when creating an issue. **Nothing can migrate into the Issues tab until this is changed.** This is a repository setting; creating a PR does not enable it.
2. Use Python 3.10+ and a `GITHUB_TOKEN` with read access to upstream and **Issues: read/write**, **Pull requests: read/write**, **Contents: read/write** in the destination. Tokens should be in environment variables or GitHub Secrets, **never committed**.
3. For applying code from open PRs, work in a local checkout of the fork with remotes `origin=https://github.com/demoh2019/Cgame.git` and `upstream=https://github.com/godotengine/godot.git`. Commit/push rights must work. Avoid running two migrations at the same time.

## Locally

Dry-run first (all commands are no-op until `--apply`):

```bash
export GITHUB_TOKEN=...  # supply your own token without committing it
python3 misc/upstream_migration/migrate_upstream.py issues --open-only --limit 20
python3 misc/upstream_migration/migrate_upstream.py prs --open-only --code --limit 20 --repo-path .
```

Apply a short batch of issues and comments (requires **Issues enabled**):

```bash
python3 misc/upstream_migration/migrate_upstream.py issues --apply --open-only --comments --limit 20
```

Run larger batches explicitly, advancing `--start-page` (one source API page = 100 records, including PRs when listing issues):

```bash
python3 misc/upstream_migration/migrate_upstream.py issues --apply --comments --limit 100 --start-page 1
python3 misc/upstream_migration/migrate_upstream.py issues --apply --comments --limit 100 --start-page 2
```

To cover the **entire history**, omit `--open-only` and use `--limit` higher than the full count; the importer follows the normal GitHub repository pagination rather than capped Search API results. This is a very large, multi-run task subject to GitHub rate limits and repository activity. On restart, the tool scans the destination and skips issue and PR origins it has already imported. Select `--start-page` to avoid rereading the earliest source pages. The script marks historically closed source issues as closed in the fork, preserving the *state* but not original GitHub event timestamps.

Import open PR code as drafts, **never automatically merge**:

```bash
python3 misc/upstream_migration/migrate_upstream.py prs --apply --open-only --code --limit 20 --repo-path .
```

Archive older closed and merged PR history as closed issues (requires Issues enabled), or save summaries to JSONL (local only). For very large runs, use the JSONL path or small source page ranges:

```bash
python3 misc/upstream_migration/migrate_upstream.py prs --apply --archive-closed-prs --limit 20
python3 misc/upstream_migration/migrate_upstream.py prs --apply --archive-path upstream_pr_history.jsonl --limit 100
```

### What is preserved

- Issue titles, descriptions, current open/closed state, labels (created in the destination on demand), and optional comments with visible original authors and timestamps.
- Direct links to the original issue or PR, including attachments and review discussion still hosted upstream.
- Draft PR code as a patch against the destination `develop` only when application is clean and nonempty; original PR author credited in description.
- Duplicates are detected by scanning destination records and exact origin references, including existing manual backports that mention upstream PRs.

### Limits and safeguards

- GitHub does not allow assigning the original PR/issue number, author, creation date, or review history to newly created records. Author/date information is included in the body only.
- Upstream assignees are not transferred: those users may not have access to the fork. Milestones and review approvals are likewise not copied verbatim.
- Non-master source PRs, conflicting patches, empty/previously merged diffs, and PRs for which a destination copy already exists are skipped for manual review. PRs are **draft**, require CI, and are never auto-merged.
- The tool does not automatically build/test Godot. Changes from thousands of unreviewed upstream PRs should not be merged blindly.
- GitHub secondary rate limits may stop mass creation. POST/PATCH calls are not automatically retried because a lost response could produce duplicate issues. Rerun after inspecting destination records.
- `--archive-path` is local storage. For GitHub Actions, upload the resulting file as an artifact; the run's ephemeral checkout is not a permanent archive.
- A large initial scan can take considerable time. Use smaller `--limit` values and keep a log of the last completed `--start-page`.

## Validation

```bash
cd misc/upstream_migration
python3 -m unittest -v test_migrate_upstream.py
```

The tests are standalone and perform **no network requests or GitHub writes**. The migration itself needs a separate, enabled GitHub destination and valid token for integration testing.
