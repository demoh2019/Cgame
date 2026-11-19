# Mirror upstream Godot issues and PRs into this fork

Source: `godotengine/godot`. Destination: `demoh2019/godot`.

**Prerequisite:** At initial inspection the fork had `has_issues=false`. To enable
migration, visit **Settings → General → Features → Issues** in
`demoh2019/godot` and turn Issues on. GitHub returns HTTP 410 for every Issue
creation while this remains disabled. The CLI now refuses an applied run
immediately rather than partially importing objects.

This is a **copy**, never a GitHub transfer. GitHub cannot transfer Issues across
unrelated owners, nor can it reproduce original PR numbers, authorship, approvals,
review threads and merge history in a different repository.

## Scope

- Every upstream Issue, open or closed, can be represented as a new Issue with
  original author, timestamps, labels (as metadata), source URL and description.
  Closed source Issues are closed in the destination after copying.
- Open upstream PRs become **real draft PRs** when `--pr-mode git` is used:
  their original Git head commits are fetched from upstream's
  `refs/pull/<n>/head`, pushed into destination branch
  `upstream-mirror/pr-<n>`, and compared against fork `master`.
- Closed/merged PRs, and open PRs without a diff against `master`, become
  **archival Issues**, not fake empty PRs.
- `--include-comments` copies top-level Issue/PR conversation comments with
  author/date/link attribution. GitHub review states, thread resolution, inline
  review positions, attachments, reactions, assignees and original creation
  timestamps of the new GitHub objects cannot be preserved automatically.
- Existing destination objects are scanned for unique provenance markers.
  Previously opened PRs referencing an upstream PR URL are also recognized
  to avoid duplicating fixes already present in this fork.

## Safe local use

You need Python 3.9+, `git` and a fresh checkout of the destination repository
with an authenticated writable `origin` remote. `GH_TOKEN` must have access
to create issues, branches and pull requests in the destination.

Dry run, first 20 upstream issues/PRs in chronological order:

```sh
python3 .github/scripts/mirror_upstream.py --start-page 1 --pages 1 --max-items 20
```

Apply up to 20:

```sh
export GH_TOKEN='...'
python3 .github/scripts/mirror_upstream.py --apply \
  --start-page 1 --pages 1 --max-items 20 --include-comments
```

Run across remaining pages, until stopped by the provider, process, or a failed
operation (prefer small batches). This can run for days or weeks because of
provider limits:

```sh
python3 .github/scripts/mirror_upstream.py --apply --pages 0 \
  --max-items 0 --checkpoint mirror-checkpoint.json --include-comments
```

Continue from the saved checkpoint **after an applied run**:

```sh
python3 .github/scripts/mirror_upstream.py --apply --resume \
  --pages 0 --max-items 0 --checkpoint mirror-checkpoint.json \
  --include-comments
```

Do not paste a token into issue descriptions, workflow inputs or output logs.
For large runs prefer GitHub Actions using its built-in `GITHUB_TOKEN`.

## GitHub Actions

After merging this tooling PR into the fork's default branch, use
**Actions → Upstream issue and PR mirror → Run workflow**. Start with
`apply=false` for a dry run. For live copying set `apply=true` and use
small increments of `start_page`, `pages` and `max_items`; open PRs are
drafts. Each run uploads its checkpoint as an artifact. A GitHub-hosted
runner is limited in time. To continue in GitHub Actions, copy `next_path`,
`next_offset`, and `next_page` from the downloaded checkpoint JSON into
the inputs `start_path`, `start_offset`, and `start_page`. A local CLI
run can instead pass `--resume` and read its existing checkpoint file.

**Important pagination detail:** GitHub no longer supports page=N requests
past a certain point for large issue collections. This migrator follows
opaque `Link: rel="next"` cursors instead. Starting at a large `start_page`
will traverse preceding cursor links; passing `--start-path` from the
previous checkpoint is considerably more efficient.

**Do not run multiple batches concurrently**. The workflow uses a concurrency
group to prevent overlapping migration writes.

## Tests

```sh
python3 -m compileall -q .github/scripts
python3 -m unittest discover -s .github/scripts/tests -v
```

The migrator is idempotent based on unique provenance markers. Failed migration
halts without advancing its checkpoint past the failed item. GitHub secondary
rate limits are handled with Retry-After/Reset backoff. Default writes are
paced at one every 10 seconds; further throttling may still occur.

Before bulk import: decide whether cloning over 123,000 upstream records into a
fork is truly desirable. This will massively change the usability of the fork's
issue tracker, cause notifications, and consume significant API capacity.
