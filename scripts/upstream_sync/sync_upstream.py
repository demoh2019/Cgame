#!/usr/bin/env python3
"""Idempotent, bounded upstream Godot issue/PR migration (Python stdlib only).

Runs with `GITHUB_TOKEN` in the TARGET repository. No writes unless --apply.
For live PRs, run from a git checkout of the target with a writable `origin`.
Closed/merged PRs cannot generally be reopened as meaningful PRs and are
archived as issues (with their state and a link to the original code review).
"""
from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from typing import Any, Iterator

ORIGIN_MARKER = "<!-- upstream-source: {repo}/{kind}/{number} -->"
USER_AGENT = "godot-upstream-migrator/1.0"


class APIError(RuntimeError):
    pass


class GitHub:
    def __init__(self, token: str, *, api_root: str = "https://api.github.com", retry_sleep=time.sleep):
        self.token = token
        self.api_root = api_root.rstrip("/")
        self.retry_sleep = retry_sleep

    def request(self, method: str, path: str, payload: Any = None):
        url = path if path.startswith("https://") else self.api_root + path
        body = json.dumps(payload).encode("utf-8") if payload is not None else None
        headers = {"Accept": "application/vnd.github+json", "User-Agent": USER_AGENT,
                   "X-GitHub-Api-Version": "2022-11-28"}
        if self.token:
            headers["Authorization"] = f"Bearer {self.token}"
        if body is not None:
            headers["Content-Type"] = "application/json"
        for attempt in range(4):
            req = urllib.request.Request(url, body, headers, method=method)
            try:
                with urllib.request.urlopen(req, timeout=45) as res:
                    data = res.read()
                    return (json.loads(data) if data else None, res.headers)
            except urllib.error.HTTPError as err:
                content = err.read().decode("utf-8", "replace")[:600]
                # Do not blindly retry secondary-rate-limit errors; exit cleanly.
                if err.code in (429, 500, 502, 503, 504) and attempt < 3:
                    self.retry_sleep(min(30, 2 ** attempt + 1))
                    continue
                raise APIError(f"GitHub {method} {url}: HTTP {err.code}: {content}") from err
            except urllib.error.URLError as err:
                if attempt == 3:
                    raise APIError(f"Network error for {url}: {err}") from err
                self.retry_sleep(min(30, 2 ** attempt + 1))
        raise AssertionError("unreachable")

    def get(self, path):
        return self.request("GET", path)[0]

    def post(self, path, payload):
        return self.request("POST", path, payload)[0]

    def patch(self, path, payload):
        return self.request("PATCH", path, payload)[0]

    def pages(self, path: str, *, start_page: int = 1) -> Iterator[list[dict]]:
        # Using REST pagination rather than Search avoids Search's 1000-result cap.
        page = start_page
        while True:
            sep = "&" if "?" in path else "?"
            data = self.get(f"{path}{sep}per_page=100&page={page}")
            if not isinstance(data, list):
                raise APIError(f"Expected paginated JSON array: {path}")
            if not data:
                return
            yield data
            if len(data) < 100:
                return
            page += 1


def ref_marker(source: str, kind: str, number: int) -> str:
    return ORIGIN_MARKER.format(repo=source, kind=kind, number=number)


def parse_origin(body: str | None):
    if not body:
        return None
    match = re.search(r"<!-- upstream-source: ([\w.-]+/[\w.-]+)/(issues|pull)/(\d+) -->", body)
    if match:
        return match.group(1), match.group(2), int(match.group(3))
    return None


def existing_upstream_pr(title: str | None, body: str | None, source: str):
    # Accommodate previously hand-ported Godot PRs that lack our new marker.
    text = (title or "") + "\n" + (body or "")
    match = re.search(r"https://github\.com/" + re.escape(source) + r"/pull/(\d+)\b", text)
    if match:
        return int(match.group(1))
    # Require a clear up/backport mention, not a bare #number (often issue IDs).
    match = re.search(r"(?:upstream|backport|port(?:ed)?\s+(?:from\s+)?upstream)\s*#(\d+)\b", text, re.I)
    if match:
        return int(match.group(1))
    return None


def body_for_item(item: dict, source: str, kind: str) -> str:
    number = item["number"]
    author = (item.get("user") or {}).get("login", "unknown")
    state = item.get("state", "unknown")
    original_url = item.get("html_url", f"https://github.com/{source}/{kind}/{number}")
    metadata = [ref_marker(source, kind, number),
                f"> Imported from [{source}#{number}]({original_url}).",
                f"> Original author: @{author}. Original state: **{state}**.",
                "> This is a copy; the original discussion and review history remain at the source URL."]
    if kind == "pull":
        metadata.append("> A closed or merged upstream PR is archived as an issue, not falsely represented as a live code PR.")
    return "\n".join(metadata) + "\n\n" + (item.get("body") or "")


def project_label_names(item: dict):
    return [label["name"] if isinstance(label, dict) else label for label in item.get("labels") or []]


class Migrator:
    def __init__(self, api: GitHub, source: str, target: str, *, apply: bool,
                 limit: int, kind: str, state: str, start_page: int,
                 sleep_seconds: float = 1.0, git_runner=subprocess.run):
        if source == target:
            raise ValueError("Source and target must differ")
        self.api, self.source, self.target = api, source, target
        self.apply, self.limit, self.kind, self.state = apply, limit, kind, state
        self.start_page, self.sleep_seconds = start_page, sleep_seconds
        self.git_runner = git_runner
        self.done = 0
        self.skipped = 0
        self.failed = 0
        self.duplicates: set[tuple[str, str, int]] = set()
        self.existing_prs: set[int] = set()

    def load_existing(self):
        for page in self.api.pages(f"/repos/{self.target}/issues?state=all"):
            for item in page:
                key = parse_origin(item.get("body"))
                if key:
                    self.duplicates.add(key)
        for page in self.api.pages(f"/repos/{self.target}/pulls?state=all"):
            for item in page:
                key = parse_origin(item.get("body"))
                if key and key[0] == self.source and key[1] == "pull":
                    self.existing_prs.add(key[2])
                old_number = existing_upstream_pr(item.get("title"), item.get("body"), self.source)
                if old_number is not None:
                    self.existing_prs.add(old_number)

    def create_issue(self, item: dict, kind: str):
        number = item["number"]
        key = (self.source, kind, number)
        if key in self.duplicates or (kind == "pull" and number in self.existing_prs):
            self.skipped += 1
            return
        title = ("[Upstream PR archive] " if kind == "pull" else "[Upstream] ") + item["title"]
        print(f"{'CREATE' if self.apply else 'DRY RUN'} issue {kind}#{number}: {title[:90]}", flush=True)
        if self.apply:
            result = self.api.post(f"/repos/{self.target}/issues", {
                "title": title,
                "body": body_for_item(item, self.source, kind),
                # Do not import upstream assignees/labels: fork may not have those
                # collaborators or label definitions.
            })
            if item.get("state") == "closed":
                close_reason = item.get("state_reason")
                patch = {"state": "closed"}
                if close_reason in {"completed", "not_planned"}:
                    patch["state_reason"] = close_reason
                self.api.patch(f"/repos/{self.target}/issues/{result['number']}", patch)
            self.duplicates.add(key)
            self.throttle()
        self.done += 1

    def throttle(self):
        if self.sleep_seconds > 0:
            time.sleep(self.sleep_seconds)

    def _git(self, args: list[str]):
        result = self.git_runner(["git", *args], check=False, capture_output=True, text=True)
        if result.returncode != 0:
            raise RuntimeError(f"git {args[0]} failed: {result.stderr[-500:]}")

    def port_pr(self, item: dict):
        number = item["number"]
        if number in self.existing_prs:
            self.skipped += 1
            return
        key = (self.source, "pull", number)
        if key in self.duplicates:
            self.skipped += 1
            return
        if item["state"] == "closed":
            self.create_issue(item, "pull")
            return
        detail = self.api.get(f"/repos/{self.source}/pulls/{number}")
        base = detail["base"]["ref"]
        # Never silently retarget PRs from stable branches to master.
        try:
            self.api.get(f"/repos/{self.target}/branches/{urllib.parse.quote(base, safe='')}")
        except APIError:
            print(f"SKIP PR#{number}: target base branch {base!r} not present", flush=True)
            self.skipped += 1
            return
        branch = f"upstream-port/pr-{number}"
        print(f"{'CREATE' if self.apply else 'DRY RUN'} draft PR#{number}: {branch} -> {base}", flush=True)
        if self.apply:
            # Fetch the exact original PR head including its commit tree, not a
            # reconstructed patch. `origin` must already be authenticated.
            self._git(["fetch", "--no-tags", "https://github.com/" + self.source + ".git",
                       f"refs/pull/{number}/head"])
            self._git(["push", "origin", f"FETCH_HEAD:refs/heads/{branch}"])
            try:
                created = self.api.post(f"/repos/{self.target}/pulls", {
                    "title": f"[Upstream #{number}] {item['title']}",
                    "head": branch, "base": base, "draft": True,
                    "body": body_for_item(item, self.source, "pull") +
                            "\n\n**Testing:** This PR is an unverified code mirror. Review, build and run tests before merging.\n",
                })
                print(f"CREATED {created.get('html_url')}", flush=True)
            except APIError as err:
                # Most commonly there is no code diff because already merged.
                print(f"PR#{number} cannot be opened ({err}); archiving as issue", flush=True)
                self.create_issue(item, "pull")
                return
            self.existing_prs.add(number)
            self.throttle()
        self.done += 1

    def run(self):
        self.load_existing()
        route = f"/repos/{self.source}/issues?state={self.state}&sort=created&direction=asc"
        # Issues REST API includes PRs. Iterate once with no search 1000 cap.
        for page in self.api.pages(route, start_page=self.start_page):
            for item in page:
                if self.limit and self.done >= self.limit:
                    print("BATCH LIMIT reached. Resume with a later page or rerun idempotently.", flush=True)
                    return
                number = item["number"]
                is_pr = "pull_request" in item
                if is_pr and self.kind == "issues":
                    continue
                if not is_pr and self.kind == "prs":
                    continue
                try:
                    if is_pr:
                        self.port_pr(item)
                    else:
                        self.create_issue(item, "issues")
                except (APIError, RuntimeError) as err:
                    self.failed += 1
                    print(f"ERROR upstream #{number}: {err}", file=sys.stderr, flush=True)
                    # Avoid producing partial duplicate records after API failures;
                    # stop rather than blindly retrying this page.
                    raise
        print("Source items exhausted", flush=True)


def parse_args(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", default="godotengine/godot")
    parser.add_argument("--target", default="demoh2019/godot")
    parser.add_argument("--kind", choices=["issues", "prs", "all"], default="all")
    parser.add_argument("--state", choices=["open", "all"], default="all")
    parser.add_argument("--start-page", type=int, default=1)
    parser.add_argument("--limit", type=int, default=25, help="Maximum NEW records per run (0 = unlimited)")
    parser.add_argument("--sleep", type=float, default=1.0)
    parser.add_argument("--apply", action="store_true", help="Perform GitHub writes (dry-run by default)")
    args = parser.parse_args(argv)
    if args.start_page < 1 or args.limit < 0 or args.sleep < 0:
        parser.error("start-page >= 1, limit >= 0 and sleep >= 0 required")
    for name in (args.source, args.target):
        if not re.fullmatch(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", name):
            parser.error(f"Invalid repository: {name}")
    return args


def main(argv=None):
    args = parse_args(argv)
    token = os.environ.get("GITHUB_TOKEN", "")
    if args.apply and not token:
        raise SystemExit("GITHUB_TOKEN is required for --apply")
    migrator = Migrator(GitHub(token), args.source, args.target, apply=args.apply,
                        limit=args.limit, kind=args.kind, state=args.state,
                        start_page=args.start_page, sleep_seconds=args.sleep)
    try:
        migrator.run()
    finally:
        print(f"Summary: created/planned={migrator.done}, already-present/skipped={migrator.skipped}, failed={migrator.failed}", flush=True)


if __name__ == "__main__":
    main()