# Importing Godot upstream issues and pull requests

This repository is a fork of [godotengine/godot](https://github.com/godotengine/godot).

The upstream issue and PR history is very large (over 120,000 records at the time this was written). This importer intentionally runs in **small, resumable batches**. It does not silently start a background migration on installation.

## Prerequisites

1. In [fork settings](https://github.com/demoh2019/godot/settings), open **General → Features → Issues**, and enable **Issues**. GitHub reports `has_issues: false` for this fork at the time of implementation. All modes except `open-prs` fail fast until this is enabled.
2. Review and merge the mirror tooling PR into the fork's default branch.
3. In **Actions** enable workflows for this fork if prompted. For the workflow, grant **read/write** permissions and allow Actions to create pull requests, or configure a fine-grained PAT secret named `MIRROR_TOKEN` with target **Contents**, **Issues**, and **Pull requests** write permissions. This token must be kept in GitHub Secrets, **never** committed.
4. Open **Actions → Upstream Issue and PR Mirror → Run workflow**. Start with `issues` and `max_new=25`; repeat runs after checking logs and the state file. `max_new=0` means unlimited and may run into rate limits or job time limits. To use `all` or `open-prs`, explicitly enable `allow_untrusted_pr_import` only after auditing Actions workflows and fork secrets: upstream PR code may be untrusted and can trigger CI on same-repository branches.

Alternatively, with Python 3.9+, Git and a checkout of the fork:

```sh
export GH_TOKEN="$(gh auth token)"
python3 misc/scripts/mirror_upstream_github.py --mode issues --max-new 25
# After auditing Actions security, include --allow-untrusted-pr-import for --mode all or open-prs.
python3 -m unittest discover -s tests/mirror -p 'test_*.py' -v
```

Save and reuse `.github/upstream-mirror-state.json` across invocations. The workflow automatically commits the checkpoint after each run. Local operators should also preserve that file; losing it can cause duplicate imports. **Do not run two imports concurrently using the same checkpoint**.

## What is imported

| Source type | Destination | Status |
| --- | --- | --- |
| Open issue | Issue | Open, source text/labels/attribution link and optional conversation comments |
| Closed issue | Issue | Closed, source text/labels/attribution link and optional conversation comments |
| Open PR | Draft PR | Actual Git branch fetched from upstream `refs/pull/N/head`, pushed to a dedicated `upstream-mirror/pr-N` branch |
| Closed or merged PR | Archived Issue | Source title, description, link, comments and original state noted |

Merged and closed PRs **cannot be cloned into new merged PRs** with their original merge commits, author identities, review history, timestamps, and original PR numbers using the ordinary GitHub REST API. They are imported as searchable archival issues instead. Open PR code still requires review, merge-conflict resolution, and tests; the importer does **not** merge PRs.

The tool preserves original authors as text, not as impersonated GitHub authors. It does **not** preserve milestone, assignee, reactions, inline review threads, exact historical dates in GitHub metadata, and some other GitHub-native history. Large bodies are partially moved into a continuation comment. Files referenced by URLs may remain attached to the upstream repository rather than being re-uploaded.

## Safety and diagnostics

- Before creating open PRs, scans existing destination PR descriptions for explicit upstream `/pull/N` references to avoid duplicate backports.
- Uses stable source issue numbers and checkpoint records to avoid re-creating items on subsequent runs.
- Retries rate-limit and transient server errors, pauses between writes, and records per-item failures in the checkpoint for later investigation.
- The default batch limit is 25 new records. API/Git errors are logged instead of being silently treated as success.
- Large migrations can generate notifications, consume rate limits, create thousands of branches, and grow the fork substantially. Monitor quota and repository size.
- No script should be run with a personal token of more privilege than necessary.

## Different modes

- `--mode issues`: Only upstream issues, open and closed.
- `--mode open-prs`: Only open upstream PRs; can run even when Issues is disabled, but requires a Git checkout with authenticated `origin`.
- `--mode archive-prs`: Only closed and merged upstream PRs as archival issues.
- `--mode all`: All of the above, with closed PRs archived as issues.

The import is **best effort, not an exact relocation** of GitHub-native object history. Follow the GitHub API constraints and review pull requests before merging.
