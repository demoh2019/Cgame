"""Unit tests for the resumable GitHub upstream mirror (no network access)."""
import importlib.util
import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import Mock, patch

ROOT = Path(__file__).resolve().parents[2]
MODULE = ROOT / "misc/scripts/mirror_upstream_github.py"
spec = importlib.util.spec_from_file_location("upstream_mirror", MODULE)
mirror = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mirror)


def item(number=17, state="open", is_pr=False, comments=0, labels=None):
    value = {
        "number": number, "title": "Example", "body": "Original text",
        "user": {"login": "original-author"},
        "state": state, "created_at": "2020-01-01T00:00:00Z",
        "labels": labels or [], "comments": comments,
    }
    if is_pr:
        value["pull_request"] = {"url": "https://api.github.com/pulls/17"}
    return value


class ApiStub:
    def __init__(self, target_issues=True, source_items=()):
        self.calls = []
        self.target_issues = target_issues
        self.source_items = list(source_items)
        self.next_number = 101

    def request(self, method, path, payload=None, with_headers=False):
        self.calls.append((method, path, payload))
        if method == "GET" and path == "/repos/demoh2019/godot":
            return {"has_issues": self.target_issues}
        if method == "GET" and "/pulls/" in path:
            return {"base": {"ref": "master"}}
        if method == "POST" and (
            path == "/repos/demoh2019/godot/issues"
            or path == "/repos/demoh2019/godot/pulls"
        ):
            self.next_number += 1
            return {"number": self.next_number,
                    "html_url": f"https://github.com/demoh2019/godot/issues/{self.next_number}"}
        if method in ("POST", "PATCH"):
            return {}
        raise AssertionError((method, path))

    def pages(self, path):
        if path.startswith("/repos/godotengine/godot/issues?"):
            yield from self.source_items
        elif path.startswith("/repos/demoh2019/godot/pulls?"):
            yield from ()
        elif "/issues/" in path and "/comments?" in path:
            yield from ()


class PureFunctionTests(unittest.TestCase):
    def test_issue_key(self):
        self.assertEqual(mirror.source_key(item(), "issue"), "issue:17")

    def test_pull_key(self):
        self.assertEqual(mirror.source_key(item(257), "pr"), "pr:257")

    def test_marker(self):
        self.assertEqual(mirror.original_marker(17, "issue"),
                         "<!-- upstream-mirror:godotengine/godot#17:issue -->")

    def test_issue_description_provenance(self):
        result = mirror.source_description(item(), "issue")
        self.assertIn("https://github.com/godotengine/godot/issues/17", result)
        self.assertIn("@original-author", result)
        self.assertIn("Original text", result)
        self.assertIn("2020-01-01", result)

    def test_archive_description_provenance(self):
        result = mirror.source_description(item(state="closed"), "archive-pr")
        self.assertIn("https://github.com/godotengine/godot/pull/17", result)
        self.assertIn("Original state: closed", result)

    def test_unnamed_author(self):
        value = item()
        value.pop("user")
        self.assertIn("@unknown", mirror.source_description(value, "issue"))

    def test_empty_body(self):
        value = item()
        value["body"] = None
        self.assertNotIn("None", mirror.source_description(value, "issue"))

    def test_short_body_stays_single(self):
        body, continuation = mirror.split_body("abcdef", 10)
        self.assertEqual(body, "abcdef")
        self.assertIsNone(continuation)

    def test_large_body_continues(self):
        body, continuation = mirror.split_body("abcdefghijkl", 5)
        self.assertIn("continues", body)
        self.assertEqual(continuation, "fghijkl")

    def test_existing_pr_source_links(self):
        pulls = [
            {"number": 7, "html_url": "https://github.com/demoh2019/godot/pull/7",
             "body": "Backport https://github.com/godotengine/godot/pull/123"},
            {"number": 8, "html_url": "https://github.com/demoh2019/godot/pull/8",
             "body": "No matching source"},
        ]
        result = mirror.existing_upstream_pr_numbers(pulls)
        self.assertEqual(result[123]["number"], 7)
        self.assertNotIn(8, result)

    def test_none_pr_body(self):
        self.assertEqual(mirror.existing_upstream_pr_numbers([
            {"number": 7, "html_url": "x", "body": None}
        ]), {})

    def test_comment_attribution(self):
        result = mirror.comment_description({
            "body": "hello", "created_at": "2019-01-01",
            "html_url": "https://github.com/godotengine/godot/issues/17#issuecomment-1",
            "user": {"login": "bob"},
        })
        self.assertIn("@bob", result)
        self.assertIn("hello", result)
        self.assertIn("issuecomment-1", result)


class ImportTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.path = str(Path(self.tmp.name) / "mirror-state.json")

    def m(self, api, mode="issues", max_new=25, comments=False):
        return mirror.Mirror(api, self.path, mode, max_new, comments, git_dir=self.tmp.name)

    def test_issue_disabled_fails_before_import(self):
        api = ApiStub(target_issues=False, source_items=[item()])
        with self.assertRaisesRegex(RuntimeError, "Issues are disabled"):
            self.m(api).run()
        self.assertEqual(len([x for x in api.calls if x[0] == "POST"]), 0)

    def test_open_pr_mode_can_run_without_issues(self):
        api = ApiStub(target_issues=False)
        self.m(api, mode="open-prs").run()
        self.assertEqual(len([x for x in api.calls if x[0] == "POST"]), 0)

    def test_creates_open_issue_and_checkpoint(self):
        api = ApiStub(source_items=[item()])
        instance = self.m(api)
        instance.run()
        state = json.loads(Path(self.path).read_text())
        self.assertEqual(state["entries"]["issue:17"]["number"], 102)
        created = [c for c in api.calls if c[0] == "POST" and c[1].endswith("/issues")]
        self.assertEqual(len(created), 1)
        self.assertIn("upstream-mirror:", created[0][2]["body"])

    def test_creates_closed_issue_then_closes(self):
        api = ApiStub(source_items=[item(state="closed")])
        self.m(api).run()
        updates = [x for x in api.calls if x[0] == "PATCH"]
        self.assertEqual(len(updates), 1)
        self.assertEqual(updates[0][2], {"state": "closed"})

    def test_resume_does_not_duplicate(self):
        api = ApiStub(source_items=[item()])
        self.m(api).run()
        self.m(api).run()
        posts = [x for x in api.calls if x[0] == "POST" and x[1].endswith("/issues")]
        self.assertEqual(len(posts), 1)

    def test_max_new_limit(self):
        api = ApiStub(source_items=[item(17), item(18), item(19)])
        self.m(api, max_new=2).run()
        state = json.loads(Path(self.path).read_text())
        self.assertEqual(len(state["entries"]), 2)

    def test_issue_only_skips_pr(self):
        api = ApiStub(source_items=[item(17, is_pr=True), item(18)])
        self.m(api).run()
        state = json.loads(Path(self.path).read_text())
        self.assertEqual(sorted(state["entries"]), ["issue:18"])

    def test_closed_pr_is_archived_issue(self):
        api = ApiStub(source_items=[item(17, "closed", True)])
        self.m(api, mode="archive-prs").run()
        state = json.loads(Path(self.path).read_text())
        self.assertIn("archive-pr:17", state["entries"])
        create = [x for x in api.calls if x[0] == "POST" and x[1].endswith("/issues")][0]
        self.assertTrue(create[2]["title"].startswith("[Upstream PR #17]"))

    def test_comments_disabled_no_api_writes(self):
        api = ApiStub(source_items=[item(17, comments=3)])
        self.m(api, comments=False).run()
        self.assertFalse(any(x[1].endswith("/comments") for x in api.calls))

    def test_git_fetch_push_and_pr_creation(self):
        api = ApiStub(source_items=[item(17, is_pr=True)])
        instance = self.m(api, mode="open-prs")
        with patch.object(instance, "git") as git:
            instance.run()
        self.assertEqual(git.call_count, 2)
        create = [x for x in api.calls if x[0] == "POST" and x[1].endswith("/pulls")][0]
        self.assertEqual(create[2]["base"], "master")
        self.assertEqual(create[2]["head"], "upstream-mirror/pr-17")
        self.assertTrue(create[2]["draft"])

    def test_open_pr_mode_skips_closed_pr(self):
        api = ApiStub(source_items=[item(17, "closed", True)])
        self.m(api, mode="open-prs").run()
        self.assertFalse(any(x[0] == "POST" for x in api.calls))


class ExtendedImportTests(ImportTests):
    def test_unlimited_batch_creates_all(self):
        api = ApiStub(source_items=[item(17), item(18), item(19)])
        self.m(api, max_new=0).run()
        entries = json.loads(Path(self.path).read_text())["entries"]
        self.assertEqual(len(entries), 3)

    def test_label_copy(self):
        api = ApiStub(source_items=[
            item(17, labels=[{"name": "bug", "color": "f00", "description": "Bug report"}])
        ])
        self.m(api).run()
        labels = [x for x in api.calls if x[0] == "POST" and x[1].endswith("/labels")]
        self.assertEqual(len(labels), 1)
        self.assertEqual(labels[0][2]["name"], "bug")
        created = [x for x in api.calls if x[0] == "POST" and x[1].endswith("/issues")][0]
        self.assertEqual(created[2]["labels"], ["bug"])

    def test_copies_and_checkpoints_comments_once(self):
        class CommentApi(ApiStub):
            def pages(self, path):
                if "/comments?" in path:
                    yield {"id": 1, "body": "first",
                           "user": {"login": "alice"}, "created_at": "2020-01-01"}
                    yield {"id": 2, "body": "second",
                           "user": {"login": "bob"}, "created_at": "2020-01-02"}
                else:
                    yield from super().pages(path)

        api = CommentApi(source_items=[item(17, comments=2)])
        self.m(api, comments=True).run()
        self.m(api, comments=True).run()
        comments = [x for x in api.calls if x[0] == "POST" and x[1].endswith("/comments")]
        self.assertEqual(len(comments), 2)
        self.assertIn("@alice", comments[0][2]["body"])
        checkpoint = json.loads(Path(self.path).read_text())["entries"]["issue:17"]
        self.assertEqual(checkpoint["last_comment_id"], 2)
        self.assertTrue(checkpoint["comments_complete"])

    def test_failed_item_is_recorded_not_silenced(self):
        class FailApi(ApiStub):
            def request(self, method, path, payload=None, with_headers=False):
                if method == "POST" and path.endswith("/issues"):
                    raise mirror.ApiError("test failure")
                return super().request(method, path, payload, with_headers)

        api = FailApi(source_items=[item(17)])
        self.m(api).run()
        state = json.loads(Path(self.path).read_text())
        self.assertIn("issue:17", state["errors"])
        self.assertNotIn("issue:17", state["entries"])

    def test_preexisting_port_not_recreated(self):
        class ExistingApi(ApiStub):
            def pages(self, path):
                if path.startswith("/repos/demoh2019/godot/pulls?"):
                    yield {"number": 7, "html_url": "https://github.com/demoh2019/godot/pull/7",
                           "body": "Port https://github.com/godotengine/godot/pull/17"}
                else:
                    yield from super().pages(path)
        api = ExistingApi(source_items=[item(17, is_pr=True)])
        instance = self.m(api, mode="open-prs", comments=True)
        with patch.object(instance, "git") as git:
            instance.run()
        git.assert_not_called()
        state = json.loads(Path(self.path).read_text())["entries"]["pr:17"]
        self.assertEqual(state["number"], 7)
        self.assertTrue(state["comments_complete"])


class ApiTests(unittest.TestCase):
    def test_pagination_with_lowercase_link_header(self):
        class FakeResponse:
            def __init__(self, payload, headers):
                self.payload = payload
                self.headers = headers

            def __enter__(self):
                return self

            def __exit__(self, *_):
                return False

            def read(self):
                return json.dumps(self.payload).encode()

        urls = []

        def opener(request, timeout):
            urls.append(request.full_url)
            if len(urls) == 1:
                return FakeResponse([{"number": 1}], {
                    "link": '<https://api.github.com/items?page=2>; rel="next"'
                })
            return FakeResponse([{"number": 2}], {})

        api = mirror.Api("test-token", pause=0, opener=opener, sleep=lambda _: None)
        self.assertEqual([x["number"] for x in api.pages("/items")], [1, 2])
        self.assertEqual(len(urls), 2)

    def test_header_and_json_encoding_for_write(self):
        class FakeResponse:
            headers = {}
            def __enter__(self):
                return self
            def __exit__(self, *_):
                return False
            def read(self):
                return b'{"number": 1}'

        def opener(request, timeout):
            self.assertEqual(request.get_method(), "POST")
            self.assertEqual(json.loads(request.data), {"title": "test"})
            self.assertEqual(request.get_header("Authorization"), "Bearer test")
            return FakeResponse()

        api = mirror.Api("test", pause=0, opener=opener, sleep=lambda _: None)
        self.assertEqual(api.request("POST", "/issues", {"title": "test"})["number"], 1)

    def test_api_error_does_not_retry_404(self):
        from urllib.error import HTTPError
        from io import BytesIO

        calls = []

        def opener(request, timeout):
            calls.append(request)
            raise HTTPError(request.full_url, 404, "Not Found",
                            {}, BytesIO(b'{"message":"Not Found"}'))

        api = mirror.Api("token", pause=0, opener=opener, sleep=lambda _: None)
        with self.assertRaisesRegex(mirror.ApiError, "HTTP 404"):
            api.request("GET", "/missing")
        self.assertEqual(len(calls), 1)

    def test_api_retry_on_503(self):
        from urllib.error import HTTPError
        from io import BytesIO

        class FakeResponse:
            headers = {}
            def __enter__(self):
                return self
            def __exit__(self, *_):
                return False
            def read(self):
                return b'{"ok":true}'

        calls, sleeps = [], []

        def opener(request, timeout):
            calls.append(request)
            if len(calls) == 1:
                raise HTTPError(request.full_url, 503, "Unavailable",
                                {}, BytesIO(b'{"message":"retry"}'))
            return FakeResponse()

        api = mirror.Api("token", pause=0, opener=opener, sleep=sleeps.append)
        self.assertTrue(api.request("GET", "/retry")["ok"])
        self.assertEqual(len(calls), 2)
        self.assertEqual(len(sleeps), 1)


class CliSafetyTests(unittest.TestCase):
    def test_open_prs_require_explicit_security_opt_in(self):
        with patch("sys.argv", ["mirror", "--mode", "open-prs"]):
            with patch.dict("os.environ", {"GH_TOKEN": "fake"}, clear=False):
                with self.assertRaises(SystemExit) as context:
                    mirror.main()
        self.assertEqual(context.exception.code, 2)

    def test_all_requires_explicit_security_opt_in(self):
        with patch("sys.argv", ["mirror", "--mode", "all"]):
            with self.assertRaises(SystemExit) as context:
                mirror.main()
        self.assertEqual(context.exception.code, 2)

    def test_issues_mode_has_no_untrusted_pr_requirement(self):
        with patch("sys.argv", ["mirror", "--mode", "issues", "--max-new", "1"]):
            with patch.dict("os.environ", {"GH_TOKEN": "fake"}, clear=False):
                with patch.object(mirror.Mirror, "run") as run:
                    mirror.main()
        run.assert_called_once()

    def test_negative_batch_limit_rejected(self):
        with patch("sys.argv", ["mirror", "--mode", "issues", "--max-new", "-1"]):
            with self.assertRaises(SystemExit) as context:
                mirror.main()
        self.assertEqual(context.exception.code, 2)


if __name__ == "__main__":
    unittest.main()
