# godotengine/godot issue and PR metadata mirror

This tool is **not a GitHub issue transfer** and **does not transplant pull-request code**.
It creates new issues in `demoh2019/Cgame`, preserving the upstream URL,
original author and status, labels as text, description, and key PR metadata.
For upstream pull requests, the destination entry is explicitly marked as a
**tracking issue**; reviews, branch commits, checks, and original authorship
cannot be recreated by changing the creator of a GitHub issue.

The upstream is very large (about 64k issues and 59k PRs on 2026-11-19).
Mirroring everything means creating over 123k new destination issues and can
take many batches. It may trigger GitHub's anti-spam or rate limits, and can
be expensive to administer. Read before enabling scheduled writes.

## Setup

1. Enable **Settings → General → Features → Issues** in `demoh2019/Cgame`.
   The feature is currently disabled. Without it the script refuses all writes.
2. Merge the tooling PR into the destination repository.
3. In **Actions**, open **Mirror upstream Godot issue and PR metadata**.
   First use `workflow_dispatch` with `dry_run=true`, then a small value (e.g.
   `max_items=5`) with `dry_run=false` to check the resulting issues.
4. To continue at a controlled cadence, set repository variable
   `UPSTREAM_MIRROR_ENABLED=true` in **Settings → Secrets and variables → Actions**.
   The workflow will then run once every 3 hours and process up to 100 entries.
   Without this variable, scheduled runs are skipped. To stop it, set the
   variable to false or disable the workflow.

## CLI

```sh
GH_TOKEN=... python3 tools/upstream_mirror.py --max-items 10 --dry-run
GH_TOKEN=... python3 tools/upstream_mirror.py --max-items 100 --checkpoint-every 20 --delay 1.5
python3 -m unittest discover -s tools -p test_upstream_mirror.py -v
```

The token must have Issues write and Contents write permissions on the fork;
no upstream write permission is needed. The checkpoint is stored only on
`upstream-mirror-state`, never on `master`. The importer uses the repository
Issues API (not capped GitHub search results), which includes PR entries.
A unique source marker and a short scan of recently created destination issues
help it recover after a crash. The `concurrency` group prevents overlapping
scheduled/manual runs in the repository. The script continues from the last
source page and offset, including new upstream items appended after the last
page. It does not update already mirrored records when upstream titles,
comments or state later change.

**Caveats:** GitHub create limits may stop a batch; restart later to resume.
The recent-record recovery is best effort, not a cross-repository atomic
transaction. If you run the tool simultaneously from outside Actions,
verify duplicates manually. The full set of historical comments/reviews and
all original labels, assignees, milestones and reactions are not re-created.
Keep the upstream links for the authoritative history.

## PR code ports

Do not confuse a mirrored upstream PR tracker with a real destination PR.
Merged upstream PRs are already represented by the synchronized `master` code.
For unmerged PRs, port the diff onto a branch targeting the correct fork base,
check license and attribution, compile, run unit/regression/integration tests,
and open a **separate draft PR** after evaluating conflicts and superseded PRs.
Do not mass-merge all upstream open PRs; many are experimental, conflict with
one another or have unresolved review notes.

This metadata-only mirror intentionally uses a separate workflow from the existing upstream code/PR mirror. Scheduled runs are read-only; GitHub writes require explicit workflow dispatch with dry-run disabled.
