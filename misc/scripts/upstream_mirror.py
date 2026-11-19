#!/usr/bin/env python3
"""Resumeable Godot upstream issue/PR migration (Python standard library only).

Archives the entire upstream issue timeline (GitHub's issues endpoint also includes
pull requests). Optionally recreates issues as linked issues in a fork and copies
open PR code into independent *draft* pull requests; never merges code into master.

WARNING: GitHub cannot preserve original issue/PR authorship, reviews, dates or IDs.
"""

from __future__ import annotations

import argparse
import gzip
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import time
from typing import Any
from urllib.error import HTTPError, URLError
from urllib.parse import quote, urlencode
from urllib.request import Request, urlopen

SOURCE = "godotengine/godot"
DEFAULT_STATE = ".github/upstream_mirror_state.json"
DEFAULT_ARCHIVE = "misc/upstream_archive"
PER_PAGE = 100
REPO_RE = re.compile(r"^[a-zA-Z0-9_.-]+/[a-zA-Z0-9_.-]+$")


class GitHubError(RuntimeError):
    def __init__(self, status: int, message: str):
        super().__init__(f"GitHub HTTP {status}: {message}")
        self.status = status


class GitHub:
    def __init__(self, token: str | None, *, api_base: str = "https://api.github.com", sleep=time.sleep):
        self.token = token
        self.api_base = api_base.rstrip("/")
        self.sleep = sleep

    def request(self, method: str, path: str, data: dict | None = None) -> Any:
        url = self.api_base + "/" + path.lstrip("/")
        raw = None if data is None else json.dumps(data).encode("utf-8")
        headers = {"Accept": "application/vnd.github+json", "X-GitHub-Api-Version": "2022-11-28", "User-Agent": "Godot-upstream-mirror"}
        if self.token:
            headers["Authorization"] = f"Bearer {self.token}"
        if raw is not None:
            headers["Content-Type"] = "application/json"
        for attempt in range(6):
            request = Request(url, data=raw, headers=headers, method=method)
            try:
                with urlopen(request, timeout=90) as resp:
                    body = resp.read()
                    return json.loads(body) if body else None
            except HTTPError as err:
                detail = err.read().decode("utf-8", "replace")[:350]
                retryable = err.code in (429, 500, 502, 503, 504) or (err.code == 403 and (err.headers.get("Retry-After") or err.headers.get("X-RateLimit-Remaining") == "0"))
                if retryable and attempt < 5:
                    delay = min(120, 2 ** attempt * 3)
                    wait = err.headers.get("Retry-After")
                    if wait and wait.isdigit():
                        delay = min(180, max(delay, int(wait)))
                    elif err.headers.get("X-RateLimit-Remaining") == "0":
                        reset = err.headers.get("X-RateLimit-Reset")
                        if reset and reset.isdigit():
                            delay = min(180, max(delay, int(reset) - int(time.time()) + 1))
                    self.sleep(delay)
                    continue
                raise GitHubError(err.code, detail) from err
            except (TimeoutError, URLError) as err:
                if attempt == 5:
                    raise RuntimeError(f"Transport failure for {method} {path}: {err}") from err
                self.sleep(min(60, 2 ** attempt * 3))
        raise AssertionError("retry loop exhausted")

    def get(self, path: str) -> Any:
        return self.request("GET", path)

    def post(self, path: str, data: dict) -> Any:
        return self.request("POST", path, data)

    def patch(self, path: str, data: dict) -> Any:
        return self.request("PATCH", path, data)


def validate_repo(repo: str) -> str:
    if not REPO_RE.fullmatch(repo) or ".." in repo:
        raise ValueError(f"Invalid owner/repository name: {repo!r}")
    return repo


def issue_page_path(source: str, page: int) -> str:
    return f"repos/{source}/issues?{urlencode({'state': 'all', 'sort': 'created', 'direction': 'asc', 'per_page': PER_PAGE, 'page': page})}"


def pr_page_path(source: str, page: int) -> str:
    return f"repos/{source}/pulls?{urlencode({'state': 'open', 'sort': 'created', 'direction': 'asc', 'per_page': PER_PAGE, 'page': page})}"


def default_state() -> dict:
    return {"version": 1, "source": SOURCE, "archive": {"next_page": 1, "complete": False},
            "issues": {"page": 1, "offset": 0, "copied": {}},
            "pr_records": {"page": 1, "offset": 0, "copied": {}},
            "prs": {"page": 1, "offset": 0, "results": {}}}


def load_state(path: Path, source: str) -> dict:
    state = json.loads(path.read_text(encoding="utf-8")) if path.is_file() else default_state()
    if state.get("version") != 1:
        raise ValueError("Unsupported state file version")
    if state.get("source") != source:
        if path.exists():
            raise ValueError("State belongs to a different upstream repository")
        state["source"] = source
    return state


def save_state(path: Path, state: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temp = path.with_name(path.name + ".tmp")
    temp.write_text(json.dumps(state, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    temp.replace(path)


def source_record_marker(source: str, number: int) -> str:
    return f"<!-- upstream-mirror:{source}#{number} -->"


def as_issue(source: str, original: dict) -> tuple[str, str]:
    """An audit-friendly linked copy, not a native cross-repository transfer."""
    number = original["number"]
    is_pr = "pull_request" in original
    author = original.get("user") or {}
    labels = ", ".join(label["name"] if isinstance(label, dict) else str(label) for label in original.get("labels", [])) or "none"
    source_url = original.get("html_url") or f"https://github.com/{source}/{'pull' if is_pr else 'issues'}/{number}"
    title = f"[Upstream {'PR' if is_pr else 'issue'} #{number}] {original['title']}"
    # Never claim that a linked issue is an actual GitHub PR or that the history is preserved.
    body = (f"{source_record_marker(source, number)}\n"
            f"**Mirror of:** {source_url}\n"
            f"**Record type:** {'Pull request (tracking issue only; code NOT imported)' if is_pr else 'Issue'}\n"
            f"**Original author:** @{author.get('login', 'unknown')}\n"
            f"**Original state:** {original.get('state', 'unknown')}\n"
            f"**Created:** {original.get('created_at', 'unknown')}\n"
            f"**Closed:** {original.get('closed_at') or 'not closed'}\n"
            f"**Labels:** {labels}\n"
            f"**Comments:** {original.get('comments', 0)} (see original discussion)\n\n"
            f"---\n\n{original.get('body') or '(No description)'}\n")
    return title[:256], body


def previous_mirrors(client: GitHub, target: str, source: str, *, max_pages: int = 3) -> dict[str, int]:
    """Recover recent issues when the previous run created issues but did not save its state."""
    seen: dict[str, int] = {}
    for page in range(1, max_pages + 1):
        path = f"repos/{target}/issues?{urlencode({'state': 'all', 'sort': 'created', 'direction': 'desc', 'per_page': PER_PAGE, 'page': page})}"
        items = client.get(path)
        for issue in items:
            if "pull_request" in issue:
                continue
            match = re.search(rf"<!-- upstream-mirror:{re.escape(source)}#(\d+) -->", issue.get("body") or "")
            if match:
                seen[match.group(1)] = issue["number"]
        if len(items) < PER_PAGE:
            break
    return seen


def archive_pages(client: GitHub, source: str, state: dict, root: Path, state_file: Path, pages: int, *, dry_run: bool) -> dict:
    progress = state["archive"]
    written = 0
    for _ in range(pages):
        if progress["complete"]:
            break
        number = progress["next_page"]
        records = client.get(issue_page_path(source, number))
        if not records:
            if not dry_run:
                progress["complete"] = True
                save_state(state_file, state)
            break
        path = root / f"page-{number:05d}.json.gz"
        if not dry_run:
            root.mkdir(parents=True, exist_ok=True)
            # Includes both issues and PR records; preserves all GitHub-returned fields.
            compressed = gzip.compress((json.dumps(records, ensure_ascii=False, sort_keys=True) + "\n").encode("utf-8"), mtime=0)
            path.write_bytes(compressed)
            progress["next_page"] += 1
            progress["complete"] = len(records) < PER_PAGE
            save_state(state_file, state)
        written += len(records)
        print(f"{'Would archive' if dry_run else 'Archived'} page {number}, {len(records)} records → {path}")
        if dry_run or len(records) < PER_PAGE:
            break
    return {"records": written, "next_page": progress["next_page"], "complete": progress["complete"]}


def mirror_issues(client: GitHub, source: str, target: str, state: dict, state_file: Path, limit: int, *, pr_records: bool, dry_run: bool, delay: float = 1.0) -> dict:
    repo = client.get(f"repos/{target}")
    if not repo.get("has_issues"):
        raise RuntimeError(f"Issues are disabled in {target}. Enable Settings > General > Features > Issues first.")
    if source == target:
        raise ValueError("Source and target must be different repositories")
    slot = "pr_records" if pr_records else "issues"
    progress = state[slot]
    recovered = previous_mirrors(client, target, source) if not dry_run else {}
    processed = 0
    created = 0
    while processed < limit:
        entries = client.get(issue_page_path(source, progress["page"]))
        if progress["offset"] >= len(entries):
            if not entries:
                break
            if not dry_run:
                progress["page"] += 1
                progress["offset"] = 0
                save_state(state_file, state)
            else:
                # Dry-run must not modify state; use local cursor below.
                break
            continue
        for entry in entries[progress["offset"]:]:
            if processed >= limit:
                break
            number = str(entry["number"])
            selected = ("pull_request" in entry) == pr_records
            if selected and number not in progress["copied"]:
                title, body = as_issue(source, entry)
                if dry_run:
                    print(f"Would copy {source}#{number} as an issue in {target}: {title[:100]}")
                elif number in recovered:
                    progress["copied"][number] = recovered[number]
                    print(f"Recovered {source}#{number} → {target}#{recovered[number]}")
                else:
                    created_record = client.post(f"repos/{target}/issues", {"title": title, "body": body})
                    progress["copied"][number] = created_record["number"]
                    created += 1
                    if entry.get("state") == "closed":
                        client.patch(f"repos/{target}/issues/{created_record['number']}", {"state": "closed"})
                    print(f"Copied {source}#{number} → {target}#{created_record['number']}")
                    time.sleep(delay)
            processed += 1
            if not dry_run:
                progress["offset"] += 1
                save_state(state_file, state)
        if dry_run:
            break
    return {"processed": processed, "created": created, "page": progress["page"], "offset": progress["offset"]}


def run_git(*args: str, cwd: Path | None = None, input_bytes: bytes | None = None, check: bool = True) -> subprocess.CompletedProcess:
    return subprocess.run(["git", *args], cwd=cwd, input=input_bytes, stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=check)


def port_pr(client: GitHub, source: str, target: str, pr: dict, base_branch: str, *, dry_run: bool) -> str:
    """Apply source PR's entire diff as a new branch; never merge into base.

    Failed patch application is recorded as a skip, never forced or partially pushed.
    This uses upstream refs/pull/<number>/head so the original branch may be deleted.
    """
    number = int(pr["number"])
    if pr.get("base", {}).get("ref") != base_branch:
        return f"skipped: base {pr.get('base', {}).get('ref')!r} != {base_branch!r}"
    if pr.get("draft"):
        return "skipped: source PR is itself a draft"
    branch = f"upstream-pr-{number}"
    if dry_run:
        return f"would port as draft branch {branch}"
    target_owner = target.split("/", 1)[0]
    # A push may have succeeded before API PR creation failed. Recover in that case.
    existing = client.get(f"repos/{target}/pulls?{urlencode({'state':'all', 'head':target_owner + ':' + branch, 'per_page':100})}")
    if existing:
        return f"already exists: {existing[0]['html_url']}"
    branch_exists = False
    try:
        client.get(f"repos/{target}/git/ref/heads/{branch}")
        branch_exists = True
    except GitHubError as err:
        if err.status != 404:
            raise
    if not branch_exists:
        source_git = f"https://github.com/{source}.git"
        source_sha = pr["base"]["sha"]
        run_git("fetch", "--no-tags", "--filter=blob:none", source_git, f"pull/{number}/head")
        head_sha = run_git("rev-parse", "FETCH_HEAD").stdout.decode().strip()
        run_git("fetch", "--no-tags", "--filter=blob:none", source_git, source_sha)
        diff = run_git("diff", "--binary", "--full-index", f"{source_sha}...{head_sha}").stdout
        if not diff:
            return "skipped: empty diff"
        with tempfile.TemporaryDirectory(prefix=f"godot-pr-{number}-") as temp_dir:
            path = Path(temp_dir) / "worktree"
            run_git("worktree", "add", "--detach", str(path), "HEAD")
            try:
                result = run_git("apply", "--3way", "--index", "-", cwd=path, input_bytes=diff, check=False)
                if result.returncode:
                    return "skipped: patch conflict: " + result.stderr.decode("utf-8", "replace")[-180:]
                if run_git("diff", "--cached", "--quiet", cwd=path, check=False).returncode == 0:
                    return "skipped: already applied"
                run_git("-c", "user.name=Godot Upstream Mirror", "-c", "user.email=mirror@users.noreply.github.com",
                        "commit", "-m", f"Port upstream PR #{number}: {pr['title'][:150]}\n\nUpstream: {pr['html_url']}", cwd=path)
                run_git("push", "origin", f"HEAD:refs/heads/{branch}", cwd=path)
            finally:
                run_git("worktree", "remove", "--force", str(path), check=False)
    body = (f"Automated *draft* port of [{source}#{number}]({pr['html_url']}).\n\n"
            f"Original author: @{pr.get('user', {}).get('login', 'unknown')}\n\n"
            f"This is a fresh, separate branch and is **not merged**. Review and add/run regression tests before merging. "
            f"Original GitHub reviews, approvals, and timestamps cannot be transferred.\n\n"
            f"### Original PR description\n\n{pr.get('body') or '(No description)'}")
    result = client.post(f"repos/{target}/pulls", {"title": f"[Upstream #{number}] {pr['title']}"[:256],
                                                       "head": branch, "base": base_branch, "draft": True, "body": body})
    return "created: " + result["html_url"]


def mirror_prs(client: GitHub, source: str, target: str, state: dict, state_file: Path, limit: int, *, base_branch: str, dry_run: bool) -> dict:
    progress = state["prs"]
    processed = 0
    while processed < limit:
        entries = client.get(pr_page_path(source, progress["page"]))
        if progress["offset"] >= len(entries):
            if not entries:
                break
            if not dry_run:
                progress["page"] += 1
                progress["offset"] = 0
                save_state(state_file, state)
            else:
                break
            continue
        for pr in entries[progress["offset"]:]:
            if processed >= limit:
                break
            key = str(pr["number"])
            if key not in progress["results"]:
                try:
                    outcome = port_pr(client, source, target, pr, base_branch, dry_run=dry_run)
                except (subprocess.CalledProcessError, GitHubError) as exc:
                    outcome = f"failed: {str(exc)[:240]}"
                print(f"PR #{key}: {outcome}")
                if not dry_run:
                    progress["results"][key] = outcome
            processed += 1
            if not dry_run:
                progress["offset"] += 1
                save_state(state_file, state)
        if dry_run:
            break
    return {"processed": processed, "page": progress["page"], "offset": progress["offset"]}


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode", choices=("archive", "issues", "pr-records", "prs"))
    parser.add_argument("--source", default=SOURCE)
    parser.add_argument("--target", default=os.environ.get("GITHUB_REPOSITORY", "demoh2019/godot"))
    parser.add_argument("--state", type=Path, default=Path(DEFAULT_STATE))
    parser.add_argument("--archive-dir", type=Path, default=Path(DEFAULT_ARCHIVE))
    parser.add_argument("--limit", type=int, default=20, help="Source records to process this run (max 100 for issues/PRs)")
    parser.add_argument("--pages", type=int, default=10, help="Archive pages this run (100 records per page)")
    parser.add_argument("--base-branch", default="master")
    parser.add_argument("--dry-run", action="store_true", help="Preview only; no writes, branch creation or state changes")
    args = parser.parse_args(argv)
    try:
        source, target = validate_repo(args.source), validate_repo(args.target)
        if not 1 <= args.limit <= 100 or not 1 <= args.pages <= 100:
            parser.error("--limit and --pages must be in range 1..100")
        if source == target:
            parser.error("--source and --target must differ")
        client = GitHub(os.environ.get("GITHUB_TOKEN"))
        state = load_state(args.state, source)
        if args.mode == "archive":
            report = archive_pages(client, source, state, args.archive_dir, args.state, args.pages, dry_run=args.dry_run)
        elif args.mode in ("issues", "pr-records"):
            if not os.environ.get("GITHUB_TOKEN") and not args.dry_run:
                parser.error("GITHUB_TOKEN required for writes")
            report = mirror_issues(client, source, target, state, args.state, args.limit,
                                   pr_records=(args.mode == "pr-records"), dry_run=args.dry_run)
        else:
            if not os.environ.get("GITHUB_TOKEN") and not args.dry_run:
                parser.error("GITHUB_TOKEN required for writes")
            report = mirror_prs(client, source, target, state, args.state, args.limit,
                                base_branch=args.base_branch, dry_run=args.dry_run)
        print(json.dumps(report, sort_keys=True))
        return 0
    except (GitHubError, RuntimeError, ValueError) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
