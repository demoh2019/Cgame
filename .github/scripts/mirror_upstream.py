#!/usr/bin/env python3
"""Incremental, idempotent copy of upstream Godot issues and PRs into a fork.

GitHub does not permit transferring issues between unrelated repository owners.
Open PRs can be mirrored using their actual git head commits; historical PRs
are archived as issues because their original review/merge identity cannot be
recreated by the GitHub API.

This script is DRY RUN by default. Use --apply to create destination objects.
Requires Python 3.9+, git for --pr-mode=git, and GH_TOKEN for --apply.
"""

from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import time
from urllib.error import HTTPError
from urllib.parse import quote, urlsplit
from urllib.request import Request, urlopen

SOURCE_DEFAULT = "godotengine/godot"
DEST_DEFAULT = "demoh2019/godot"
MARKER_RE = re.compile(r"<!-- upstream-mirror: ([\w.-]+/[\w.-]+)/(issues|pull)/(\d+) -->")
SOURCE_LINK_RE = re.compile(r"https://github\.com/godotengine/godot/(pull|issues)/(\d+)")
WRITE_METHODS = {"POST", "PATCH", "PUT", "DELETE"}


class ApiError(RuntimeError):
    def __init__(self, status: int, text: str):
        self.status = status
        super().__init__(f"HTTP {status}: {text[:600]}")


def parse_next_link(header: str):
    """Follow GitHub's opaque cursor from the Link header, never increment page."""
    for entry in header.split(","):
        if 'rel="next"' not in entry:
            continue
        matched = re.search(r"<([^>]+)>", entry)
        if not matched:
            continue
        target = urlsplit(matched.group(1))
        if target.scheme != "https" or target.netloc != "api.github.com":
            raise ValueError("Unexpected pagination host")
        return target.path + ("?" + target.query if target.query else "")
    return None


class GitHub:
    def __init__(self, token: str = "", write_delay: float = 10.0, sleep=time.sleep):
        self.token = token
        self.write_delay = write_delay
        self.sleep = sleep
        self.last_write = 0.0

    def request(self, method: str, path: str, payload=None, with_links=False):
        if not (path.startswith("/repos/") or path.startswith("/repositories/")):
            raise ValueError("Only repository API paths are accepted")
        url = "https://api.github.com" + path
        headers = {
            "Accept": "application/vnd.github+json",
            "User-Agent": "godot-upstream-mirror/1.0",
            "X-GitHub-Api-Version": "2022-11-28",
        }
        if self.token:
            headers["Authorization"] = "Bearer " + self.token
        if method in WRITE_METHODS:
            if not self.token:
                raise RuntimeError("GH_TOKEN is required for writes")
            elapsed = time.monotonic() - self.last_write
            if self.last_write and elapsed < self.write_delay:
                self.sleep(self.write_delay - elapsed)
        data = None if payload is None else json.dumps(payload).encode()
        if data is not None:
            headers["Content-Type"] = "application/json"
        for attempt in range(5):
            req = Request(url, data=data, headers=headers, method=method)
            try:
                with urlopen(req, timeout=45) as response:
                    raw = response.read()
                    link_header = response.headers.get("Link", "")
                if method in WRITE_METHODS:
                    self.last_write = time.monotonic()
                result = json.loads(raw) if raw else {}
                return (result, parse_next_link(link_header)) if with_links else result
            except HTTPError as exc:
                message = exc.read().decode("utf-8", "replace")
                limited = exc.code == 429 or (
                    exc.code == 403 and (
                        "rate limit" in message.lower() or "abuse" in message.lower()
                    )
                )
                if not limited or attempt == 4:
                    raise ApiError(exc.code, message) from exc
                retry_after = exc.headers.get("Retry-After")
                reset = exc.headers.get("X-RateLimit-Reset")
                if retry_after:
                    pause = float(retry_after)
                elif exc.headers.get("X-RateLimit-Remaining") == "0" and reset:
                    pause = max(1, float(reset) - time.time() + 1)
                else:
                    pause = 60 * (2 ** attempt)
                print(f"Rate limited; pausing {pause:.0f}s", file=sys.stderr)
                self.sleep(min(pause, 3600))
        raise AssertionError("unreachable")

    def pages(self, path: str):
        if "per_page=" not in path:
            separator = "&" if "?" in path else "?"
            path += f"{separator}per_page=100"
        while path:
            batch, path = self.request("GET", path, with_links=True)
            yield from batch
            if not batch:
                break


def source_key(kind: str, number: int):
    return kind, int(number)


def source_url(source: str, kind: str, number: int):
    return f"https://github.com/{source}/{kind}/{number}"


def marker(source: str, kind: str, number: int):
    return f"<!-- upstream-mirror: {source}/{kind}/{number} -->"


def capped_body(body: str, original_url: str, max_bytes=60000):
    """Fit GitHub body limits without splitting UTF-8 or losing provenance."""
    raw = body.encode("utf-8")
    if len(raw) <= max_bytes:
        return body
    suffix = f"\n\n[Original content truncated. Full text: {original_url}]"
    budget = max_bytes - len(suffix.encode("utf-8"))
    return raw[:budget].decode("utf-8", "ignore") + suffix


def format_body(source: str, item: dict, kind: str, detail: dict | None = None):
    num = item["number"]
    author = (item.get("user") or {}).get("login", "unknown")
    labels = ", ".join("[" + l["name"] + "]" for l in item.get("labels", [])) or "(none)"
    assignees = ", ".join(a["login"] for a in item.get("assignees") or []) or "(none)"
    milestone = (item.get("milestone") or {}).get("title") or "(none)"
    data = detail or item
    original_body = data.get("body") or "(no description)"
    merged = f"\nOriginal merged-at: {detail.get('merged_at') or '(not merged)'}" if detail and kind == "pull" else ""
    body = (
        f"{marker(source, kind, num)}\n"
        f"Original: {source_url(source, kind, num)}\n\n"
        f"Original author: {author}\n"
        f"Original state: {item['state']}\n"
        f"Created: {item.get('created_at')}\n"
        f"Updated: {item.get('updated_at')}\n"
        f"Original labels: {labels}{merged}\n"
        f"Original assignees: {assignees}\n"
        f"Original milestone: {milestone}\n"
        f"Closed: {item.get('closed_at')}\n\n"
        "> Historical context: bare issue/PR references below refer to the upstream project.\n\n"
        "---\n\n"
        + original_body
    )
    return capped_body(body, source_url(source, kind, num))


def existing_keys(items, source=SOURCE_DEFAULT):
    """Explicit markers, plus original PR links in previously created fork PRs."""
    found = set()
    for item in items:
        body = item.get("body") or ""
        for match in MARKER_RE.finditer(body):
            if match.group(1) == source:
                found.add(source_key(match.group(2), int(match.group(3))))
        if item.get("pull_request") is not None:
            for match in SOURCE_LINK_RE.finditer(body):
                found.add(source_key(match.group(1), int(match.group(2))))
    return found


def git_run(directory, *args, check=True):
    process = subprocess.run(
        ["git", "-C", str(directory), *args],
        text=True, capture_output=True, check=False,
    )
    if check and process.returncode:
        raise RuntimeError(f"git {args[0]} failed: {process.stderr[:300]}")
    return process


class GitHeadMirror:
    def __init__(self, directory: Path, upstream: str, base_branch: str):
        self.directory = directory
        self.upstream = upstream
        self.base_branch = base_branch

    def push(self, number: int) -> bool:
        """Push upstream PR head preserving commits; return False if no base diff."""
        ref = f"refs/heads/upstream-mirror/pr-{number}"
        # Existing remote branches must never be force-pushed by the mirror.
        exists = git_run(self.directory, "ls-remote", "--heads", "origin", ref)
        if exists.stdout.strip():
            return True
        git_run(self.directory, "fetch", "--no-tags", "origin", self.base_branch)
        git_run(
            self.directory, "fetch", "--no-tags",
            f"https://github.com/{self.upstream}.git",
            f"refs/pull/{number}/head",
        )
        # No PR is possible when the original head has no changes vs fork base.
        diff = git_run(
            self.directory, "diff", "--quiet",
            f"origin/{self.base_branch}...FETCH_HEAD", check=False,
        )
        if diff.returncode == 0:
            return False
        if diff.returncode != 1:
            raise RuntimeError(f"Unable to diff upstream PR #{number}: {diff.stderr[:300]}")
        git_run(self.directory, "push", "origin", f"FETCH_HEAD:{ref}")
        return True


class Mirror:
    def __init__(
        self, api, source=SOURCE_DEFAULT, dest=DEST_DEFAULT,
        apply=False, comments=False, pr_mode="git", git_mirror=None,
    ):
        self.api, self.source, self.dest = api, source, dest
        self.apply, self.comments, self.pr_mode = apply, comments, pr_mode
        self.git_mirror = git_mirror
        self.present = set()
        self.mirrored_targets = {}
        self.stats = {"created_issues": 0, "created_prs": 0, "skipped": 0,
                      "dry_run": 0, "errors": 0}

    def check_destination(self):
        if not self.apply:
            return
        metadata = self.api.request("GET", f"/repos/{self.dest}")
        if metadata.get("has_issues") is False:
            raise RuntimeError(
                f"Issues are disabled in {self.dest}. "
                "Enable Settings > General > Features > Issues before migration."
            )

    def build_index(self):
        self.present = set()
        self.mirrored_targets = {}
        for record in self.api.pages(f"/repos/{self.dest}/issues?state=all"):
            self.present.update(existing_keys([record], self.source))
            for matched in MARKER_RE.finditer(record.get("body") or ""):
                if matched.group(1) != self.source:
                    continue
                key = source_key(matched.group(2), int(matched.group(3)))
                self.mirrored_targets[key] = (
                    record["number"], record.get("state"), bool(record.get("pull_request"))
                )
        print(f"Existing upstream references in destination: {len(self.present)}")

    def mirror_comments(self, upstream_num, destination_num):
        dest_comments = list(self.api.pages(
            f"/repos/{self.dest}/issues/{destination_num}/comments"
        ))
        copied = set()
        for comment in dest_comments:
            match = re.search(r"<!-- upstream-comment: (\d+) -->", comment.get("body") or "")
            if match:
                copied.add(int(match.group(1)))
        for item in self.api.pages(f"/repos/{self.source}/issues/{upstream_num}/comments"):
            if item["id"] in copied:
                continue
            login = (item.get("user") or {}).get("login", "unknown")
            body = (f"<!-- upstream-comment: {item['id']} -->\n"
                    f"From {item['html_url']} by {login} at {item['created_at']}:\n\n"
                    f"{item.get('body') or '(empty)'}")
            body = capped_body(body, item["html_url"])
            self.api.request("POST", f"/repos/{self.dest}/issues/{destination_num}/comments",
                             {"body": body})

    def create_archive(self, item, kind, detail=None):
        number = item["number"]
        prefix = "Upstream PR archive" if kind == "pull" else "Upstream issue"
        payload = {
            "title": f"[{prefix} #{number}] {item['title']}"[:250],
            "body": format_body(self.source, item, kind, detail),
        }
        result = self.api.request("POST", f"/repos/{self.dest}/issues", payload)
        created_number = result["number"]
        self.present.add(source_key(kind, number))
        self.mirrored_targets[source_key(kind, number)] = (
            created_number, item["state"], False
        )
        if self.comments:
            self.mirror_comments(number, created_number)
        if item["state"] == "closed":
            self.api.request("PATCH", f"/repos/{self.dest}/issues/{created_number}",
                             {"state": "closed"})
        self.stats["created_issues"] += 1
        print(f"Created issue #{created_number} for upstream {kind} #{number}")

    def create_pr(self, item, detail):
        number = item["number"]
        if self.pr_mode == "archive" or detail.get("state") != "open":
            return self.create_archive(item, "pull", detail)
        if not self.git_mirror:
            raise RuntimeError("Missing git checkout for PR branch migration")
        if not self.git_mirror.push(number):
            print(f"PR #{number} has no diff against fork base; archiving")
            return self.create_archive(item, "pull", detail)
        payload = {
            "title": item["title"][:250],
            "body": format_body(self.source, item, "pull", detail),
            "base": self.git_mirror.base_branch,
            "head": f"upstream-mirror/pr-{number}",
            "draft": True,
        }
        try:
            result = self.api.request("POST", f"/repos/{self.dest}/pulls", payload)
        except ApiError as exc:
            if exc.status != 422:
                raise
            print(f"PR #{number} could not be opened (422); archiving")
            return self.create_archive(item, "pull", detail)
        self.present.add(source_key("pull", number))
        self.mirrored_targets[source_key("pull", number)] = (
            result["number"], "open", True
        )
        if self.comments:
            self.mirror_comments(number, result["number"])
        self.stats["created_prs"] += 1
        print(f"Created draft PR #{result['number']} for upstream #{number}")

    def one(self, item):
        kind = "pull" if item.get("pull_request") else "issues"
        number = item["number"]
        key = source_key(kind, number)
        if key in self.present:
            # A previous run may have created an issue but stopped in the middle
            # of comments or before closing it. Repair that partial import.
            if self.apply and key in self.mirrored_targets:
                dest_number, dest_state, is_pr = self.mirrored_targets[key]
                if self.comments:
                    self.mirror_comments(number, dest_number)
                if item["state"] == "closed" and dest_state != "closed" and not is_pr:
                    self.api.request("PATCH", f"/repos/{self.dest}/issues/{dest_number}",
                                     {"state": "closed"})
            self.stats["skipped"] += 1
            return
        if not self.apply:
            self.stats["dry_run"] += 1
            print(f"DRY RUN {kind} #{number}: {item['title'][:70]}")
            return
        if kind == "pull":
            detail = self.api.request(
                "GET", f"/repos/{self.source}/pulls/{number}"
            )
            self.create_pr(item, detail)
        else:
            self.create_archive(item, kind)

    def run(self, start_page=1, pages=1, max_items=20, checkpoint=None,
            start_offset=0, start_cursor=None):
        self.check_destination()
        self.build_index()
        path = (start_cursor or
                f"/repos/{self.source}/issues"
                "?state=all&sort=created&direction=asc&per_page=100")
        source_metadata = self.api.request("GET", f"/repos/{self.source}")
        source_repo_id = str(source_metadata["id"])
        allowed = (path.startswith(f"/repos/{self.source}/issues?") or
                   path.startswith(f"/repositories/{source_repo_id}/issues?"))
        if not allowed:
            raise ValueError("Checkpoint cursor must target the source issue list")
        # Starting by page number is supported, but walking GitHub's cursor
        # links is mandatory. Random page=N access fails on large repositories.
        if start_page > 1 and not start_cursor:
            for skipped in range(1, start_page):
                _, path = self.api.request("GET", path, with_links=True)
                if not path:
                    return self.stats
        page = start_page
        processed = 0
        while path and (pages == 0 or page < start_page + pages):
            batch, next_path = self.api.request("GET", path, with_links=True)
            if not batch:
                break
            for offset, item in enumerate(batch):
                if page == start_page and offset < start_offset:
                    continue
                if processed >= max_items > 0:
                    return self.stats
                processed += 1
                try:
                    self.one(item)
                except Exception as exc:
                    self.stats["errors"] += 1
                    print(f"Failed upstream #{item.get('number')}: {exc}",
                          file=sys.stderr)
                    return self.stats
                if checkpoint and self.apply:
                    checkpoint.write_text(json.dumps(
                        {"next_page": page, "next_path": path,
                         "next_offset": offset + 1, "processed": processed},
                        indent=2) + "\n")
            page += 1
            path = next_path
            if checkpoint and self.apply:
                checkpoint.write_text(json.dumps(
                    {"next_page": page, "next_path": path,
                     "next_offset": 0, "processed": processed},
                    indent=2) + "\n")
        return self.stats


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", default=SOURCE_DEFAULT)
    parser.add_argument("--dest", default=DEST_DEFAULT)
    parser.add_argument("--start-page", type=int, default=1)
    parser.add_argument("--start-path", default="",
                        help="Opaque next_path from an earlier checkpoint; bypasses page walking")
    parser.add_argument("--start-offset", type=int, default=0,
                        help="0-based offset from the checkpoint on the cursor page")
    parser.add_argument("--pages", type=int, default=1,
                        help="Number of pages (0 = all remaining pages)")
    parser.add_argument("--max-items", type=int, default=20,
                        help="Items in this run (0 = unlimited)")
    parser.add_argument("--pr-mode", choices=["git", "archive"], default="git")
    parser.add_argument("--include-comments", action="store_true")
    parser.add_argument("--apply", action="store_true", help="Write changes to GitHub")
    parser.add_argument("--checkpoint", type=Path, default=Path("mirror-checkpoint.json"))
    parser.add_argument("--resume", action="store_true",
                        help="Read the next source page and offset from the checkpoint")
    parser.add_argument("--git-dir", type=Path, default=Path("."))
    parser.add_argument("--base-branch", default="master")
    parser.add_argument("--write-delay", type=float, default=10.0)
    args = parser.parse_args(argv)
    if args.start_page < 1 or args.pages < 0 or args.max_items < 0 or not (0 <= args.start_offset <= 100):
        parser.error("invalid pagination arguments")
    if args.apply and not os.environ.get("GH_TOKEN"):
        parser.error("Set GH_TOKEN to write to GitHub")
    api = GitHub(os.environ.get("GH_TOKEN", ""), write_delay=args.write_delay)
    git_mirror = GitHeadMirror(args.git_dir, args.source, args.base_branch)
    mirror = Mirror(api, args.source, args.dest, args.apply,
                    args.include_comments, args.pr_mode, git_mirror)
    start_page, start_offset = args.start_page, args.start_offset
    start_cursor = args.start_path or None
    if args.resume:
        if not args.checkpoint.exists():
            parser.error("Checkpoint not found; cannot resume")
        state = json.loads(args.checkpoint.read_text())
        start_page = int(state["next_page"])
        start_offset = int(state["next_offset"])
        start_cursor = state.get("next_path")
    stats = mirror.run(start_page, args.pages, args.max_items, args.checkpoint,
                       start_offset=start_offset, start_cursor=start_cursor)
    print("Summary:", json.dumps(stats, sort_keys=True))
    return 1 if stats["errors"] else 0


if __name__ == "__main__":
    sys.exit(main())
