# Upstream Godot issue/PR mirroring

This is an **opt-in**, rate-limited, idempotent bulk mirror for GitHub issues and pull requests from `godotengine/godot` to `demoh2019/godot`. Nothing is written by default.

- Source issues are copied with title, body, original author attribution, source URL, and open/closed state. GitHub will show the importing account as the creator; original author cannot be impersonated. Original comments/reviews, assignees, milestones, labels, and attachments are **not re-created**; links in issue bodies still point to the original location.
- Open upstream pull requests attempt a true draft PR mirror: fetch `refs/pull/N/head` and push to a dedicated `upstream-port/pr-N` branch, then create a draft PR targeting the **same** base branch in the fork. If a base branch is absent, the PR is safely skipped rather than silently retargeted to master. Existing local ports are detected and skipped.
- Closed/merged PRs usually cannot be re-created as meaningful PRs (their changes may already exist in `master`); they are stored as closed archival issues with source links and full original descriptions.
- No code is auto-merged. New PRs are **unverified drafts** until the full Godot build and tests pass.
- Existing mirrored records are detected by a machine-readable `upstream-source` HTML marker, and previously hand-ported PRs are detected from original PR links where available.
- Paginated REST `/issues` is used instead of Search, avoiding the 1000 search-result limit. Large migrations will still take many runs owing to GitHub API and Actions quotas.

## Using GitHub Actions

First enable **Issues** in fork Settings → General → Features; otherwise GitHub rejects imported issues with HTTP 410. Also enable GitHub Actions for the fork and grant the workflow read/write permissions with **Allow GitHub Actions to create and approve pull requests** (Settings → Actions → General). After merging the pull request introducing this workflow into the **default branch**, go to **Actions → Mirror upstream Godot issues and pull requests → Run workflow**. Start with a dry run (apply=false). Then select `apply=true`, `kind=issues` and a small `limit` (25). Use `kind=prs` for pull request code branches. Use `state=all` to include the entire historical record, including closed/merged items. Set `start_page` if advancing through the upstream results; GitHub REST issues pages include PRs. Stop and inspect each batch to avoid overwhelming the fork.

For a local dry run:

```bash
python3 -m unittest discover -s scripts/upstream_sync/tests -v
python3 scripts/upstream_sync/sync_upstream.py --state open --kind all --limit 25
```

For real writes from an authenticated target checkout (token must be able to write issues, PRs, and contents):

```bash
export GITHUB_TOKEN=... # Do not commit or print secrets.
python3 scripts/upstream_sync/sync_upstream.py --kind all --state all --limit 25 --apply
```

When `--limit` stops in mid-page, the next run safely skips already created records, but at high volume later `--start-page` reduces repeated scanning. If a GitHub API write is interrupted between creating an issue and closing it, the next run will skip it based on marker; its state must be corrected manually. GitHub Actions environments may need fork Actions enabled in the repository settings.