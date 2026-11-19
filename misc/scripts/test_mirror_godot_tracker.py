import io
import json
import sqlite3
import tempfile
import unittest
from contextlib import redirect_stderr
from pathlib import Path
from unittest.mock import patch

import mirror_godot_tracker as m


def issue(n, *, kind="issue", state="open", body="Description", author="alice"):
    return {"number": n, "title": f"Item {n}", "body": body,
            "html_url": f"https://github.com/godotengine/godot/{'pull' if kind == 'pr' else 'issues'}/{n}",
            "state": state, "created_at": "2026-11-01T00:00:00Z", "updated_at": "2026-11-18T00:00:00Z",
            "user": {"login": author}, "labels": [{"name": "bug"}],
            **({"pull_request": {"url": f"https://api.github.com/repos/godotengine/godot/pulls/{n}"}} if kind == "pr" else {})}


class FakeAPI:
    def __init__(self, source=None, existing=None, *, issues_enabled=True):
        self.source = source or []
        self.existing = existing or []
        self.issues_enabled = issues_enabled
        self.writes = []
        self.next_num = 50

    def list_pages(self, endpoint, *, params=None):
        from urllib.parse import urlencode
        page = 1
        while True:
            records = self.request("GET", endpoint + "?" + urlencode({**(params or {}), "page": page, "per_page": 100}))
            yield from records
            if len(records) < 100:
                return
            page += 1

    def request(self, method, path, payload=None):
        if path == "/repos/demoh2019/godot" and method == "GET":
            return {"has_issues": self.issues_enabled}
        if method == "GET" and path.startswith("/repos/godotengine/godot/issues?"):
            from urllib.parse import parse_qs
            params = parse_qs(path.split("?", 1)[1])
            page = int(params["page"][0]); per_page = int(params["per_page"][0])
            return self.source[(page - 1) * per_page:page * per_page]
        if method == "GET" and path.startswith("/repos/demoh2019/godot/issues?"):
            from urllib.parse import parse_qs
            params = parse_qs(path.split("?", 1)[1])
            page = int(params["page"][0]); per_page = int(params["per_page"][0])
            return self.existing[(page - 1) * per_page:page * per_page]
        if method == "POST" and path == "/repos/demoh2019/godot/issues":
            if not self.issues_enabled:
                raise m.ApiError(410, "Issues disabled")
            self.writes.append((method, path, payload))
            self.next_num += 1
            item = {"number": self.next_num, "title": payload["title"], "body": payload["body"],
                    "html_url": f"https://github.com/demoh2019/godot/issues/{self.next_num}", "state": "open"}
            self.existing.append(item)
            return item
        if method == "PATCH" and path.startswith("/repos/demoh2019/godot/issues/"):
            self.writes.append((method, path, payload))
            number = int(path.rsplit("/", 1)[1])
            for target in self.existing:
                if target["number"] == number:
                    target["state"] = payload["state"]
            return {"state": payload["state"]}
        raise AssertionError((method, path, payload))


class MirrorTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.db = m.connect(Path(self.tmp.name) / "state.sqlite3")

    def tearDown(self):
        self.db.close()
        self.tmp.cleanup()

    def test_scan_distinguishes_prs_and_issues(self):
        api = FakeAPI([issue(1), issue(2, kind="pr", state="closed"), issue(3)])
        result = m.scan(api, self.db)
        self.assertEqual((result["issues"], result["prs"]), (2, 1))
        self.assertEqual(result["records_seen"], 3)
        self.assertEqual(result["next_page"], 1)
        self.assertEqual(m.scan(api, self.db)["records_seen"], 3)
        self.assertEqual(self.db.execute("SELECT COUNT(*) FROM source_records").fetchone()[0], 3)

    def test_scan_pagination_and_restart_with_new_partial_page(self):
        api = FakeAPI([issue(n) for n in range(1, 102)])
        first = m.scan(api, self.db, max_pages=1)
        self.assertEqual((first["next_page"], first["records_seen"]), (2, 100))
        second = m.scan(api, self.db)
        self.assertEqual((second["next_page"], second["records_seen"]), (2, 1))
        api.source.extend([issue(102), issue(103)])
        self.assertEqual(m.scan(api, self.db)["issues"], 103)
        self.assertEqual(self.db.execute("SELECT COUNT(*) FROM source_records").fetchone()[0], 103)

    def test_dry_run_never_writes(self):
        api = FakeAPI([issue(1)])
        m.scan(api, self.db)
        out = m.synchronize(api, self.db, apply=False)
        self.assertEqual(out["candidates"], 1)
        self.assertTrue(out["dry_run"])
        self.assertEqual(api.writes, [])

    def test_issue_enabled_gate_prevents_partial_migration(self):
        api = FakeAPI([issue(1)], issues_enabled=False)
        m.scan(api, self.db)
        with self.assertRaisesRegex(m.MirrorError, "Issues are disabled"):
            m.synchronize(api, self.db, apply=True)
        self.assertEqual(api.writes, [])

    def test_import_issue_preserves_attribution_and_state(self):
        api = FakeAPI([issue(8, state="closed", author="some-user")])
        m.scan(api, self.db)
        out = m.synchronize(api, self.db, apply=True)
        self.assertEqual(out["created_issues"], 1)
        self.assertEqual(len(api.writes), 2)
        self.assertIn("Author: @some-user", api.writes[0][2]["body"])
        self.assertIn("godot-upstream-mirror kind=issue number=8", api.writes[0][2]["body"])
        self.assertIn("Labels: bug", api.writes[0][2]["body"])
        self.assertEqual(api.writes[1][2], {"state": "closed"})
        self.assertEqual(m.synchronize(api, self.db, apply=True)["created_issues"], 0)

    def test_pr_archive_is_not_pretended_to_be_real_pr(self):
        api = FakeAPI([issue(4, kind="pr", state="closed")])
        m.scan(api, self.db)
        out = m.synchronize(api, self.db, kind="prs", apply=True)
        self.assertEqual(out["created_prs"], 0)
        self.assertEqual(out["created_issues"], 1)
        self.assertIn("[Upstream PR] #4:", api.writes[0][2]["title"])
        self.assertIn("cannot be re-created", api.writes[0][2]["body"])
        self.assertIn("godot-upstream-mirror kind=pr number=4", api.writes[0][2]["body"])

    def test_deduplication_from_existing_marker_survives_db_loss(self):
        original = issue(123)
        copied = {"number": 25, "title": "[Upstream Issue] #123", "state": "open",
                  "body": m.provenance_body(original, "issue"),
                  "html_url": "https://github.com/demoh2019/godot/issues/25"}
        api = FakeAPI([original], existing=[copied])
        m.scan(api, self.db)
        result = m.synchronize(api, self.db, apply=True)
        self.assertEqual(result["candidates"], 0)
        self.assertEqual(api.writes, [])
        self.assertEqual(self.db.execute("SELECT dest_number FROM mirrored WHERE number=123").fetchone()[0], 25)

    def test_existing_backport_pr_is_indexed(self):
        original = issue(125502, kind="pr")
        copied = {"number": 3, "title": "Backport #125502", "body": "Source: godotengine/godot#125502",
                  "html_url": "https://github.com/demoh2019/godot/pull/3", "pull_request": {"url": "..."}}
        api = FakeAPI([original], existing=[copied])
        m.scan(api, self.db)
        result = m.synchronize(api, self.db, kind="prs", apply=True)
        self.assertEqual(result["candidates"], 0)
        self.assertEqual(api.writes, [])

    def test_skip_closed_prs_gate_allows_open_only_with_disabled_issues(self):
        api = FakeAPI([issue(10, kind="pr", state="closed")], issues_enabled=False)
        m.scan(api, self.db)
        res = m.synchronize(api, self.db, kind="prs", skip_closed_prs=True, apply=True)
        self.assertEqual(res["candidates"], 0)
        self.assertEqual(api.writes, [])

    def test_metadata_truncation_is_bounded(self):
        original = issue(6, body="x" * 100000)
        body = m.provenance_body(original, "issue")
        self.assertLess(len(body), 65536)
        self.assertIn("truncated", body)

    def test_dedup_does_not_hallucinate_references(self):
        self.assertIsNone(m.dedup_key({"title": "Fix something", "body": "Related to #125502"}))
        self.assertIsNone(m.dedup_key({"title": "A PR", "body": "godotengine/godot#2 and godotengine/godot#3", "pull_request": {}}))

    def test_rate_limit_applies_between_writes(self):
        now = [1.0]; sleeps = []
        def do_sleep(s):
            sleeps.append(s)
            now[0] += s
        api = m.GitHub("TOKEN", min_write_seconds=9, sleep=do_sleep, clock=lambda: now[0])
        class Response:
            def __enter__(self): return self
            def __exit__(self, *args): pass
            def read(self): return b'{}'
        with patch("urllib.request.urlopen", return_value=Response()):
            api.request("POST", "/x", {})
            api.request("GET", "/x")
            api.request("POST", "/x", {})
        self.assertEqual(sleeps, [9.0])

    def test_no_retry_ambiguous_write_transport_failure(self):
        from urllib.error import URLError
        api = m.GitHub("TOKEN", sleep=lambda _: None)
        with patch("urllib.request.urlopen", side_effect=URLError("remote closed")) as opener:
            with self.assertRaisesRegex(m.MirrorError, "Ambiguous request failure"):
                api.request("POST", "/repos/foo/bar/issues", {"title": "One"})
            self.assertEqual(opener.call_count, 1)

    def test_batch_limit_and_kind_filter(self):
        api = FakeAPI([issue(1), issue(2), issue(3, kind="pr")])
        m.scan(api, self.db)
        result = m.synchronize(api, self.db, kind="issues", limit=1, apply=True)
        self.assertEqual(result["candidates"], 1)
        self.assertEqual(self.db.execute("SELECT COUNT(*) FROM mirrored").fetchone()[0], 1)
        self.assertEqual(m.synchronize(api, self.db, kind="issues", limit=1, apply=True)["created_issues"], 1)
        self.assertEqual(m.synchronize(api, self.db, kind="issues", limit=1, apply=True)["created_issues"], 0)

    def test_closure_patch_failure_is_recovered_without_duplicate(self):
        class FlakyAPI(FakeAPI):
            failures_left = 1
            def request(self, method, path, payload=None):
                if method == "PATCH" and self.failures_left:
                    self.failures_left -= 1
                    raise m.ApiError(503, "transient backend failure")
                return super().request(method, path, payload)
        api = FlakyAPI([issue(77, state="closed")])
        m.scan(api, self.db)
        with self.assertRaises(m.ApiError):
            m.synchronize(api, self.db, apply=True)
        self.assertEqual(len(api.existing), 1)
        self.assertEqual(self.db.execute("SELECT COUNT(*) FROM pending_closures").fetchone()[0], 1)
        self.assertEqual(self.db.execute("SELECT COUNT(*) FROM mirrored").fetchone()[0], 1)
        retry = m.synchronize(api, self.db, apply=True)
        self.assertEqual(retry["candidates"], 0)
        self.assertEqual(len(api.existing), 1)
        self.assertEqual(api.existing[0]["state"], "closed")
        self.assertEqual(self.db.execute("SELECT COUNT(*) FROM pending_closures").fetchone()[0], 0)

    def test_reconcile_mirrored_but_open_target(self):
        src = issue(79, state="closed")
        target = {"number": 87, "title": "existing", "html_url": "https://github.com/demoh2019/godot/issues/87",
                  "body": m.provenance_body(src, "issue"), "state": "open"}
        api = FakeAPI([src], existing=[target])
        m.scan(api, self.db)
        out = m.synchronize(api, self.db, apply=True)
        self.assertEqual(out["candidates"], 0)
        self.assertEqual(api.existing[0]["state"], "closed")
        self.assertEqual([op[0] for op in api.writes], ["PATCH"])

    def test_post_server_error_is_not_retried(self):
        from urllib.error import HTTPError
        from io import BytesIO
        error = HTTPError("https://api.github.com/repos/x", 500, "Server Error", {}, BytesIO(b'{"message":"failed"}'))
        api = m.GitHub("TOKEN", sleep=lambda _: None)
        with patch("urllib.request.urlopen", side_effect=error) as opener:
            with self.assertRaises(m.ApiError):
                api.request("POST", "/repos/foo/bar/issues", {"title": "One"})
            self.assertEqual(opener.call_count, 1)

    def test_existing_closed_issue_requires_no_extra_writes(self):
        src = issue(80, state="closed")
        target = {"number": 88, "title": "existing", "html_url": "https://github.com/demoh2019/godot/issues/88",
                  "body": m.provenance_body(src, "issue"), "state": "closed"}
        api = FakeAPI([src], existing=[target])
        m.scan(api, self.db)
        out = m.synchronize(api, self.db, apply=True)
        self.assertEqual(out["candidates"], 0)
        self.assertEqual(api.writes, [])

    def test_scan_reset_is_idempotent(self):
        api = FakeAPI([issue(1), issue(2)])
        m.scan(api, self.db)
        result = m.scan(api, self.db, reset=True)
        self.assertEqual(result["issues"], 2)
        self.assertEqual(result["records_seen"], 2)


if __name__ == "__main__":
    unittest.main()
