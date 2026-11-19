#!/usr/bin/env python3
"""Best-effort, resumable mirror of upstream GitHub issues and pull requests.

Requires Python 3.9+, a checkout of the target repository for open PRs,
and GH_TOKEN with target issue/PR/content permissions.
"""
import argparse
import json
import os
import re
import subprocess
import sys
import tempfile
import time
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.parse import quote
from urllib.request import Request, urlopen

SOURCE = "godotengine/godot"
TARGET = "demoh2019/godot"
API_ROOT = "https://api.github.com"
NEXT_LINK = re.compile(r'<([^>]+)>;\s*rel="next"')
UPSTREAM_PR_LINK = re.compile(r"https://github\.com/godotengine/godot/pull/(\d+)")
BODY_LIMIT = 58000


class ApiError(RuntimeError):
    pass


class Api:
    def __init__(self, token, pause=1.0, opener=urlopen, sleep=time.sleep):
        self.token = token
        self.pause = pause
        self.opener = opener
        self.sleep = sleep

    def request(self, method, path, payload=None, with_headers=False):
        url = path if path.startswith("https://") else API_ROOT + path
        data = None if payload is None else json.dumps(payload).encode("utf-8")
        headers = {
            "Accept": "application/vnd.github+json",
            "Authorization": "Bearer " + self.token,
            "User-Agent": "godot-upstream-mirror/1",
            "X-GitHub-Api-Version": "2022-11-28",
        }
        if data is not None:
            headers["Content-Type"] = "application/json"
        for attempt in range(6):
            try:
                req = Request(url, data=data, headers=headers, method=method)
                with self.opener(req, timeout=90) as response:
                    raw = response.read()
                    result = json.loads(raw) if raw else {}
                    response_headers = {name.lower(): value for name, value in response.headers.items()}
                if method != "GET" and self.pause:
                    self.sleep(self.pause)
                return (result, response_headers) if with_headers else result
            except HTTPError as exc:
                retryable = exc.code in (429, 502, 503, 504) or (
                    exc.code == 403 and (
                        exc.headers.get("Retry-After")
                        or exc.headers.get("X-RateLimit-Remaining") == "0"
                    )
                )
                if not retryable or attempt == 5:
                    detail = exc.read().decode("utf-8", "replace")[:500]
                    raise ApiError(f"{method} {url}: HTTP {exc.code} {detail}") from exc
                wait = exc.headers.get("Retry-After")
                if wait and wait.isdigit():
                    delay = min(300, max(1, int(wait)))
                elif exc.headers.get("X-RateLimit-Remaining") == "0":
                    reset = int(exc.headers.get("X-RateLimit-Reset", "0"))
                    delay = min(300, max(1, reset - int(time.time()) + 1))
                else:
                    delay = min(120, 2 ** (attempt + 2))
                self.sleep(delay)
            except URLError as exc:
                if attempt == 5:
                    raise ApiError(f"Network error: {exc}") from exc
                self.sleep(min(60, 2 ** (attempt + 1)))
        raise AssertionError("unreachable")

    def pages(self, path):
        while path:
            values, headers = self.request("GET", path, with_headers=True)
            if not isinstance(values, list):
                raise ApiError("Expected a paginated GitHub list at " + path)
            yield from values
            next_match = NEXT_LINK.search(headers.get("link", ""))
            path = next_match.group(1) if next_match else None


def source_key(item, kind):
    return f"{kind}:{item['number']}"


def original_marker(number, kind):
    return f"<!-- upstream-mirror:{SOURCE}#{number}:{kind} -->"


def source_description(item, kind, extra=""):
    n = item["number"]
    source_type = "pull" if kind in ("pr", "archive-pr") else "issues"
    link = f"https://github.com/{SOURCE}/{source_type}/{n}"
    user = (item.get("user") or {}).get("login") or "unknown"
    lines = [
        original_marker(n, kind),
        f"Imported from {link}",
        f"Original author: @{user}",
        f"Original created_at: {item.get('created_at', 'unknown')}",
        f"Original state: {item.get('state', 'unknown')}",
    ]
    if extra:
        lines.append(extra)
    lines.append("\n---\n")
    return "\n".join(lines) + (item.get("body") or "")


def split_body(body, limit=BODY_LIMIT):
    if len(body) <= limit:
        return body, None
    return body[:limit] + "\n\n[Original body continues in a mirror comment.]", body[limit:]


def comment_description(comment):
    user = (comment.get("user") or {}).get("login") or "unknown"
    return (
        f"Imported upstream comment by @{user}, "
        f"{comment.get('created_at', 'unknown')}\n"
        f"Source: {comment.get('html_url', '')}\n\n"
        + (comment.get("body") or "")
    )


def existing_upstream_pr_numbers(pulls):
    result = {}
    for pr in pulls:
        body = pr.get("body") or ""
        for n in UPSTREAM_PR_LINK.findall(body):
            result[int(n)] = {"number": pr["number"], "url": pr["html_url"],
                              "existing": True, "done": True, "comments_complete": True}
    return result


class Mirror:
    def __init__(self, api, state_path, mode, max_new=25, comments=True, git_dir="."):
        self.api = api
        self.path = Path(state_path)
        self.mode = mode
        self.max_new = max_new
        self.comments = comments
        self.git_dir = git_dir
        self.state = json.loads(self.path.read_text("utf-8")) if self.path.exists() else {"entries": {}, "errors": {}}
        self.state.setdefault("entries", {})
        self.state.setdefault("errors", {})
        self.labels = set()
        self.count = 0

    def save(self):
        self.path.parent.mkdir(parents=True, exist_ok=True)
        fd, temp = tempfile.mkstemp(prefix=self.path.name + ".", dir=str(self.path.parent))
        try:
            with os.fdopen(fd, "w", encoding="utf-8") as stream:
                json.dump(self.state, stream, ensure_ascii=False, indent=2, sort_keys=True)
                stream.write("\n")
            os.replace(temp, self.path)
        finally:
            if os.path.exists(temp):
                os.unlink(temp)

    def ensure_labels(self, item):
        names = []
        for label in item.get("labels") or []:
            name = label.get("name") if isinstance(label, dict) else str(label)
            if not name:
                continue
            if name not in self.labels:
                try:
                    self.api.request("POST", f"/repos/{TARGET}/labels", {
                        "name": name,
                        "color": (label.get("color") if isinstance(label, dict) else None) or "dddddd",
                        "description": ((label.get("description") if isinstance(label, dict) else "") or "")[:100],
                    })
                except ApiError as exc:
                    # Labels may already exist. Only use valid labels in this run.
                    existing = self.api.request("GET", f"/repos/{TARGET}/labels/{quote(name, safe='')}")
                    if existing.get("name") != name:
                        raise exc
                self.labels.add(name)
            names.append(name)
        return names

    def import_comments(self, source_number, destination_number, entry):
        if not self.comments or entry.get("comments_complete"):
            return
        uri = f"/repos/{SOURCE}/issues/{source_number}/comments?per_page=100"
        last_id = entry.get("last_comment_id", 0)
        for comment in self.api.pages(uri):
            if comment["id"] <= last_id:
                continue
            self.api.request("POST", f"/repos/{TARGET}/issues/{destination_number}/comments", {
                "body": comment_description(comment)
            })
            entry["last_comment_id"] = comment["id"]
            self.save()
        entry["comments_complete"] = True
        self.save()

    def copy_issue(self, item, kind="issue"):
        key = source_key(item, kind)
        entry = self.state["entries"].get(key)
        if entry is None:
            if self.max_new and self.count >= self.max_new:
                return False
            desc = source_description(item, kind, "Archived original PR (cannot preserve the original merged/closed PR state)." if kind == "archive-pr" else "")
            body, continuation = split_body(desc)
            title = f"[Upstream PR #{item['number']}] {item['title']}" if kind == "archive-pr" else item["title"]
            result = self.api.request("POST", f"/repos/{TARGET}/issues", {
                "title": title[:256], "body": body, "labels": self.ensure_labels(item),
            })
            entry = {"number": result["number"], "url": result["html_url"], "done": False}
            self.state["entries"][key] = entry
            self.save()
            self.count += 1
            if continuation:
                self.api.request("POST", f"/repos/{TARGET}/issues/{entry['number']}/comments", {
                    "body": "Continuation of original issue/PR body:\n\n" + continuation
                })
        if not entry.get("done"):
            if item.get("state") == "closed":
                self.api.request("PATCH", f"/repos/{TARGET}/issues/{entry['number']}", {"state": "closed"})
            entry["done"] = True
            self.save()
        self.import_comments(item["number"], entry["number"], entry)
        return True

    def git(self, *args):
        subprocess.run(["git", "-C", self.git_dir, *args], check=True, timeout=1800)

    def copy_open_pr(self, item):
        key = source_key(item, "pr")
        entry = self.state["entries"].get(key)
        if entry is None:
            if self.max_new and self.count >= self.max_new:
                return False
            n = item["number"]
            pr = self.api.request("GET", f"/repos/{SOURCE}/pulls/{n}")
            base = pr["base"]["ref"]
            name = f"upstream-mirror/pr-{n}"
            self.git("fetch", "--no-tags", f"https://github.com/{SOURCE}.git", f"refs/pull/{n}/head")
            self.git("push", "origin", f"FETCH_HEAD:refs/heads/{name}")
            body, _ = split_body(source_description(item, "pr", f"Original target branch: {base}"))
            result = self.api.request("POST", f"/repos/{TARGET}/pulls", {
                "title": item["title"][:256], "body": body,
                "head": name, "base": base, "draft": True,
            })
            entry = {"number": result["number"], "url": result["html_url"], "done": True}
            self.state["entries"][key] = entry
            self.save()
            self.count += 1
        self.import_comments(item["number"], entry["number"], entry)
        return True

    def run(self):
        target = self.api.request("GET", f"/repos/{TARGET}")
        needs_issues = self.mode != "open-prs"
        if needs_issues and not target.get("has_issues"):
            raise RuntimeError(
                f"{TARGET}: Issues are disabled. Enable Settings -> General -> Features -> Issues "
                "before importing issues or closed PR archives."
            )

        if self.mode in ("all", "open-prs"):
            existing = existing_upstream_pr_numbers(
                self.api.pages(f"/repos/{TARGET}/pulls?state=all&per_page=100")
            )
            for n, entry in existing.items():
                self.state["entries"].setdefault(f"pr:{n}", entry)
            self.save()

        upstream = f"/repos/{SOURCE}/issues?state=all&sort=created&direction=asc&per_page=100"
        for item in self.api.pages(upstream):
            is_pr = bool(item.get("pull_request"))
            if self.mode == "issues" and is_pr:
                continue
            if self.mode == "open-prs" and (not is_pr or item.get("state") != "open"):
                continue
            if self.mode == "archive-prs" and (not is_pr or item.get("state") == "open"):
                continue
            kind = "pr" if is_pr and item.get("state") == "open" else (
                "archive-pr" if is_pr else "issue"
            )
            key = source_key(item, kind)
            if self.max_new and self.count >= self.max_new and key not in self.state["entries"]:
                break
            try:
                if kind == "pr":
                    self.copy_open_pr(item)
                else:
                    self.copy_issue(item, kind=kind)
                self.state["errors"].pop(key, None)
            except (ApiError, subprocess.CalledProcessError, subprocess.TimeoutExpired) as exc:
                self.state["errors"][key] = str(exc)
                self.save()
                print(f"FAILED {key}: {exc}", file=sys.stderr)
        print(f"Created: {self.count}. Total checkpoint entries: {len(self.state['entries'])}. "
              f"Recorded failures: {len(self.state['errors'])}.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--mode", choices=["all", "issues", "open-prs", "archive-prs"], default="all")
    parser.add_argument("--max-new", type=int, default=25, help="0 means no per-run limit")
    parser.add_argument("--state", default=".github/upstream-mirror-state.json")
    parser.add_argument("--git-dir", default=".")
    parser.add_argument("--allow-untrusted-pr-import", action="store_true",
                        help="Explicitly allow pushing unreviewed upstream PR branches into the fork")
    parser.add_argument("--skip-comments", action="store_true")
    parser.add_argument("--pause", type=float, default=1.0, help="Delay between writes")
    args = parser.parse_args()
    if args.max_new < 0:
        parser.error("--max-new must be >= 0")
    if args.mode in ("all", "open-prs") and not args.allow_untrusted_pr_import:
        parser.error(
            "Importing open PRs can trigger CI on untrusted branches. "
            "Review your fork's Actions permissions and secrets first, then pass "
            "--allow-untrusted-pr-import to acknowledge this risk."
        )
    token = os.environ.get("GH_TOKEN") or os.environ.get("GITHUB_TOKEN")
    if not token:
        parser.error("GH_TOKEN or GITHUB_TOKEN with write permissions is required")
    Mirror(Api(token, pause=args.pause), args.state, args.mode,
           max_new=args.max_new, comments=not args.skip_comments,
           git_dir=args.git_dir).run()


if __name__ == "__main__":
    main()
