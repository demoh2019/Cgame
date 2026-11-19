#!/usr/bin/env python3
"""Resume-safe GitHub issue migration and selective open-PR backports.

Requires Python 3.10+, GITHUB_TOKEN, and (for PR backports) a local git checkout.
Read MIGRATION.md before using --apply. Dry-run is the default.
"""
from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
import tempfile
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Iterator
from urllib.error import HTTPError, URLError
from urllib.parse import urlencode, urlparse
from urllib.request import Request, urlopen

SOURCE = "godotengine/godot"
TARGET = "demoh2019/Cgame"
TARGET_BASE = "develop"
API_ROOT = "https://api.github.com"
ISSUE_RE = re.compile(r"(?:https://github\.com/)?godotengine/godot/issues/(\d+)")
PR_RE = re.compile(r"(?:https://github\.com/)?godotengine/godot/pull/(\d+)")
COMMENT_RE = re.compile(r"upstream-comment-id:\s*(\d+)")


class GitHubError(RuntimeError):
    def __init__(self, status: int, message: str):
        super().__init__(f"GitHub HTTP {status}: {message}")
        self.status = status


class GitHub:
    def __init__(self, token: str, *, pause: float = 0.35):
        if not token:
            raise ValueError("GITHUB_TOKEN is required for any GitHub operation")
        self.token = token
        self.pause = pause

    def request(self, method: str, path: str, data: Any = None) -> tuple[Any, dict[str, str]]:
        """Only GET calls are retried; a lost POST response must not duplicate writes."""
        method = method.upper()
        if not path.startswith("/repos/"):
            raise ValueError("Only repository-scoped GitHub API URLs are allowed")
        url = API_ROOT + path
        payload = json.dumps(data).encode("utf-8") if data is not None else None
        request = Request(url, method=method, data=payload, headers={
            "Authorization": f"Bearer {self.token}",
            "Accept": "application/vnd.github+json",
            "X-GitHub-Api-Version": "2022-11-28",
            "User-Agent": "godot-upstream-migrate/1.0",
            "Content-Type": "application/json",
        })
        for attempt in range(5):
            time.sleep(self.pause)
            try:
                with urlopen(request, timeout=60) as response:
                    data_bytes = response.read()
                    body = json.loads(data_bytes) if data_bytes else None
                    return body, dict(response.headers.items())
            except HTTPError as exc:
                response_text = exc.read().decode("utf-8", "replace")[:1000]
                headers = dict(exc.headers.items())
                retryable = method == "GET" and (exc.code in (403, 429, 500, 502, 503, 504))
                if retryable and attempt < 4:
                    remaining = headers.get("X-RateLimit-Remaining")
                    reset = headers.get("X-RateLimit-Reset")
                    retry_after = headers.get("Retry-After")
                    if remaining == "0" and reset and reset.isdigit():
                        delay = min(3700, max(1, int(reset) - int(time.time()) + 2))
                    elif retry_after and retry_after.isdigit():
                        delay = min(3700, int(retry_after))
                    else:
                        delay = min(120, 2 ** attempt * 5)
                    print(f"GET rate limit/server error {exc.code}; retrying in {delay}s", file=sys.stderr)
                    time.sleep(delay)
                    continue
                raise GitHubError(exc.code, response_text) from exc
            except URLError as exc:
                if method == "GET" and attempt < 4:
                    time.sleep(2 ** attempt)
                    continue
                raise RuntimeError(f"GitHub connection failed: {exc.reason}") from exc
        raise RuntimeError("Retry limit reached")

    def get(self, path: str) -> Any:
        return self.request("GET", path)[0]

    def post(self, path: str, body: dict) -> Any:
        return self.request("POST", path, body)[0]

    def patch(self, path: str, body: dict) -> Any:
        return self.request("PATCH", path, body)[0]

    def pages(self, path: str) -> Iterator[dict]:
        """Follow Link next within the same repository endpoint, without 1000-item search limits."""
        visited: set[str] = set()
        while path:
            if path in visited:
                raise ValueError("GitHub pagination loop detected")
            visited.add(path)
            data, headers = self.request("GET", path)
            if not isinstance(data, list):
                raise ValueError(f"Expected a GitHub list for {path}")
            yield from data
            next_path = ""
            for value in headers.get("Link", headers.get("link", "")).split(","):
                match = re.search(r'<([^>]+)>;\s*rel="next"', value)
                if not match:
                    continue
                url = urlparse(match.group(1))
                if url.scheme != "https" or url.netloc != "api.github.com":
                    raise ValueError("Unsafe pagination host")
                next_path = url.path + ("?" + url.query if url.query else "")
                if not next_path.startswith("/repos/"):
                    raise ValueError("Unsafe pagination path")
            path = next_path


def page_path(repo: str, kind: str, state: str, start_page: int = 1) -> str:
    if kind not in ("issues", "pulls") or state not in ("open", "closed", "all"):
        raise ValueError("Invalid list parameters")
    return f"/repos/{repo}/{kind}?{urlencode({'state': state, 'per_page': 100, 'sort': 'created', 'direction': 'asc', 'page': start_page})}"


def origin_issue_number(body: str | None) -> int | None:
    m = ISSUE_RE.search(body or "")
    return int(m.group(1)) if m else None


def origin_pr_number(body: str | None, title: str = "") -> int | None:
    m = PR_RE.search(body or "")
    if m:
        return int(m.group(1))
    # Existing manual backports sometimes mention the upstream number only in the title.
    for s in (body or "", title):
        m = re.search(r"(?:upstream|backport|port)\b[^\n]{0,80}?#(\d+)", s, re.I)
        if m:
            return int(m.group(1))
    return None


def issue_body(item: dict) -> str:
    num = item["number"]
    original = f"https://github.com/{SOURCE}/issues/{num}"
    author = (item.get("user") or {}).get("login", "unknown")
    labels = ", ".join("`" + l["name"] + "`" for l in item.get("labels", []) if isinstance(l, dict)) or "none"
    text = item.get("body") or ""
    return (f"> Migrated from {original}\n"
            f"> Originally submitted by @{author} on {item.get('created_at', '?')}; "
            f"last updated {item.get('updated_at', '?')}.\n"
            f"> Upstream state: {item.get('state', 'unknown')}; labels: {labels}.\n"
            "> This copy is independent. Original discussion and attachments remain linked above.\n\n"
            f"<!-- upstream-issue: {SOURCE}#{num} -->\n\n---\n\n{text}")


def pr_archive_body(item: dict) -> str:
    num = item["number"]
    author = (item.get("user") or {}).get("login", "unknown")
    state = "merged" if item.get("merged_at") else item.get("state", "unknown")
    return (f"> Archived upstream PR: https://github.com/{SOURCE}/pull/{num}\n"
            f"> Original author: @{author}; originally created {item.get('created_at','?')}.\n"
            f"> Upstream state: **{state}**. This is a historical record, not an open code PR.\n\n"
            f"<!-- upstream-pr: {SOURCE}#{num} -->\n\n---\n\n{item.get('body') or ''}")


def imported_comment(comment: dict) -> str:
    author = (comment.get("user") or {}).get("login", "unknown")
    link = comment.get("html_url") or ""
    return (f"> Imported comment from @{author} on {comment.get('created_at','?')}.\n"
            f"> Original: {link}\n\n"
            f"<!-- upstream-comment-id: {comment['id']} -->\n\n{comment.get('body') or ''}")


def target_indexes(api: GitHub) -> tuple[dict[int, dict], dict[int, dict], dict[int, dict]]:
    """Read destination once, rather than rate-limited GitHub search for each item."""
    issues: dict[int, dict] = {}
    archives: dict[int, dict] = {}
    prs: dict[int, dict] = {}
    for item in api.pages(page_path(TARGET, "issues", "all")):
        if item.get("pull_request"):
            continue
        n = origin_issue_number(item.get("body"))
        if n is not None:
            issues[n] = item
        m = re.search(rf"(?:https://github\.com/)?{re.escape(SOURCE)}/pull/(\d+)", item.get("body") or "")
        if m:
            archives[int(m.group(1))] = item
    for item in api.pages(page_path(TARGET, "pulls", "all")):
        n = origin_pr_number(item.get("body"), item.get("title", ""))
        if n is not None:
            prs[n] = item
    return issues, archives, prs


def ensure_label(api: GitHub, name: str, color: str = "ededed", description: str = "") -> None:
    """Ensure label exists; 422 means another process created it concurrently."""
    try:
        api.post(f"/repos/{TARGET}/labels", {"name": name, "color": color or "ededed", "description": description or ""})
    except GitHubError as exc:
        if exc.status != 422:
            raise


@dataclass
class Settings:
    apply: bool = False
    limit: int = 20
    include_closed: bool = True
    comments: bool = False
    code: bool = False
    archive_closed_prs: bool = False
    repo_path: str = "."
    archive_path: str = ""
    start_page: int = 1


def migrate_issues(api: GitHub, settings: Settings, existing: dict[int, dict]) -> dict[str, int]:
    stats = {"scanned": 0, "created": 0, "existing": 0, "comments": 0}
    state = "all" if settings.include_closed else "open"
    existing_labels: set[str] = set()
    if settings.apply:
        existing_labels = {label["name"] for label in api.pages(f"/repos/{TARGET}/labels?per_page=100")}
    for item in api.pages(page_path(SOURCE, "issues", state, settings.start_page)):
        if item.get("pull_request"):
            continue
        if stats["scanned"] >= settings.limit:
            break
        stats["scanned"] += 1
        n = item["number"]
        if n in existing:
            target = existing[n]
            stats["existing"] += 1
        elif not settings.apply:
            print(f"DRY-RUN issue #{n}: {item['title']}")
            continue
        else:
            labels = []
            for l in item.get("labels", []):
                if not isinstance(l, dict):
                    continue
                if l["name"] not in existing_labels:
                    ensure_label(api, l["name"], l.get("color", "ededed"), l.get("description") or "")
                    existing_labels.add(l["name"])
                labels.append(l["name"])
            try:
                target = api.post(f"/repos/{TARGET}/issues", {
                    "title": item["title"], "body": issue_body(item), "labels": labels,
                })
            except GitHubError as exc:
                if exc.status == 410:
                    raise RuntimeError(f"Issues are disabled in {TARGET}. Enable Settings > General > Features > Issues first.") from exc
                raise
            existing[n] = target
            stats["created"] += 1
            print(f"Created issue #{target['number']} from upstream #{n}")
            if item.get("state") == "closed":
                api.patch(f"/repos/{TARGET}/issues/{target['number']}", {"state": "closed"})
        if settings.apply and settings.comments:
            target_num = target["number"]
            present = {int(m.group(1)) for c in api.pages(f"/repos/{TARGET}/issues/{target_num}/comments?per_page=100")
                       if (m := COMMENT_RE.search(c.get("body") or ""))}
            for comment in api.pages(f"/repos/{SOURCE}/issues/{n}/comments?per_page=100"):
                if comment["id"] not in present:
                    api.post(f"/repos/{TARGET}/issues/{target_num}/comments", {"body": imported_comment(comment)})
                    present.add(comment["id"])
                    stats["comments"] += 1
    return stats


def git(*args: str, cwd: str = ".", input_data: bytes | None = None) -> subprocess.CompletedProcess[bytes]:
    return subprocess.run(["git", *args], cwd=cwd, input=input_data, stdout=subprocess.PIPE,
                          stderr=subprocess.PIPE, check=True)


def backport_pr(api: GitHub, item: dict, repo_path: str) -> str:
    """Apply a PR's merge-base diff as a draft; never push if patch conflicts or is empty."""
    n = item["number"]
    branch = f"upstream-pr-{n}"
    path = str(Path(repo_path).resolve())
    # Verify expected repository checkout and existence of git remotes.
    remotes = git("remote", "-v", cwd=path).stdout.decode("utf-8", "replace")
    if SOURCE not in remotes or TARGET not in remotes:
        raise ValueError(f"Checkout needs remotes for both {SOURCE} and {TARGET}")
    git("fetch", "--no-tags", "upstream", "refs/heads/master:refs/remotes/upstream/master", cwd=path)
    git("fetch", "--no-tags", "upstream", f"refs/pull/{n}/head", cwd=path)
    pr_head = git("rev-parse", "FETCH_HEAD", cwd=path).stdout.decode().strip()
    git("fetch", "--no-tags", "origin", f"refs/heads/{TARGET_BASE}:refs/remotes/origin/{TARGET_BASE}", cwd=path)
    merge_base = git("merge-base", "upstream/master", pr_head, cwd=path).stdout.decode().strip()
    patch = git("diff", "--binary", merge_base, pr_head, cwd=path).stdout
    if not patch:
        return "empty"
    with tempfile.TemporaryDirectory(prefix=f"godot-pr-{n}-") as tmp:
        worktree = str(Path(tmp) / "tree")
        git("worktree", "add", "--detach", worktree, f"origin/{TARGET_BASE}", cwd=path)
        try:
            try:
                git("apply", "--3way", "--index", "-", cwd=worktree, input_data=patch)
            except subprocess.CalledProcessError:
                return "conflict"
            staged = git("diff", "--cached", "--name-only", cwd=worktree).stdout
            if not staged.strip():
                return "already-applied"
            git("-c", "user.name=Godot migration", "-c", "user.email=actions@users.noreply.github.com",
                "commit", "-m", f"Backport upstream godotengine/godot#{n}", cwd=worktree)
            # Never overwrite an existing branch; concurrent/previous imports are left untouched.
            git("push", "origin", f"HEAD:refs/heads/{branch}", cwd=worktree)
        finally:
            git("worktree", "remove", "--force", worktree, cwd=path)
    author = (item.get("user") or {}).get("login", "unknown")
    body = (f"Backport of https://github.com/{SOURCE}/pull/{n}\n\n"
            f"Original contributor: @{author}.\n\n{item.get('body') or ''}\n\n"
            "**Migration notice:** AI/automation-assisted patch application; review and run the full CI/test suite before merge. "
            "The original source PR may still change.")
    result = api.post(f"/repos/{TARGET}/pulls", {
        "title": f"[Upstream #{n}] {item['title']}", "head": branch, "base": TARGET_BASE,
        "draft": True, "body": body,
    })
    return result.get("html_url", "created")


def migrate_prs(api: GitHub, settings: Settings, existing_prs: dict[int, dict],
                archives: dict[int, dict]) -> dict[str, int]:
    stats = {"scanned": 0, "created": 0, "existing": 0, "archived": 0, "skipped": 0, "conflicts": 0}
    state = "all" if settings.include_closed else "open"
    # JSONL archives are append-only, but repeat runs must not duplicate PR records.
    archived_ids: set[int] = set()
    if settings.archive_path and settings.apply and Path(settings.archive_path).exists():
        with open(settings.archive_path, encoding="utf-8") as previous:
            for line in previous:
                if line.strip():
                    archived_ids.add(int(json.loads(line)["number"]))
    archive_file = open(settings.archive_path, "a", encoding="utf-8") if settings.archive_path and settings.apply else None
    try:
        for item in api.pages(page_path(SOURCE, "pulls", state, settings.start_page)):
            if stats["scanned"] >= settings.limit:
                break
            stats["scanned"] += 1
            n = item["number"]
            if n in existing_prs or n in archives:
                stats["existing"] += 1
                continue
            open_pr = item.get("state") == "open" and not item.get("merged_at")
            # Never apply an older maintenance branch (3.x, 4.6...) onto master.
            base_ref = (item.get("base") or {}).get("ref", "master")
            if archive_file and n not in archived_ids:
                archive_file.write(json.dumps({k: item.get(k) for k in
                    ("number", "title", "body", "state", "created_at", "closed_at", "merged_at", "html_url")}, ensure_ascii=False) + "\n")
                archive_file.flush()
                archived_ids.add(n)
            if open_pr and settings.code and base_ref == "master":
                if not settings.apply:
                    print(f"DRY-RUN PR #{n}: {item['title']}")
                    continue
                try:
                    outcome = backport_pr(api, item, settings.repo_path)
                    if outcome in ("empty", "already-applied", "conflict"):
                        stats["conflicts" if outcome == "conflict" else "skipped"] += 1
                        print(f"Skipped PR #{n}: {outcome}")
                    else:
                        stats["created"] += 1
                        print(f"Created PR from upstream #{n}: {outcome}")
                except (ValueError, subprocess.CalledProcessError, GitHubError) as exc:
                    stats["conflicts"] += 1
                    print(f"PR #{n} needs manual intervention: {exc}", file=sys.stderr)
                continue
            if settings.archive_closed_prs and not open_pr:
                if not settings.apply:
                    print(f"DRY-RUN archived historical PR #{n}: {item['title']}")
                    continue
                target = api.post(f"/repos/{TARGET}/issues", {
                    "title": f"[Upstream PR #{n} — archived] {item['title']}",
                    "body": pr_archive_body(item),
                })
                api.patch(f"/repos/{TARGET}/issues/{target['number']}", {"state": "closed"})
                archives[n] = target
                stats["archived"] += 1
            else:
                stats["skipped"] += 1
    finally:
        if archive_file:
            archive_file.close()
    return stats


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("kind", choices=("issues", "prs"))
    parser.add_argument("--apply", action="store_true", help="Actually write to destination; default is dry-run")
    parser.add_argument("--limit", type=int, default=20, help="Maximum source items per run (default: 20)")
    parser.add_argument("--open-only", action="store_true", help="Ignore closed upstream records")
    parser.add_argument("--comments", action="store_true", help="Copy issue comments with attribution, including when resuming")
    parser.add_argument("--code", action="store_true", help="Attempt to import open PRs with git patch application")
    parser.add_argument("--archive-closed-prs", action="store_true", help="Archive merged/closed PRs as closed issues")
    parser.add_argument("--repo-path", default=".", help="Git checkout with origin=fork, upstream=source")
    parser.add_argument("--archive-path", default="", help="Append PR summaries to JSONL file")
    parser.add_argument("--start-page", type=int, default=1,
                        help="1-based upstream listing page for incremental batches; pages contain 100 entries")
    parser.add_argument("--pause", type=float, default=0.35, help="Pause between API calls")
    a = parser.parse_args(argv)
    if a.limit < 1 or a.pause < 0 or a.start_page < 1:
        parser.error("--limit/--start-page must be positive and --pause nonnegative")
    return a


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    api = GitHub(os.environ.get("GITHUB_TOKEN", ""), pause=args.pause)
    settings = Settings(apply=args.apply, limit=args.limit, include_closed=not args.open_only,
                        comments=args.comments, code=args.code, archive_closed_prs=args.archive_closed_prs,
                        repo_path=args.repo_path, archive_path=args.archive_path, start_page=args.start_page)
    repo = api.get(f"/repos/{TARGET}")
    if (args.kind == "issues" or args.archive_closed_prs) and not repo.get("has_issues", False):
        print(f"BLOCKED: {TARGET} has Issues disabled. Enable Settings > General > Features > Issues.", file=sys.stderr)
        return 2
    issue_index, archive_index, pr_index = target_indexes(api)
    if args.kind == "issues":
        stats = migrate_issues(api, settings, issue_index)
    else:
        stats = migrate_prs(api, settings, pr_index, archive_index)
    print(json.dumps(stats, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (GitHubError, ValueError, RuntimeError) as error:
        print(f"Migration stopped: {error}", file=sys.stderr)
        sys.exit(1)
