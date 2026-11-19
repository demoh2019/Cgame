# Source copy for export
"""Offline regression tests. Run: python -m unittest discover -s tests -v"""

import gzip
import io
import json
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest import mock
from urllib.error import HTTPError

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import upstream_mirror as m


def record(number=1, *, pr=False, state="open"):
    d = {
        "number": number, "title": f"Fixture #{number}", "body": "Repro steps\n```cpp\n42\n```",
        "state": state, "created_at": "2020-01-01T00:00:00Z", "closed_at": None,
        "labels": [{"name": "bug"}, {"name": "confirmed"}], "user": {"login": "test-author"},
        "comments": 2, "html_url": f"https://github.com/godotengine/godot/{'pull' if pr else 'issues'}/{number}"
    }
    if pr:
        d["pull_request"] = {"url": "https://api.github.com/example"}
    if state == "closed":
        d["closed_at"] = "2020-01-03T00:00:00Z"
    return d


class FakeGitHub:
    def __init__(self, *, pages=None, target_issues=None, issues_enabled=True):
        self.pages = pages or {}
        self.target_issues = target_issues or []
        self.issues_enabled = issues_enabled
        self.posts = []
        self.patches = []
        self.get_calls = []

    def get(self, url):
        self.get_calls.append(url)
        if url == "repos/demoh2019/godot":
            return {"has_issues": self.issues_enabled}
        if url.startswith("repos/godotengine/godot/issues?") or url.startswith("repos/godotengine/godot/pulls?"):
            import urllib.parse
            page = int(urllib.parse.parse_qs(urllib.parse.urlsplit(url).query)["page"][0])
            return self.pages.get(page, [])
        if url.startswith("repos/demoh2019/godot/issues?"):
            return self.target_issues
        if url.startswith("repos/demoh2019/godot/pulls?"):
            return []
        raise AssertionError("Unmocked GET " + url)

    def post(self, path, data):
        self.posts.append((path, data))
        return {"number": 800 + len(self.posts), "html_url": f"https://github.com/demoh2019/godot/pull/{800+len(self.posts)}"}

    def patch(self, path, data):
        self.patches.append((path, data))
        return {"ok": True}


class StateTests(unittest.TestCase):
    def test_default_state_contains_all_cursors(self):
        s = m.default_state()
        self.assertEqual(s["archive"]["next_page"], 1)
        self.assertEqual(s["issues"]["offset"], 0)
        self.assertEqual(s["prs"]["results"], {})

    def test_save_load_roundtrip_utf8_and_atomic_cleanup(self):
        with tempfile.TemporaryDirectory() as t:
            p = Path(t) / "sub" / "state.json"
            s = m.default_state()
            s["issues"]["copied"]["123"] = "Тест 🚀"
            m.save_state(p, s)
            self.assertEqual(m.load_state(p, m.SOURCE), s)
            self.assertFalse((p.parent / "state.json.tmp").exists())

    def test_wrong_source_protected(self):
        with tempfile.TemporaryDirectory() as t:
            p = Path(t) / "state.json"
            m.save_state(p, m.default_state())
            with self.assertRaisesRegex(ValueError, "different upstream"):
                m.load_state(p, "notgodot/test")

    def test_invalid_schema_rejected(self):
        with tempfile.TemporaryDirectory() as t:
            p = Path(t) / "state.json"
            p.write_text('{"version":999,"source":"godotengine/godot"}')
            with self.assertRaisesRegex(ValueError, "version"):
                m.load_state(p, m.SOURCE)

    def test_invalid_repo_slugs(self):
        for value in ("", "myrepo", "../../etc/passwd", "evil/repo/extra", "a/b?x", "a..b/c"):
            with self.subTest(value=value), self.assertRaises(ValueError):
                m.validate_repo(value)
        self.assertEqual(m.validate_repo("demoh2019/godot"), "demoh2019/godot")

    def test_pagination_is_stable_creation_order(self):
        self.assertIn("direction=asc", m.issue_page_path(m.SOURCE, 42))
        self.assertIn("state=all", m.issue_page_path(m.SOURCE, 42))
        self.assertIn("page=42", m.issue_page_path(m.SOURCE, 42))
        self.assertIn("state=open", m.pr_page_path(m.SOURCE, 3))


class ArchiveTests(unittest.TestCase):
    def test_archives_issues_and_prs_with_source_metadata(self):
        source = [record(1), record(2, pr=True, state="closed")]
        api = FakeGitHub(pages={1: source})
        with tempfile.TemporaryDirectory() as t:
            path = Path(t) / "state.json"
            root = Path(t) / "archive"
            state = m.default_state()
            result = m.archive_pages(api, m.SOURCE, state, root, path, 3, dry_run=False)
            self.assertEqual(result["records"], 2)
            self.assertTrue(result["complete"])
            stored = json.loads(gzip.decompress((root / "page-00001.json.gz").read_bytes()))
            self.assertEqual(stored, source)
            self.assertEqual(m.load_state(path, m.SOURCE)["archive"]["next_page"], 2)

    def test_dry_run_does_not_write_or_advance(self):
        api = FakeGitHub(pages={1: [record()]})
        with tempfile.TemporaryDirectory() as t:
            path = Path(t) / "state.json"
            state = m.default_state()
            m.archive_pages(api, m.SOURCE, state, Path(t) / "archive", path, 10, dry_run=True)
            self.assertFalse(path.exists())
            self.assertEqual(state["archive"]["next_page"], 1)

    def test_resume_does_not_revisit_completed_page(self):
        api = FakeGitHub(pages={5: [record(i) for i in range(1, 101)], 6: [record(101)]})
        with tempfile.TemporaryDirectory() as t:
            path = Path(t) / "state.json"
            state = m.default_state()
            state["archive"]["next_page"] = 5
            result = m.archive_pages(api, m.SOURCE, state, Path(t) / "archive", path, 2, dry_run=False)
            self.assertEqual(result["records"], 101)
            self.assertEqual(result["next_page"], 7)
            self.assertEqual(len(api.get_calls), 2)

    def test_completed_archive_never_fetches(self):
        api = FakeGitHub()
        with tempfile.TemporaryDirectory() as t:
            s = m.default_state()
            s["archive"]["complete"] = True
            result = m.archive_pages(api, m.SOURCE, s, Path(t), Path(t) / "state", 2, dry_run=False)
            self.assertEqual(result["records"], 0)
            self.assertFalse(api.get_calls)


class CopyTests(unittest.TestCase):
    def test_mirror_metadata_and_pr_distinction(self):
        title, body = m.as_issue(m.SOURCE, record(72))
        self.assertIn("[Upstream issue #72]", title)
        self.assertIn("@test-author", body)
        self.assertIn("<!-- upstream-mirror:godotengine/godot#72 -->", body)
        self.assertIn("Repro steps", body)
        title, body = m.as_issue(m.SOURCE, record(73, pr=True))
        self.assertIn("[Upstream PR #73]", title)
        self.assertIn("code NOT imported", body)

    def test_closed_issue_state_preserved(self):
        api = FakeGitHub(pages={1: [record(2, state="closed")]})
        with tempfile.TemporaryDirectory() as t:
            s = m.default_state()
            path = Path(t) / "state.json"
            out = m.mirror_issues(api, m.SOURCE, "demoh2019/godot", s, path, 1, pr_records=False, dry_run=False, delay=0)
            self.assertEqual(out["created"], 1)
            self.assertEqual(api.patches, [("repos/demoh2019/godot/issues/801", {"state": "closed"})])

    def test_issue_filter_skips_pr_but_moves_cursor(self):
        api = FakeGitHub(pages={1: [record(1, pr=True), record(2)]})
        with tempfile.TemporaryDirectory() as t:
            s = m.default_state()
            out = m.mirror_issues(api, m.SOURCE, "demoh2019/godot", s, Path(t)/"state", 2, pr_records=False, dry_run=False, delay=0)
            self.assertEqual(out["created"], 1)
            self.assertEqual(s["issues"]["offset"], 2)
            self.assertIn("2", s["issues"]["copied"])
            self.assertNotIn("1", s["issues"]["copied"])

    def test_pr_records_only_are_tracking_issues(self):
        api = FakeGitHub(pages={1: [record(1), record(2, pr=True)]})
        with tempfile.TemporaryDirectory() as t:
            s = m.default_state()
            m.mirror_issues(api, m.SOURCE, "demoh2019/godot", s, Path(t)/"state", 2, pr_records=True, dry_run=False, delay=0)
            self.assertEqual(len(api.posts), 1)
            self.assertIn("PR #2", api.posts[0][1]["title"])
            self.assertIn("code NOT imported", api.posts[0][1]["body"])

    def test_idempotence_uses_checkpoint(self):
        api = FakeGitHub(pages={1: [record(1), record(2)]})
        with tempfile.TemporaryDirectory() as t:
            s = m.default_state()
            s["issues"]["copied"]["1"] = 42
            m.mirror_issues(api, m.SOURCE, "demoh2019/godot", s, Path(t)/"state", 2, pr_records=False, dry_run=False, delay=0)
            self.assertEqual(len(api.posts), 1)
            self.assertEqual(s["issues"]["copied"]["1"], 42)

    def test_recover_recent_create_if_state_lost(self):
        recovered = dict(record(799), number=799, body=m.source_record_marker(m.SOURCE, 1), state="open")
        api = FakeGitHub(pages={1: [record(1)]}, target_issues=[recovered])
        with tempfile.TemporaryDirectory() as t:
            s = m.default_state()
            m.mirror_issues(api, m.SOURCE, "demoh2019/godot", s, Path(t)/"state", 1, pr_records=False, dry_run=False, delay=0)
            self.assertFalse(api.posts)
            self.assertEqual(s["issues"]["copied"]["1"], 799)

    def test_refuse_disabled_issues_even_dryrun(self):
        api = FakeGitHub(issues_enabled=False)
        with self.assertRaisesRegex(RuntimeError, "Issues are disabled"):
            m.mirror_issues(api, m.SOURCE, "demoh2019/godot", m.default_state(), Path("bad"), 1, pr_records=False, dry_run=True)

    def test_dryrun_neither_posts_nor_advances(self):
        api = FakeGitHub(pages={1: [record(1)]})
        with tempfile.TemporaryDirectory() as t:
            p = Path(t) / "state.json"
            s = m.default_state()
            m.mirror_issues(api, m.SOURCE, "demoh2019/godot", s, p, 1, pr_records=False, dry_run=True)
            self.assertFalse(api.posts)
            self.assertFalse(p.exists())
            self.assertEqual(s["issues"]["offset"], 0)

    def test_page_boundary_advances_cursor(self):
        api = FakeGitHub(pages={1: [record(1)], 2: [record(2)]})
        with tempfile.TemporaryDirectory() as t:
            s = m.default_state()
            result = m.mirror_issues(api, m.SOURCE, "demoh2019/godot", s, Path(t)/"state", 2, pr_records=False, dry_run=False, delay=0)
            self.assertEqual(result["created"], 2)
            self.assertEqual(s["issues"]["page"], 2)
            self.assertEqual(s["issues"]["offset"], 1)


class PortTests(unittest.TestCase):
    def setUp(self):
        self.pr = dict(record(125492, pr=True), base={"ref": "master", "sha": "abcdef123"}, draft=False)

    def test_wrong_target_branch_skipped(self):
        pr = dict(self.pr, base={"ref": "3.x", "sha": "abcd"})
        self.assertIn("skipped: base", m.port_pr(FakeGitHub(), m.SOURCE, "demoh2019/godot", pr, "master", dry_run=False))

    def test_upstream_drafts_skipped(self):
        self.assertIn("source PR is itself a draft", m.port_pr(FakeGitHub(), m.SOURCE, "demoh2019/godot", dict(self.pr, draft=True), "master", dry_run=False))

    def test_port_dryrun_does_not_call_api_or_git(self):
        api = FakeGitHub()
        with mock.patch.object(m, "run_git") as git:
            result = m.port_pr(api, m.SOURCE, "demoh2019/godot", self.pr, "master", dry_run=True)
        self.assertIn("would port", result)
        git.assert_not_called()
        self.assertFalse(api.get_calls)

    def test_detects_existing_target_pr(self):
        api = FakeGitHub()
        old_get = api.get
        def get(path):
            if "/pulls?" in path:
                return [{"html_url": "https://github.com/demoh2019/godot/pull/111"}]
            return old_get(path)
        api.get = get
        self.assertIn("already exists", m.port_pr(api, m.SOURCE, "demoh2019/godot", self.pr, "master", dry_run=False))

    def test_pr_batch_dry_run_keeps_cursor(self):
        api = FakeGitHub(pages={1: [self.pr]})
        with tempfile.TemporaryDirectory() as t:
            s = m.default_state()
            r = m.mirror_prs(api, m.SOURCE, "demoh2019/godot", s, Path(t)/"state", 1, base_branch="master", dry_run=True)
            self.assertEqual(r["processed"], 1)
            self.assertEqual(s["prs"]["results"], {})
            self.assertEqual(s["prs"]["offset"], 0)

    def test_pr_batch_records_failure_and_continues(self):
        api = FakeGitHub(pages={1: [self.pr, dict(self.pr, number=125493)]})
        with tempfile.TemporaryDirectory() as t:
            s = m.default_state()
            with mock.patch.object(m, "port_pr", side_effect=[m.GitHubError(422,"bad"), "created: example"]):
                r = m.mirror_prs(api, m.SOURCE, "demoh2019/godot", s, Path(t)/"state", 2, base_branch="master", dry_run=False)
            self.assertEqual(r["processed"], 2)
            self.assertIn("failed:", s["prs"]["results"]["125492"])
            self.assertEqual(s["prs"]["results"]["125493"], "created: example")


class MainTests(unittest.TestCase):
    def test_bad_limit_rejected(self):
        with self.assertRaises(SystemExit) as context:
            m.main(["archive", "--limit", "999"])
        self.assertEqual(context.exception.code, 2)

    def test_no_token_mutating_mode_rejected(self):
        with mock.patch.dict(os.environ, {"GITHUB_TOKEN": ""}):
            with self.assertRaises(SystemExit) as context:
                m.main(["issues"])
        self.assertEqual(context.exception.code, 2)


if __name__ == "__main__":
    unittest.main()