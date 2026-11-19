#!/usr/bin/env python3
"""Resumable, attribution-preserving mirror of OPEN Godot Issues and Pull Requests.

Standard library only. Does not impersonate source authors or replay PR comments.
Run `python mirror_godot_tracker.py --help` for subcommands.
"""
from __future__ import annotations

import argparse
import json
import os
import re
import sqlite3
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path
from typing import Any

SOURCE = "godotengine/godot"
TARGET = "demoh2019/godot"
API = "https://api.github.com"
MARKER_RE = re.compile(r"<!-- godot-upstream-mirror kind=(issue|pr) number=(\d+) -->")
SOURCE_PR_RE = re.compile(r"(?:github\.com/|\b)godotengine/godot(?:/pull/|#)(\d+)", re.I)
SOURCE_ISSUE_RE = re.compile(r"github\.com/godotengine/godot/issues/(\d+)", re.I)


class MirrorError(Exception):
    pass


class ApiError(MirrorError):
    def __init__(self, status: int, detail: str):
        super().__init__(f"HTTP {status}: {detail[:500]}")
        self.status = status


class GitHub:
    def __init__(self, token: str = "", *, min_write_seconds: float = 9.0,
                 sleep=time.sleep, clock=time.monotonic):
        self.token = token
        self.min_write_seconds = min_write_seconds
        self.sleep = sleep
        self.clock = clock
        self._last_write: float | None = None

    def request(self, method: str, path: str, payload: dict | None = None) -> Any:
        if method != "GET" and not self.token:
            raise MirrorError("Set GH_TOKEN or GITHUB_TOKEN before using --apply")
        if method != "GET":
            if self._last_write is not None:
                delay = self.min_write_seconds - (self.clock() - self._last_write)
                if delay > 0:
                    self.sleep(delay)
            # Also limit retries of failed writes.
            self._last_write = self.clock()
        url = path if path.startswith("https://") else API + path
        headers = {
            "Accept": "application/vnd.github+json",
            "X-GitHub-Api-Version": "2022-11-28",
            "User-Agent": "godot-upstream-mirror/1",
        }
        if self.token:
            headers["Authorization"] = "Bearer " + self.token
        data = json.dumps(payload).encode("utf-8") if payload is not None else None
        if data is not None:
            headers["Content-Type"] = "application/json"
        for attempt in range(7):
            req = urllib.request.Request(url, data=data, headers=headers, method=method)
            try:
                with urllib.request.urlopen(req, timeout=50) as res:
                    raw = res.read()
                return json.loads(raw) if raw else None
            except urllib.error.HTTPError as exc:
                detail = exc.read().decode("utf-8", "replace")
                # 5xx after POST/PATCH may mean GitHub applied the write before
                # returning an error. Never replay an ambiguous mutation.
                retryable = exc.code in (403, 429) or (method == "GET" and exc.code in (500, 502, 503, 504))
                if not retryable or attempt == 6:
                    raise ApiError(exc.code, detail) from exc
                # Only retry rejected writes when the server explicitly replied that it
                # did not apply them. Network/timeout failures are intentionally fatal.
                retry_after = exc.headers.get("Retry-After", "")
                remaining = exc.headers.get("X-RateLimit-Remaining", "")
                reset = exc.headers.get("X-RateLimit-Reset", "")
                if retry_after and retry_after.isdecimal():
                    wait = int(retry_after) + 1
                elif remaining == "0" and reset.isdecimal():
                    wait = max(1, int(reset) - int(time.time()) + 1)
                else:
                    wait = min(600, 60 * (2 ** attempt))
                self.sleep(wait)
                if method != "GET":
                    self._last_write = self.clock()
            except (urllib.error.URLError, TimeoutError) as exc:
                # Don't retry writes: a timeout can occur *after* a successful POST.
                if method != "GET" or attempt == 6:
                    raise MirrorError(f"Ambiguous request failure; rerun after reindex: {exc}") from exc
                self.sleep(min(60, 2 ** attempt))
        raise AssertionError("retry loop exhausted")

    def list_pages(self, endpoint: str, *, params: dict | None = None):
        page = 1
        while True:
            query = urllib.parse.urlencode({**(params or {}), "page": page, "per_page": 100})
            records = self.request("GET", endpoint + "?" + query)
            if not isinstance(records, list):
                raise MirrorError(f"Unexpected collection response from {endpoint}")
            yield from records
            if len(records) < 100:
                return
            page += 1


def connect(db_path: Path) -> sqlite3.Connection:
    db_path.parent.mkdir(parents=True, exist_ok=True)
    db = sqlite3.connect(db_path)
    db.execute("PRAGMA journal_mode=WAL")
    db.executescript("""
        CREATE TABLE IF NOT EXISTS source_records (
            kind TEXT NOT NULL CHECK(kind IN ('issue','pr')),
            number INTEGER NOT NULL,
            title TEXT NOT NULL,
            state TEXT NOT NULL,
            raw TEXT NOT NULL,
            PRIMARY KEY(kind, number)
        );
        CREATE TABLE IF NOT EXISTS mirrored (
            kind TEXT NOT NULL,
            number INTEGER NOT NULL,
            dest_kind TEXT NOT NULL,
            dest_number INTEGER NOT NULL,
            dest_url TEXT NOT NULL,
            PRIMARY KEY(kind, number)
        );
        CREATE TABLE IF NOT EXISTS meta (key TEXT PRIMARY KEY, value TEXT NOT NULL);
        CREATE TABLE IF NOT EXISTS pending_closures (
            kind TEXT NOT NULL, number INTEGER NOT NULL, dest_number INTEGER NOT NULL,
            PRIMARY KEY(kind, number)
        );
        CREATE TABLE IF NOT EXISTS failures (
            kind TEXT NOT NULL, number INTEGER NOT NULL, error TEXT NOT NULL,
            PRIMARY KEY(kind, number)
        );
    """)
    return db


def meta_get(db: sqlite3.Connection, key: str, default: str) -> str:
    row = db.execute("SELECT value FROM meta WHERE key=?", (key,)).fetchone()
    return row[0] if row else default


def meta_put(db: sqlite3.Connection, key: str, value: str) -> None:
    db.execute("INSERT INTO meta(key,value) VALUES(?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value", (key, value))


def scan(api: GitHub, db: sqlite3.Connection, *, max_pages: int = 0, reset: bool = False) -> dict:
    """Snapshot only OPEN source Issues/PRs, resumable by page.

    --reset replaces the source inventory, retaining already-mirrored mappings.
    """
    if reset or meta_get(db, "scan_mode", "") != "open-v1":
        db.execute("DELETE FROM source_records")
        meta_put(db, "scan_next_page", "1")
        meta_put(db, "scan_mode", "open-v1")
        db.commit()
    page = int(meta_get(db, "scan_next_page", "1"))
    pages = added = 0
    while not max_pages or pages < max_pages:
        q = urllib.parse.urlencode({"state": "open", "sort": "created", "direction": "asc", "per_page": 100, "page": page})
        records = api.request("GET", f"/repos/{SOURCE}/issues?{q}")
        if not isinstance(records, list):
            raise MirrorError("GitHub returned non-list issue page")
        for item in records:
            # Defensive check: even a mocked or unexpected API response must
            # never make a closed record eligible for import.
            if item.get("state") != "open":
                continue
            kind = "pr" if item.get("pull_request") else "issue"
            db.execute("""INSERT INTO source_records(kind,number,title,state,raw) VALUES(?,?,?,?,?)
                ON CONFLICT(kind,number) DO UPDATE SET
                title=excluded.title,state=excluded.state,raw=excluded.raw""",
                (kind, int(item["number"]), item["title"], item["state"], json.dumps(item, ensure_ascii=False)))
            added += 1
        # Transaction boundary includes both the data and its cursor.
        if len(records) == 100:
            page += 1
        # On a partial final page, leave cursor at that page for future rescan
        # of newly appended issues. Upserts make the re-read harmless.
        meta_put(db, "scan_next_page", str(page))
        db.commit()
        pages += 1
        if len(records) < 100:
            break
    return {"pages": pages, "records_seen": added, "next_page": page,
            "issues": db.execute("SELECT COUNT(*) FROM source_records WHERE kind='issue'").fetchone()[0],
            "prs": db.execute("SELECT COUNT(*) FROM source_records WHERE kind='pr'").fetchone()[0]}


def source_key(obj: dict) -> tuple[str, int]:
    return ("pr" if obj.get("pull_request") else "issue", int(obj["number"]))


def dedup_key(obj: dict) -> tuple[str, int] | None:
    content = (obj.get("body") or "") + "\n" + (obj.get("title") or "")
    marker = MARKER_RE.search(content)
    if marker:
        return marker.group(1), int(marker.group(2))
    if obj.get("pull_request"):
        matches = set(SOURCE_PR_RE.findall(content))
        if len(matches) == 1:
            return "pr", int(next(iter(matches)))
    return None


def load_existing(api: GitHub, db: sqlite3.Connection) -> int:
    """Reconcile real destination records before creating anything; handles interrupted POST."""
    found = 0
    for obj in api.list_pages(f"/repos/{TARGET}/issues", params={"state": "open", "sort": "created", "direction": "asc"}):
        key = dedup_key(obj)
        if key is None:
            continue
        dk = "pr" if obj.get("pull_request") else "issue"
        url = obj["html_url"]
        db.execute("""INSERT INTO mirrored(kind,number,dest_kind,dest_number,dest_url)
            VALUES(?,?,?,?,?) ON CONFLICT(kind,number) DO NOTHING""",
            (*key, dk, int(obj["number"]), url))
        found += 1
    db.commit()
    return found


def provenance_body(obj: dict, kind: str, *, note: str = "") -> str:
    number = int(obj["number"])
    original = obj.get("html_url") or f"https://github.com/{SOURCE}/{'pull' if kind == 'pr' else 'issues'}/{number}"
    labels = ", ".join(x.get("name", "") for x in obj.get("labels", [])) or "(none)"
    author = (obj.get("user") or {}).get("login") or "unknown"
    marker = f"<!-- godot-upstream-mirror kind={kind} number={number} -->"
    metadata = (f"{marker}\n\n> **Imported reference; not authored by the importer.**\n"
                f"> Original: {original}\n> Author: @{author}\n"
                f"> Original state: `{obj.get('state', 'unknown')}`\n"
                f"> Created: {obj.get('created_at', '')}\n"
                f"> Updated: {obj.get('updated_at', '')}\n"
                f"> Labels: {labels}\n")
    if note:
        metadata += f"> Migration note: {note}\n"
    body = (obj.get("body") or "(no original description)").strip()
    # GitHub issue body limit, with room for the metadata and a source permalink.
    budget = max(0, 60000 - len(metadata))
    if len(body) > budget:
        body = body[:budget] + "\n\n[Original description truncated; see source link above.]"
    return metadata + "\n---\n\n" + body


def save_mirrored(db: sqlite3.Connection, kind: str, number: int, result: dict, dest_kind: str):
    db.execute("""INSERT INTO mirrored(kind,number,dest_kind,dest_number,dest_url)
        VALUES(?,?,?,?,?) ON CONFLICT(kind,number) DO UPDATE SET
        dest_kind=excluded.dest_kind,dest_number=excluded.dest_number,dest_url=excluded.dest_url""",
        (kind, number, dest_kind, int(result["number"]), result["html_url"]))
    db.execute("DELETE FROM failures WHERE kind=? AND number=?", (kind, number))
    db.commit()


def create_archive_issue(api: GitHub, obj: dict, kind: str, *, note: str = "") -> dict:
    label = "[Upstream PR]" if kind == "pr" else "[Upstream Issue]"
    data = api.request("POST", f"/repos/{TARGET}/issues", {
        "title": f"{label} #{obj['number']}: {obj['title']}"[:255],
        "body": provenance_body(obj, kind, note=note),
    })
    # Closing happens *after* the successful POST is recorded in SQLite.
    # If a later PATCH fails, the next invocation can safely repair it.
    return data


def git(*args: str, cwd: Path, input_bytes: bytes | None = None) -> bytes:
    proc = subprocess.run(["git", *args], cwd=cwd, input=input_bytes, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if proc.returncode:
        raise MirrorError(f"git {' '.join(args[:5])}: {proc.stderr.decode('utf-8', 'replace')[:500]}")
    return proc.stdout


def create_code_pr(api: GitHub, obj: dict, git_root: Path) -> dict:
    """Replay one upstream open PR's diff onto a fork branch, without executing PR code."""
    number = int(obj["number"])
    details = api.request("GET", f"/repos/{SOURCE}/pulls/{number}")
    base = details["base"]["ref"]
    branch = f"mirror/upstream-pr-{number}"
    try:
        api.request("GET", f"/repos/{TARGET}/branches/{urllib.parse.quote(base, safe='')}")
    except ApiError as exc:
        if exc.status == 404:
            raise MirrorError(f"fork does not contain PR target branch '{base}'") from exc
        raise
    remote = git("remote", "get-url", "origin", cwd=git_root).decode()
    if TARGET not in remote:
        raise MirrorError(f"git origin must point to {TARGET}, not {remote}")
    # When a previous run pushed the branch but failed creating the PR,
    # reuse the branch instead of constructing a second copy.
    branch_exists = False
    try:
        api.request("GET", f"/repos/{TARGET}/branches/{urllib.parse.quote(branch, safe='')}")
        branch_exists = True
    except ApiError as exc:
        if exc.status != 404:
            raise
    if not branch_exists:
        upstream_url = f"https://github.com/{SOURCE}.git"
        source_ref = f"refs/remotes/godot-mirror/pr-{number}"
        base_ref = f"refs/remotes/godot-mirror/base-{number}"
        git("fetch", "--no-tags", upstream_url, f"refs/pull/{number}/head:{source_ref}", cwd=git_root)
        git("fetch", "--no-tags", upstream_url, f"refs/heads/{base}:{base_ref}", cwd=git_root)
        git("fetch", "--no-tags", "origin", f"refs/heads/{base}:refs/remotes/origin/{base}", cwd=git_root)
        merge_base = git("merge-base", base_ref, source_ref, cwd=git_root).decode()
        patch = git("diff", "--binary", merge_base, source_ref, cwd=git_root)
        if not patch:
            raise MirrorError("upstream PR has no diff against its base")
        with tempfile.TemporaryDirectory(prefix="godot-pr-mirror-") as tmp:
            worktree = Path(tmp) / "working"
            made_branch = False
            pushed = False
            try:
                git("worktree", "add", "-b", branch, str(worktree), f"refs/remotes/origin/{base}", cwd=git_root)
                made_branch = True
                git("apply", "--3way", "--index", "-", cwd=worktree, input_bytes=patch)
                git("-c", "user.name=Upstream Mirror", "-c", "user.email=upstream-mirror@users.noreply.github.com",
                    "commit", "-m", f"Mirror upstream Godot PR #{number}", cwd=worktree)
                git("push", "origin", f"HEAD:refs/heads/{branch}", cwd=worktree)
                pushed = True
            finally:
                if made_branch:
                    git("worktree", "remove", "--force", str(worktree), cwd=git_root)
                if made_branch and not pushed:
                    git("branch", "-D", branch, cwd=git_root)
    return api.request("POST", f"/repos/{TARGET}/pulls", {
        "title": f"[Upstream #{number}] {obj['title']}"[:255],
        "head": branch,
        "base": base,
        "body": provenance_body(obj, "pr", note="Code ported as an unreviewed draft; verify tests and conflicts."),
        "draft": True,
    })


def synchronize(api: GitHub, db: sqlite3.Connection, *, kind: str = "all", limit: int = 50,
                apply: bool = False, replay_open_prs: bool = False, git_root: Path | None = None) -> dict:
    """Only import records that are still OPEN on upstream at time of creation.

    Open Pull Requests always require a real code replay into a draft PR;
    never turn a PR into a misleading plain Issue.
    """
    if apply:
        info = api.request("GET", f"/repos/{TARGET}")
        if not info.get("has_issues") and kind in ("all", "issues"):
            raise MirrorError(f"Issues are disabled in {TARGET}; enable them in Settings > General > Features > Issues")
        load_existing(api, db)

    filters = ["m.number IS NULL", "s.state='open'"]
    if kind == "issues":
        filters.append("s.kind='issue'")
    elif kind == "prs":
        filters.append("s.kind='pr'")
    else:
        # Import Issues before PRs when both are requested, for simple
        # incremental progress while the PR checkout is being prepared.
        pass
    q = ("SELECT s.kind,s.number,s.raw FROM source_records s "
         "LEFT JOIN mirrored m ON m.kind=s.kind AND m.number=s.number "
         f"WHERE {' AND '.join(filters)} ORDER BY s.number ASC")
    items = db.execute(q + (" LIMIT ?" if limit else ""), (limit,) if limit else ()).fetchall()
    outcome = {"candidates": len(items), "created_issues": 0, "created_prs": 0,
               "skipped_now_closed": 0, "failures": 0, "dry_run": not apply}
    if not apply:
        outcome["sample"] = [f"{k} #{n}" for k, n, _ in items[:20]]
        return outcome

    if any(k == "pr" for k, _, _ in items) and not replay_open_prs:
        raise MirrorError("Open Pull Requests require --replay-open-prs and --git-root; "
                          "they are never converted into plain Issues")
    if any(k == "pr" for k, _, _ in items) and git_root is None:
        raise MirrorError("--git-root is required for real open Pull Requests")

    for src_kind, number, raw in items:
        obj = json.loads(raw)
        try:
            # Source may have closed after scan; re-check immediately before
            # any write, and persist that transition in the local inventory.
            current = api.request("GET", f"/repos/{SOURCE}/issues/{number}")
            if current.get("state") != "open":
                db.execute("UPDATE source_records SET state='closed' WHERE kind=? AND number=?",
                           (src_kind, number))
                db.execute("DELETE FROM failures WHERE kind=? AND number=?", (src_kind, number))
                db.commit()
                outcome["skipped_now_closed"] += 1
                continue
            if (current.get("pull_request") is not None) != (src_kind == "pr"):
                raise MirrorError(f"Upstream item #{number} changed kind unexpectedly")
            obj = current
            if src_kind == "pr":
                result = create_code_pr(api, obj, git_root)
                dest_kind = "pr"
            else:
                result = create_archive_issue(api, obj, "issue")
                dest_kind = "issue"
            save_mirrored(db, src_kind, number, result, dest_kind)
            outcome["created_prs" if dest_kind == "pr" else "created_issues"] += 1
        except (MirrorError, ApiError) as exc:
            db.execute("INSERT INTO failures(kind,number,error) VALUES(?,?,?) "
                       "ON CONFLICT(kind,number) DO UPDATE SET error=excluded.error",
                       (src_kind, number, str(exc)))
            db.commit()
            outcome["failures"] += 1
            print(f"FAILED {src_kind} #{number}: {exc}", file=sys.stderr)
            # Abort on permission/rate-limit/transport failures to prevent flooding.
            if isinstance(exc, ApiError) or "Ambiguous request" in str(exc):
                raise
    return outcome


def main(argv: list[str] | None = None):
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--db", type=Path, default=Path.home() / ".cache/godot-upstream-mirror/tracker.sqlite3")
    p.add_argument("--min-write-seconds", type=float, default=9.0,
                   help="Minimum spacing of writes; GitHub rate-limits content generation")
    cmd = p.add_subparsers(dest="command", required=True)
    a = cmd.add_parser("scan", help="Inventory ONLY open upstream Issues and PRs")
    a.add_argument("--max-pages", type=int, default=0, help="0 = scan until end of history")
    a.add_argument("--reset", action="store_true", help="discard cached inventory and rescan currently open items; keep mirrored mappings")
    b = cmd.add_parser("sync", help="Import open Issues and optionally replay open PRs as draft code PRs")
    b.add_argument("--kind", choices=("all", "issues", "prs"), default="all")
    b.add_argument("--limit", type=int, default=50, help="Items per run; 0 = all (may take many days)")
    b.add_argument("--apply", action="store_true", help="Actually create GitHub issues/PRs; default dry-run")
    b.add_argument("--replay-open-prs", action="store_true", help="Use git patch replay and create draft PRs for open PRs")
    b.add_argument("--git-root", type=Path, help="Checked-out fork for patch replay")
    c = cmd.add_parser("status", help="Show inventory and migration totals")
    args = p.parse_args(argv)
    if args.min_write_seconds < 1:
        p.error("--min-write-seconds must be >= 1 to avoid GitHub secondary limits")
    api = GitHub(os.environ.get("GH_TOKEN") or os.environ.get("GITHUB_TOKEN") or "",
                 min_write_seconds=args.min_write_seconds)
    with connect(args.db) as db:
        if args.command == "scan":
            result = scan(api, db, max_pages=args.max_pages, reset=args.reset)
        elif args.command == "sync":
            if args.replay_open_prs and not args.git_root:
                p.error("--replay-open-prs requires --git-root")
            result = synchronize(api, db, kind=args.kind, limit=args.limit, apply=args.apply,
                                 replay_open_prs=args.replay_open_prs, git_root=args.git_root)
        else:
            result = {"inventory": dict(db.execute("SELECT kind,COUNT(*) FROM source_records WHERE state='open' GROUP BY kind")),
                      "mirrored": [dict(kind=k, dest_kind=d, count=n) for k,d,n in db.execute(
                          "SELECT kind,dest_kind,COUNT(*) FROM mirrored GROUP BY kind,dest_kind")],
                      "failures": [dict(kind=k, number=n, error=e) for k,n,e in db.execute(
                          "SELECT kind,number,error FROM failures LIMIT 30")],
                      "scan_next_page": meta_get(db, "scan_next_page", "1")}
    print(json.dumps(result, indent=2, ensure_ascii=False))


if __name__ == "__main__":
    try:
        main()
    except MirrorError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        raise SystemExit(1)
