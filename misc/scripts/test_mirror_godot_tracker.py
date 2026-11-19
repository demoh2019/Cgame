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
        self.live_states = {}

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
            state = params.get("state", ["all"])[0]
            matching = [obj for obj in self.source if state == "all" or obj["state"] == state]
            return matching[(page - 1) * per_page:page * per_page]
        if method == "GET" and path.startswith("/repos/godotengine/godot/issues/"):
            number = int(path.rsplit("/", 1)[1])
            original = next(obj for obj in self.source if obj["number"] == number)
            return {**original, "state": self.live_states.get(number, original["state"])}
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

    def test_scan_distinguishes_only_open_prs_and_issues(self):
        api = FakeAPI([issue(1), issue(2, kind="pr"), issue(3),
                       issue(4, kind="pr", state="closed"), issue(5, state="closed")])
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

    def test_import_open_issue_preserves_attribution_without_closing(self):
        api = FakeAPI([issue(8, state="open", author="some-user")])
        m.scan(api, self.db)
        out = m.synchronize(api, self.db, apply=True)
        self.assertEqual(out["created_issues"], 1)
        self.assertEqual(len(api.writes), 1)
        self.assertIn("Author: @some-user", api.writes[0][2]["body"])
        self.assertIn("godot-upstream-mirror kind=issue number=8", api.writes[0][2]["body"])
        self.assertIn("Labels: bug", api.writes[0][2]["body"])
        self.assertEqual(api.existing[0]["state"], "open")
        self.assertEqual(m.synchronize(api, self.db, apply=True)["created_issues"], 0)

    def test_closed_prs_are_not_archived_as_issues(self):
        api = FakeAPI([issue(4, kind="pr", state="closed")])
        m.scan(api, self.db)
        out = m.synchronize(api, self.db, kind="prs", apply=True)
        self.assertEqual(out["candidates"], 0)
        self.assertEqual(out["created_prs"], 0)
        self.assertEqual(out["created_issues"], 0)
        self.assertEqual(api.writes, [])

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

    def test_closed_prs_are_ignored_even_when_issues_feature_disabled(self):
        api = FakeAPI([issue(10, kind="pr", state="closed")], issues_enabled=False)
        m.scan(api, self.db)
        res = m.synchronize(api, self.db, kind="prs", apply=True)
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

    def test_issue_closed_after_scan_is_skipped_before_writes(self):
        api = FakeAPI([issue(77)])
        m.scan(api, self.db)
        api.live_states[77] = "closed"
        out = m.synchronize(api, self.db, apply=True)
        self.assertEqual(out["skipped_now_closed"], 1)
        self.assertEqual(out["created_issues"], 0)
        self.assertEqual(api.writes, [])
        self.assertEqual(self.db.execute("SELECT state FROM source_records WHERE number=77").fetchone()[0], "closed")
        self.assertEqual(m.synchronize(api, self.db, apply=False)["candidates"], 0)

    def test_legacy_pending_closures_are_not_executed(self):
        api = FakeAPI([issue(79)])
        m.scan(api, self.db)
        self.db.execute("INSERT INTO pending_closures(kind,number,dest_number) VALUES('issue',79,600)")
        self.db.commit()
        out = m.synchronize(api, self.db, apply=True)
        self.assertEqual(out["created_issues"], 1)
        self.assertTrue(all(method != "PATCH" for method, _, _ in api.writes))

    def test_stale_legacy_closed_inventory_is_not_imported(self):
        api = FakeAPI([issue(91)])
        m.scan(api, self.db)
        self.db.execute("INSERT INTO source_records(kind,number,title,state,raw) VALUES(?,?,?,?,?)",
                        ("pr", 92, "old closed PR", "closed", json.dumps(issue(92, kind="pr", state="closed"))))
        self.db.commit()
        self.assertEqual(m.synchronize(api, self.db, apply=False)["candidates"], 1)

    def test_real_open_pr_requires_explicit_replay(self):
        api = FakeAPI([issue(100, kind="pr")], issues_enabled=False)
        m.scan(api, self.db)
        with self.assertRaisesRegex(m.MirrorError, "--replay-open-prs"):
            m.synchronize(api, self.db, kind="prs", apply=True)
        self.assertEqual(api.writes, [])

    def test_open_pr_creates_actual_draft_not_issue(self):
        src = issue(101, kind="pr")
        api = FakeAPI([src], issues_enabled=False)
        m.scan(api, self.db)
        created = {"number": 230, "html_url": "https://github.com/demoh2019/godot/pull/230"}
        with patch.object(m, "create_code_pr", return_value=created) as fn:
            out = m.synchronize(api, self.db, kind="prs", apply=True,
                                replay_open_prs=True, git_root=Path("/source"))
        self.assertEqual(out["created_prs"], 1)
        self.assertEqual(out["created_issues"], 0)
        self.assertEqual(self.db.execute("SELECT dest_kind FROM mirrored WHERE number=101").fetchone()[0], "pr")
        self.assertEqual(api.writes, [])
        fn.assert_called_once()

    def test_open_pr_closed_after_scan_is_not_replayed(self):
        api = FakeAPI([issue(102, kind="pr")], issues_enabled=False)
        m.scan(api, self.db)
        api.live_states[102] = "closed"
        with patch.object(m, "create_code_pr") as fn:
            out = m.synchronize(api, self.db, kind="prs", apply=True,
                                replay_open_prs=True, git_root=Path("/source"))
        self.assertEqual(out["skipped_now_closed"], 1)
        self.assertEqual(out["created_prs"], 0)
        fn.assert_not_called()

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

    def test_open_scan_reset_prunes_closed_and_old_records(self):
        api = FakeAPI([issue(1), issue(2, kind="pr")])
        m.scan(api, self.db)
        api.source[0]["state"] = "closed"
        result = m.scan(api, self.db, reset=True)
        self.assertEqual((result["issues"], result["prs"]), (0, 1))
        self.assertEqual(m.meta_get(self.db, "scan_mode", ""), "open-v1")

    def test_migration_from_old_scan_mode_discards_closed_inventory(self):
        old = issue(200, state="closed")
        self.db.execute("INSERT INTO source_records(kind,number,title,state,raw) VALUES(?,?,?,?,?)",
                        ("issue", 200, old["title"], "closed", json.dumps(old)))
        self.db.execute("INSERT INTO meta(key,value) VALUES('scan_next_page','999')")
        self.db.commit()
        result = m.scan(FakeAPI([issue(1)]), self.db)
        self.assertEqual(result["issues"], 1)
        self.assertEqual(result["next_page"], 1)
        self.assertEqual(self.db.execute("SELECT number FROM source_records").fetchone()[0], 1)


    def test_failed_first_item_does_not_starve_subsequent_batches(self):
        class FailOne(FakeAPI):
            def request(self, method, path, payload=None):
                if method == "POST" and path.endswith("/issues") and payload["title"].startswith("[Upstream Issue] #1:"):
                    raise m.MirrorError("synthetic invalid issue body")
                return super().request(method, path, payload)

        api = FailOne([issue(1), issue(2), issue(3)])
        m.scan(api, self.db)
        with redirect_stderr(io.StringIO()):
            first = m.synchronize(api, self.db, kind="issues", limit=1, apply=True)
        self.assertEqual((first["failures"], first["created_issues"]), (1, 0))
        second = m.synchronize(api, self.db, kind="issues", limit=1, apply=True)
        self.assertEqual((second["created_issues"], second["failures"]), (1, 0))
        self.assertIn("number=2", api.writes[0][2]["body"])
        self.assertEqual(self.db.execute("SELECT COUNT(*) FROM failures").fetchone()[0], 1)
        third = m.synchronize(api, self.db, kind="issues", limit=1, apply=False,
                              retry_failures=True)
        self.assertEqual(third["sample"], ["issue #1"])

    def test_retry_failures_retries_exactly_failed_item_and_clears_failure(self):
        api = FakeAPI([issue(1)])
        m.scan(api, self.db)
        self.db.execute("INSERT INTO failures(kind,number,error) VALUES('issue',1,'transient')")
        self.db.commit()
        self.assertEqual(m.synchronize(api, self.db, kind="issues", apply=True)["created_issues"], 0)
        out = m.synchronize(api, self.db, kind="issues", apply=True, retry_failures=True)
        self.assertEqual(out["created_issues"], 1)
        self.assertEqual(self.db.execute("SELECT COUNT(*) FROM failures").fetchone()[0], 0)

    def test_closed_destination_copy_prevents_duplicate_after_lost_db(self):
        source = issue(101)
        mirror = {"number": 701, "title": "[Upstream Issue] 101", "state": "closed",
                  "body": m.provenance_body(source, "issue"),
                  "html_url": "https://github.com/demoh2019/godot/issues/701"}
        api = FakeAPI([source], existing=[mirror])
        m.scan(api, self.db)
        out = m.synchronize(api, self.db, kind="issues", apply=True)
        self.assertEqual(out["candidates"], 0)
        self.assertEqual(api.writes, [])
        self.assertEqual(self.db.execute("SELECT dest_number FROM mirrored WHERE number=101").fetchone()[0], 701)

    def test_reset_preserves_completed_imports_and_failure_history(self):
        api = FakeAPI([issue(1), issue(2)])
        m.scan(api, self.db)
        m.synchronize(api, self.db, kind="issues", limit=1, apply=True)
        self.db.execute("INSERT INTO failures(kind,number,error) VALUES('issue',2,'cannot apply')")
        self.db.commit()
        m.scan(api, self.db, reset=True)
        self.assertEqual(self.db.execute("SELECT COUNT(*) FROM mirrored").fetchone()[0], 1)
        self.assertEqual(self.db.execute("SELECT COUNT(*) FROM failures").fetchone()[0], 1)
        self.assertEqual(m.synchronize(api, self.db, kind="issues", apply=False)["candidates"], 0)

    def test_negative_batch_limit_fails_before_any_writes(self):
        api = FakeAPI([issue(1)])
        m.scan(api, self.db)
        with self.assertRaisesRegex(m.MirrorError, "--limit"):
            m.synchronize(api, self.db, kind="issues", limit=-1, apply=True)
        self.assertEqual(api.writes, [])

    def test_cli_rejects_negative_scan_pages(self):
        with redirect_stderr(io.StringIO()):
            with self.assertRaises(SystemExit) as e:
                m.main(["--db", str(Path(self.tmp.name) / "other.sqlite3"), "scan", "--max-pages", "-1"])
        self.assertEqual(e.exception.code, 2)

    def test_cli_rejects_negative_sync_limit(self):
        with redirect_stderr(io.StringIO()):
            with self.assertRaises(SystemExit) as e:
                m.main(["--db", str(Path(self.tmp.name) / "other.sqlite3"), "sync", "--limit", "-9"])
        self.assertEqual(e.exception.code, 2)

    def test_scan_from_empty_repo_is_idempotent(self):
        api = FakeAPI([])
        for _ in range(2):
            stats = m.scan(api, self.db, reset=True)
            self.assertEqual((stats["issues"], stats["prs"], stats["records_seen"]), (0, 0, 0))
        self.assertEqual(m.synchronize(api, self.db, apply=False)["candidates"], 0)

    def test_pr_dry_run_includes_pr_without_code_write(self):
        api = FakeAPI([issue(10, kind="pr")])
        m.scan(api, self.db)
        result = m.synchronize(api, self.db, kind="prs", limit=1)
        self.assertEqual(result["sample"], ["pr #10"])
        self.assertEqual(result["created_issues"], 0)
        self.assertEqual(api.writes, [])

    def test_anonymous_read_and_write_requires_token(self):
        client = m.GitHub(token="")
        with self.assertRaisesRegex(m.MirrorError, "GH_TOKEN"):
            client.request("POST", "/repos/demoh2019/godot/issues", {"title": "x"})

    def test_closed_issue_does_not_overwrite_existing_mappings(self):
        api = FakeAPI([issue(40)])
        m.scan(api, self.db)
        m.synchronize(api, self.db, kind="issues", apply=True)
        dest = self.db.execute("SELECT dest_number FROM mirrored WHERE number=40").fetchone()[0]
        api.live_states[40] = "closed"
        m.scan(api, self.db, reset=True)
        self.assertEqual(m.synchronize(api, self.db, kind="issues", apply=True)["created_issues"], 0)
        self.assertEqual(self.db.execute("SELECT dest_number FROM mirrored WHERE number=40").fetchone()[0], dest)


if __name__ == "__main__":
    unittest.main()
