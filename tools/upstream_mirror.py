#!/usr/bin/env python3
"""Resumable, attribution-preserving metadata mirror for godotengine/godot.

This tool imports upstream issues AND pull requests as tracking issues in a fork.
It does NOT transplant PR commits or impersonate authors/reviewers.

See docs in tools/UPSTREAM_MIRROR.md before running with write access.
"""

from __future__ import annotations

import argparse
import base64
import json
import os
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from dataclasses import asdict, dataclass
from typing import Any

API = "https://api.github.com"
SOURCE = "godotengine/godot"
DESTINATION = "demoh2019/Cgame"
STATE_BRANCH = "upstream-mirror-state"
STATE_PATH = "tools/upstream_mirror_state.json"
PAGE_SIZE = 100
MAX_BODY = 65_000
MARKER_RE = re.compile(r"<!-- upstream-mirror:godotengine/godot#(\d+) -->")


class APIError(RuntimeError):
    def __init__(self, status: int, message: str):
        super().__init__(f"GitHub API {status}: {message[:300]}")
        self.status = status


class GitHubAPI:
    def __init__(self, token: str, *, delay: float = 1.2, sleep=time.sleep):
        if not token:
            raise ValueError("Set GH_TOKEN or GITHUB_TOKEN")
        self.token = token
        self.delay = delay
        self.sleep = sleep

    def request(self, method: str, path: str, payload: dict | None = None) -> Any:
        assert path.startswith("/"), path
        url = API + path
        data = json.dumps(payload).encode("utf-8") if payload is not None else None
        headers = {
            "Accept": "application/vnd.github+json",
            "Authorization": f"Bearer {self.token}",
            "X-GitHub-Api-Version": "2022-11-28",
            "User-Agent": "godot-upstream-metadata-mirror",
        }
        if data is not None:
            headers["Content-Type"] = "application/json"
        for attempt in range(6):
            req = urllib.request.Request(url, data=data, method=method, headers=headers)
            try:
                with urllib.request.urlopen(req, timeout=40) as response:
                    content = response.read()
                    result = json.loads(content) if content else None
                if method != "GET" and self.delay:
                    self.sleep(self.delay)
                return result
            except urllib.error.HTTPError as exc:
                body = exc.read().decode("utf-8", errors="replace")
                retry_after = exc.headers.get("Retry-After")
                limited = exc.code in (403, 429) and (
                    retry_after or "rate limit" in body.lower() or "abuse detection" in body.lower()
                )
                transient = exc.code in (500, 502, 503, 504)
                if attempt < 5 and (limited or transient):
                    seconds = max(float(retry_after or 0), min(2**attempt * 5, 90))
                    print(f"retry {method} {path} ({exc.code}) in {seconds:.0f}s", file=sys.stderr)
                    self.sleep(seconds)
                    continue
                raise APIError(exc.code, body) from exc
            except urllib.error.URLError as exc:
                if attempt == 5:
                    raise RuntimeError(f"Network failure: {exc}") from exc
                self.sleep(min(2**attempt, 30))
        raise AssertionError("retry loop exhausted")


@dataclass
class State:
    page: int = 1
    offset: int = 0
    last_source_number: int = 0
    total_mirrored: int = 0
    finished: bool = False

    @classmethod
    def from_json(cls, obj: dict[str, Any]) -> "State":
        values = {name: obj[name] for name in cls.__dataclass_fields__ if name in obj}
        state = cls(**values)
        if state.page < 1 or not 0 <= state.offset < PAGE_SIZE or state.last_source_number < 0:
            raise ValueError(f"Bad checkpoint: {state}")
        return state


class RemoteCheckpoint:
    """A dedicated branch avoids state commits in the fork's master branch."""

    def __init__(self, api: GitHubAPI):
        self.api = api
        self.sha: str | None = None

    def load(self) -> State:
        path = urllib.parse.quote(STATE_PATH, safe="/")
        try:
            response = self.api.request(
                "GET", f"/repos/{DESTINATION}/contents/{path}?ref={STATE_BRANCH}"
            )
        except APIError as exc:
            if exc.status == 404:
                return State()
            raise
        self.sha = response["sha"]
        content = base64.b64decode(response["content"].replace("\n", ""))
        return State.from_json(json.loads(content))

    def _ensure_branch(self) -> None:
        try:
            self.api.request("GET", f"/repos/{DESTINATION}/git/ref/heads/{STATE_BRANCH}")
            return
        except APIError as exc:
            if exc.status != 404:
                raise
        base = self.api.request("GET", f"/repos/{DESTINATION}/git/ref/heads/master")
        try:
            self.api.request(
                "POST",
                f"/repos/{DESTINATION}/git/refs",
                {"ref": f"refs/heads/{STATE_BRANCH}", "sha": base["object"]["sha"]},
            )
        except APIError as exc:
            if exc.status != 422:  # another worker created it first
                raise

    def save(self, state: State) -> None:
        self._ensure_branch()
        payload = {
            "message": f"Mirror checkpoint after upstream #{state.last_source_number}",
            "branch": STATE_BRANCH,
            "content": base64.b64encode((json.dumps(asdict(state), indent=2) + "\n").encode()).decode(),
        }
        if self.sha:
            payload["sha"] = self.sha
        try:
            result = self.api.request("PUT", f"/repos/{DESTINATION}/contents/{STATE_PATH}", payload)
        except APIError as exc:
            # A previous process may have saved the state; never overwrite its work silently.
            if exc.status in (409, 422):
                raise RuntimeError("Concurrent checkpoint update; aborting") from exc
            raise
        self.sha = result["content"]["sha"]


def marker(number: int) -> str:
    return f"<!-- upstream-mirror:{SOURCE}#{number} -->"


def source_url(item: dict[str, Any]) -> str:
    if item.get("pull_request"):
        return f"https://github.com/{SOURCE}/pull/{item['number']}"
    return f"https://github.com/{SOURCE}/issues/{item['number']}"


def format_item(item: dict[str, Any], pr: dict | None = None) -> tuple[str, str, str]:
    number = int(item["number"])
    is_pr = bool(item.get("pull_request"))
    kind = "PR" if is_pr else "Issue"
    title = f"[Upstream {kind} #{number}] {item['title']}"[:256]
    link = source_url(item)
    labels = ", ".join(label["name"] for label in item.get("labels", [])) or "—"
    author = item.get("user") or {}
    status = "merged" if pr and pr.get("merged_at") else item["state"]
    lines = [
        f"{marker(number)}",
        f"Upstream source: {link}",
        "",
        f"Original author: @{author.get('login', 'unknown')}",
        f"Original status: `{status}`",
        f"Original created_at: {item.get('created_at', 'unknown')}",
        f"Original labels: {labels}",
        f"Original comments: {item.get('comments', 0)} (read on upstream)",
    ]
    if pr:
        lines += [
            f"Original base: `{pr['base']['ref']}`",
            f"Original head: `{pr['head']['label']}`",
            f"Original head SHA: `{pr['head']['sha']}`",
            f"Original draft: `{bool(pr.get('draft'))}`",
        ]
    if is_pr:
        lines += [
            "",
            "**This is a tracking issue, not a ported pull request.**",
            "No commits, reviews, checks or permissions have been transferred.",
            f"Review original changes at {link}/files.",
        ]
    lines += ["", "---", "", "### Original description", ""]
    header = "\n".join(lines)
    original = item.get("body") or "*(No description provided.)*"
    if len(header) + len(original) > MAX_BODY:
        original = original[: MAX_BODY - len(header) - 200] + (
            f"\n\n[Truncated; see original discussion]({link})"
        )
    return title, header + original, "upstream-mirror-pr" if is_pr else "upstream-mirror-issue"


class Mirror:
    def __init__(self, api: GitHubAPI, store: RemoteCheckpoint, *, dry_run: bool = False):
        self.api = api
        self.store = store
        self.dry_run = dry_run

    def preflight(self) -> None:
        repo = self.api.request("GET", f"/repos/{DESTINATION}")
        if not repo.get("has_issues") and not self.dry_run:
            raise RuntimeError(
                f"Issues are disabled in {DESTINATION}. Enable Settings > General > Features > Issues."
            )
        if self.dry_run:
            return
        for name, color, description in (
            ("upstream-mirror-issue", "2e86c1", "Mirror of a godotengine/godot issue"),
            ("upstream-mirror-pr", "a569bd", "Tracker for a godotengine/godot PR (not a code port)"),
        ):
            try:
                self.api.request("GET", f"/repos/{DESTINATION}/labels/{name}")
            except APIError as exc:
                if exc.status != 404:
                    raise
                try:
                    self.api.request("POST", f"/repos/{DESTINATION}/labels", {
                        "name": name, "color": color, "description": description,
                    })
                except APIError as create_exc:
                    if create_exc.status != 422:
                        raise

    def recover_last_source_number(self, state: State) -> None:
        """Recover a partially completed batch when a create succeeded before checkpoint save."""
        for page in range(1, 4):
            items = self.api.request(
                "GET", f"/repos/{DESTINATION}/issues?state=all&sort=created&direction=desc&per_page=100&page={page}"
            )
            if not items:
                break
            for item in items:
                matches = MARKER_RE.search(item.get("body") or "")
                if matches:
                    state.last_source_number = max(state.last_source_number, int(matches.group(1)))

    def run(self, *, max_items: int = 100, checkpoint_every: int = 20) -> State:
        if max_items < 1 or checkpoint_every < 1:
            raise ValueError("max_items and checkpoint_every must be positive")
        self.preflight()
        state = self.store.load()
        self.recover_last_source_number(state)
        # A previously completed pass may have new upstream items since the last run.
        state.finished = False

        count = 0
        since_checkpoint = 0
        while count < max_items:
            source_items = self.api.request(
                "GET", f"/repos/{SOURCE}/issues?state=all&sort=created&direction=asc&per_page={PAGE_SIZE}&page={state.page}"
            )
            if not source_items:
                state.finished = True
                break
            while state.offset < len(source_items) and count < max_items:
                item = source_items[state.offset]
                number = int(item["number"])
                if number > state.last_source_number:
                    pr = None
                    if item.get("pull_request"):
                        pr = self.api.request("GET", f"/repos/{SOURCE}/pulls/{number}")
                    title, body, label = format_item(item, pr)
                    if self.dry_run:
                        print(json.dumps({"number": number, "title": title, "label": label}, ensure_ascii=False))
                    else:
                        created = self.api.request("POST", f"/repos/{DESTINATION}/issues", {
                            "title": title, "body": body, "labels": [label],
                        })
                        if item["state"] == "closed":
                            self.api.request("PATCH", f"/repos/{DESTINATION}/issues/{created['number']}", {
                                "state": "closed", "state_reason": "completed",
                            })
                        print(f"mirrored #{number} -> {created['html_url']}", flush=True)
                    state.last_source_number = number
                    state.total_mirrored += 1
                    count += 1
                    since_checkpoint += 1
                state.offset += 1
                if not self.dry_run and since_checkpoint >= checkpoint_every:
                    self.store.save(state)
                    since_checkpoint = 0
            if state.offset >= len(source_items):
                if len(source_items) < PAGE_SIZE:
                    # Stay on the final partial page so later upstream items are seen.
                    state.finished = True
                    break
                state.page += 1
                state.offset = 0
        if not self.dry_run:
            self.store.save(state)
        return state


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--max-items", type=int, default=100)
    parser.add_argument("--checkpoint-every", type=int, default=20)
    parser.add_argument("--delay", type=float, default=1.2, help="Seconds after each GitHub write")
    parser.add_argument("--dry-run", action="store_true", help="Read-only preview; does not change checkpoint")
    args = parser.parse_args(argv)
    token = os.getenv("GH_TOKEN") or os.getenv("GITHUB_TOKEN")
    try:
        api = GitHubAPI(token, delay=args.delay)
        state = Mirror(api, RemoteCheckpoint(api), dry_run=args.dry_run).run(
            max_items=args.max_items, checkpoint_every=args.checkpoint_every
        )
    except (RuntimeError, ValueError, APIError) as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1
    print(json.dumps(asdict(state), indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
