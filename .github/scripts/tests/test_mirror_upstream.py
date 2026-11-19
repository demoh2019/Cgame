"""Offline unit tests for mirror_upstream. No GitHub network or token required."""
import sys
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import mirror_upstream as m


def issue(number, *, closed=False, is_pr=False, body="A bug"):
    obj = {
        "number": number,
        "title": f"Test #{number}",
        "body": body,
        "state": "closed" if closed else "open",
        "created_at": "2026-11-01T00:00:00Z",
        "updated_at": "2026-11-03T00:00:00Z",
        "user": {"login": "alice"},
        "labels": [{"name": "bug"}],
    }
    if is_pr:
        obj["pull_request"] = {"html_url": f"https://github.com/godotengine/godot/pull/{number}"}
    return obj


class FakeAPI:
    def __init__(self, source=None, destination=None, comments=None, fail_pr=False,
                 issues_enabled=True):
        self.issues_enabled = issues_enabled
        self.source = source or []
        self.destination = destination or []
        self.comments = comments or []
        self.calls = []
        self.next_number = 1000
        self.fail_pr = fail_pr

    def pages(self, path):
        if path.startswith("/repos/demoh2019/godot/issues/") and path.endswith("/comments"):
            return iter(self.comments)
        if path == "/repos/demoh2019/godot/issues?state=all":
            return iter(self.destination)
        if path.startswith("/repos/godotengine/godot/issues/") and path.endswith("/comments"):
            return iter(self.comments)
        raise AssertionError(f"unexpected pagination path: {path}")

    def request(self, method, path, payload=None, with_links=False):
        self.calls.append((method, path, payload))
        if method == "GET" and path == "/repos/demoh2019/godot":
            return {"has_issues": self.issues_enabled}
        if method == "GET" and path == "/repos/godotengine/godot":
            return {"id": 15634981}
        if method == "GET" and (path.startswith("/repos/godotengine/godot/issues?") or
                                path.startswith("/repositories/15634981/issues?")):
            return (self.source, None) if with_links else self.source
        if method == "GET" and "/pulls/" in path:
            return {"state": "open", "body": "Proposed patch", "merged_at": None}
        if method == "POST" and path == "/repos/demoh2019/godot/pulls":
            if self.fail_pr:
                raise m.ApiError(422, "no commits")
            self.next_number += 1
            return {"number": self.next_number}
        if method == "POST" and path == "/repos/demoh2019/godot/issues":
            self.next_number += 1
            return {"number": self.next_number}
        if method in {"POST", "PATCH"}:
            return {}
        raise AssertionError(f"unexpected API call {method} {path}")


class FakeGit:
    base_branch = "master"

    def __init__(self, result=True):
        self.result = result
        self.numbers = []

    def push(self, number):
        self.numbers.append(number)
        return self.result


class MirrorTests(unittest.TestCase):
    def test_marker_is_stable_and_preserves_original_metadata(self):
        entry = issue(42, body="Details\n\n#41")
        body = m.format_body("godotengine/godot", entry, "issues")
        self.assertIn("<!-- upstream-mirror: godotengine/godot/issues/42 -->", body)
        self.assertIn("https://github.com/godotengine/godot/issues/42", body)
        self.assertIn("Original author: alice", body)
        self.assertIn("Original labels: [bug]", body)
        self.assertIn("Details\n\n#41", body)

    def test_disabled_issue_tracker_blocks_all_writes(self):
        api = FakeAPI([issue(1)], issues_enabled=False)
        with self.assertRaisesRegex(RuntimeError, "Issues are disabled"):
            m.Mirror(api, apply=True).run(max_items=1)
        self.assertFalse([x for x in api.calls if x[0] != "GET"])

    def test_existing_marker_and_previous_upstream_pr_links_are_deduped(self):
        entries = [
            {"body": m.marker("godotengine/godot", "issues", 41)},
            {"body": "Patch from https://github.com/godotengine/godot/pull/87",
             "pull_request": {}},
            {"body": m.marker("different/repo", "issues", 42)},
        ]
        keys = m.existing_keys(entries)
        self.assertIn(("issues", 41), keys)
        self.assertIn(("pull", 87), keys)
        self.assertNotIn(("issues", 42), keys)

    def test_dry_run_creates_no_issues_or_prs(self):
        api = FakeAPI([issue(1), issue(2, is_pr=True)])
        mirror = m.Mirror(api)
        result = mirror.run(max_items=2)
        self.assertEqual(result["dry_run"], 2)
        self.assertFalse([call for call in api.calls if call[0] != "GET"])

    def test_existing_issue_is_skipped_and_unrelated_issue_created(self):
        api = FakeAPI(
            [issue(1), issue(2)],
            destination=[{"number": 999, "state": "open", "body": m.marker(m.SOURCE_DEFAULT, "issues", 1)}],
        )
        mirror = m.Mirror(api, apply=True, git_mirror=FakeGit())
        stats = mirror.run(max_items=2)
        self.assertEqual(stats["skipped"], 1)
        self.assertEqual(stats["created_issues"], 1)
        self.assertEqual(len([c for c in api.calls if c[:2] == (
            "POST", "/repos/demoh2019/godot/issues")]), 1)

    def test_resume_partial_import_completes_comment_and_closure(self):
        comment = {"id": 16, "body": "Important detail", "user": {"login": "alice"},
                   "html_url": "https://github.com/godotengine/godot/issues/4#issuecomment-16",
                   "created_at": "2026-11-01T00:00:00Z"}
        api = FakeAPI(
            [issue(4, closed=True)],
            destination=[{"number": 999, "state": "open",
                          "body": m.marker(m.SOURCE_DEFAULT, "issues", 4)}],
            comments=[comment],
        )
        stats = m.Mirror(api, apply=True, comments=True).run(max_items=1)
        self.assertEqual(stats["skipped"], 1)
        self.assertEqual(stats["created_issues"], 0)
        self.assertIn(("PATCH", "/repos/demoh2019/godot/issues/999",
                       {"state": "closed"}), api.calls)
        comment_posts = [a for a in api.calls if a[0] == "POST"]
        self.assertEqual(len(comment_posts), 1)
        self.assertIn("upstream-comment: 16", comment_posts[0][2]["body"])

    def test_closed_issue_is_created_then_closed(self):
        api = FakeAPI([issue(5, closed=True)])
        stats = m.Mirror(api, apply=True, git_mirror=FakeGit()).run(max_items=1)
        self.assertEqual(stats["created_issues"], 1)
        self.assertIn(
            ("PATCH", "/repos/demoh2019/godot/issues/1001", {"state": "closed"}),
            api.calls,
        )

    def test_open_pr_creates_real_draft_pr_and_pushes_head(self):
        api = FakeAPI([issue(9, is_pr=True)])
        git = FakeGit()
        stats = m.Mirror(api, apply=True, git_mirror=git).run(max_items=1)
        self.assertEqual(stats["created_prs"], 1)
        self.assertEqual(git.numbers, [9])
        created = [c for c in api.calls if c[:2] == (
            "POST", "/repos/demoh2019/godot/pulls")]
        self.assertEqual(created[0][2]["head"], "upstream-mirror/pr-9")
        self.assertTrue(created[0][2]["draft"])
        self.assertIn("/pull/9", created[0][2]["body"])

    def test_open_pr_without_diff_is_archived_as_issue(self):
        api = FakeAPI([issue(11, is_pr=True)])
        git = FakeGit(result=False)
        stats = m.Mirror(api, apply=True, git_mirror=git).run(max_items=1)
        self.assertEqual(stats["created_issues"], 1)
        self.assertEqual(stats["created_prs"], 0)
        self.assertIn("Upstream PR archive",
                      [c for c in api.calls if c[0] == "POST"][0][2]["title"])

    def test_pr_422_falls_back_to_issue_archive(self):
        api = FakeAPI([issue(22, is_pr=True)], fail_pr=True)
        stats = m.Mirror(api, apply=True, git_mirror=FakeGit()).run(max_items=1)
        self.assertEqual(stats["created_issues"], 1)
        self.assertEqual(stats["created_prs"], 0)

    def test_archive_option_does_not_push_branch(self):
        api = FakeAPI([issue(13, is_pr=True)])
        git = FakeGit()
        stats = m.Mirror(api, apply=True, pr_mode="archive",
                         git_mirror=git).run(max_items=1)
        self.assertEqual(stats["created_issues"], 1)
        self.assertEqual(git.numbers, [])

    def test_comments_are_copied_with_source_marker(self):
        comment = {"id": 777, "body": "Found bug", "user": {"login": "reviewer"},
                   "html_url": "https://github.com/godotengine/godot/issues/1#issuecomment-777",
                   "created_at": "2026-11-01T00:00:00Z"}
        api = FakeAPI([issue(1)], comments=[comment])
        mirror = m.Mirror(api, apply=True, comments=True)
        mirror.run(max_items=1)
        posts = [x for x in api.calls if x[0] == "POST" and x[1].endswith("/comments")]
        self.assertEqual(len(posts), 1)
        self.assertIn("<!-- upstream-comment: 777 -->", posts[0][2]["body"])

    def test_errors_stop_batch_without_skipping_failed_issue(self):
        api = FakeAPI([issue(1), issue(2)])
        actual = api.request

        def fail_one(method, path, payload=None):
            if method == "POST" and path.endswith("/issues") and "Test #1" in payload["title"]:
                raise RuntimeError("transient failure")
            return actual(method, path, payload)
        api.request = fail_one
        result = m.Mirror(api, apply=True).run(max_items=2)
        self.assertEqual(result["errors"], 1)
        self.assertEqual(result["created_issues"], 0)

    def test_checkpoint_written_for_processed_items(self):
        api = FakeAPI([issue(1), issue(2), issue(3)])
        with tempfile.TemporaryDirectory() as folder:
            checkpoint = Path(folder) / "state.json"
            stats = m.Mirror(api, apply=True).run(max_items=2, checkpoint=checkpoint)
            self.assertEqual(stats["created_issues"], 2)
            self.assertEqual(__import__("json").loads(checkpoint.read_text())["next_offset"], 2)

    def test_large_unicode_body_preserves_valid_utf8_and_source_link(self):
        data = issue(5, body="🔧" * 25000)
        original = m.format_body(m.SOURCE_DEFAULT, data, "issues")
        self.assertLessEqual(len(original.encode("utf-8")), 60000)
        self.assertIn("Original content truncated", original)
        self.assertTrue(original.endswith("https://github.com/godotengine/godot/issues/5]"))

    def test_resume_by_repository_id_cursor(self):
        api = FakeAPI([issue(4)])
        mirror = m.Mirror(api)
        cursor = "/repositories/15634981/issues?after=opaque123&per_page=100"
        stats = mirror.run(start_page=700, start_cursor=cursor, max_items=1)
        self.assertEqual(stats["dry_run"], 1)
        self.assertTrue(any(x[1] == cursor for x in api.calls))

    def test_cursor_link_parsing_and_host_check(self):
        header = ('<https://api.github.com/repos/godotengine/godot/issues?after=opaque123&per_page=100>; rel="next", '
                  '<https://api.github.com/repos/godotengine/godot/issues?before=one>; rel="prev"')
        self.assertEqual(m.parse_next_link(header),
                         "/repos/godotengine/godot/issues?after=opaque123&per_page=100")
        self.assertIsNone(m.parse_next_link(""))
        with self.assertRaises(ValueError):
            m.parse_next_link('<https://evil.test/steal>; rel="next"')

    def test_github_pages_follow_cursor_instead_of_page_numbers(self):
        api = m.GitHub()
        calls = []
        def get(method, path, payload=None, with_links=False):
            calls.append((path, with_links))
            if len(calls) == 1:
                return ([{"number": 1}], "/repos/owner/repo/issues?after=cursor")
            return ([{"number": 2}], None)
        with patch.object(api, "request", side_effect=get):
            records = list(api.pages("/repos/owner/repo/issues?state=all"))
        self.assertEqual([x["number"] for x in records], [1, 2])
        self.assertTrue(all(flag for path, flag in calls))
        self.assertEqual(calls[1][0], "/repos/owner/repo/issues?after=cursor")

    def test_git_fetch_and_push_without_force(self):
        from types import SimpleNamespace
        calls = []

        def fake_git(directory, *args, check=True):
            calls.append(args)
            if args[0] == "diff":
                return SimpleNamespace(returncode=1, stdout="", stderr="")
            return SimpleNamespace(returncode=0, stdout="", stderr="")
        with patch.object(m, "git_run", side_effect=fake_git):
            self.assertTrue(m.GitHeadMirror(Path("."), m.SOURCE_DEFAULT, "master").push(99))
        self.assertTrue(any(x[0] == "fetch" and "refs/pull/99/head" in x for x in calls))
        self.assertTrue(any(x[0] == "push" and "FETCH_HEAD:refs/heads/upstream-mirror/pr-99" in x for x in calls))
        self.assertFalse(any("--force" in " ".join(x) for x in calls))


if __name__ == "__main__":
    unittest.main()
