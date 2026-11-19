"""Zero-network unit tests for the upstream issue/PR metadata mirror."""

import base64
import json
import sys
import unittest
from pathlib import Path
from urllib.parse import parse_qs, urlsplit
from unittest.mock import Mock

sys.path.insert(0, str(Path(__file__).parent))
from upstream_mirror import APIError, Mirror, RemoteCheckpoint, State, format_item, marker, source_url


def issue(number, *, pr=False, state="open", body="description"):
    result = {
        "number": number,
        "title": f"Bug {number}",
        "state": state,
        "body": body,
        "labels": [{"name": "bug"}],
        "user": {"login": "alice"},
        "comments": 2,
        "created_at": "2026-01-01T00:00:00Z",
    }
    if pr:
        result["pull_request"] = {"url": "https://api.github.com/example"}
    return result


class FakeAPI:
    def __init__(self, source=None, *, issues_enabled=True):
        self.source = source or []
        self.issues_enabled = issues_enabled
        self.requests = []
        self.created = []
        self.existing = []
        self.next_number = 41
        self.labels = {"upstream-mirror-issue", "upstream-mirror-pr"}

    def request(self, method, path, payload=None):
        self.requests.append((method, path, payload))
        if path == "/repos/demoh2019/Cgame":
            return {"has_issues": self.issues_enabled}
        if path.startswith("/repos/demoh2019/Cgame/labels/"):
            name = path.rsplit("/", 1)[1]
            if name not in self.labels:
                raise APIError(404, "missing label")
            return {"name": name}
        if path == "/repos/demoh2019/Cgame/labels" and method == "POST":
            self.labels.add(payload["name"])
            return payload
        if path.startswith("/repos/demoh2019/Cgame/issues?state=all"):
            if parse_qs(urlsplit(path).query).get("page") == ["1"]:
                return list(reversed(self.existing))[:100]
            return []
        if path.startswith("/repos/godotengine/godot/issues?"):
            page = int(parse_qs(urlsplit(path).query)["page"][0]); return self.source[(page - 1) * 100:page * 100]
        if path.startswith("/repos/godotengine/godot/pulls/"):
            return {"base": {"ref": "master"}, "head": {"label": "alice:patch", "sha": "abc"}, "draft": True, "merged_at": None}
        if path == "/repos/demoh2019/Cgame/issues" and method == "POST":
            self.created.append(payload)
            result = {"number": self.next_number, "html_url": f"https://github.com/demoh2019/Cgame/issues/{self.next_number}", "body": payload["body"]}
            self.existing.append(result)
            self.next_number += 1
            return result
        if path.startswith("/repos/demoh2019/Cgame/issues/") and method == "PATCH":
            return {"ok": True}
        raise AssertionError(f"Unexpected request: {method} {path}")


class FakeStore:
    def __init__(self, state=None):
        self.state = state or State()
        self.saved = []

    def load(self):
        return State.from_json(self.state.__dict__)

    def save(self, state):
        self.state = State.from_json(state.__dict__)
        self.saved.append(self.state)


class TestFormatting(unittest.TestCase):
    def test_issue_body_attribution(self):
        title, body, label = format_item(issue(42))
        self.assertEqual(label, "upstream-mirror-issue")
        self.assertIn("@alice", body)
        self.assertIn("Original labels: bug", body)
        self.assertIn("https://github.com/godotengine/godot/issues/42", body)
        self.assertIn(marker(42), body)
        self.assertEqual(title, "[Upstream Issue #42] Bug 42")

    def test_pr_body_is_not_misrepresented_as_code_port(self):
        pr = {"base": {"ref": "3.x"}, "head": {"label": "alice:fix", "sha": "abc"}, "draft": True, "merged_at": None}
        title, body, label = format_item(issue(99, pr=True), pr)
        self.assertEqual(label, "upstream-mirror-pr")
        self.assertIn("not a ported pull request", body)
        self.assertIn("Original head SHA: `abc`", body)
        self.assertIn("https://github.com/godotengine/godot/pull/99/files", body)
        self.assertIn("Original base: `3.x`", body)
        self.assertEqual(source_url(issue(99, pr=True)), "https://github.com/godotengine/godot/pull/99")

    def test_merged_pr_preserves_merged_state(self):
        _, body, _ = format_item(issue(8, pr=True, state="closed"), {"base": {"ref": "master"}, "head": {"label": "x:y", "sha": "x"}, "merged_at": "2026-01-02"})
        self.assertIn("Original status: `merged`", body)

    def test_long_description_is_truncated_without_dropping_source(self):
        title, body, _ = format_item(issue(7, body="x" * 100_000))
        self.assertLess(len(body), 65_000)
        self.assertIn("Truncated", body)
        self.assertIn(marker(7), body)
        self.assertLessEqual(len(title), 256)

    def test_no_optional_body_or_labels(self):
        obj = issue(20); obj["body"] = None; obj.pop("labels")
        _, body, _ = format_item(obj)
        self.assertIn("No description", body)
        self.assertIn("Original labels: —", body)


class TestWorkflow(unittest.TestCase):
    def test_issues_disabled_blocks_writes(self):
        api = FakeAPI([issue(1)], issues_enabled=False)
        store = FakeStore()
        with self.assertRaisesRegex(RuntimeError, "Issues are disabled"):
            Mirror(api, store).run(max_items=1)
        self.assertFalse(api.created)

    def test_dry_run_works_without_issues_and_no_checkpoint(self):
        api = FakeAPI([issue(1)], issues_enabled=False)
        store = FakeStore()
        result = Mirror(api, store, dry_run=True).run(max_items=1)
        self.assertEqual(result.total_mirrored, 1)
        self.assertEqual(store.saved, [])
        self.assertFalse(api.created)

    def test_mixed_issue_and_pr_open_closed_and_resume(self):
        api = FakeAPI([issue(1), issue(2, pr=True), issue(3, state="closed")])
        store = FakeStore()
        state = Mirror(api, store).run(max_items=2, checkpoint_every=1)
        self.assertEqual(state.last_source_number, 2)
        self.assertEqual(len(api.created), 2)
        self.assertEqual(api.created[1]["labels"], ["upstream-mirror-pr"])
        new_state = Mirror(api, store).run(max_items=2, checkpoint_every=1)
        self.assertTrue(new_state.finished)
        self.assertEqual(new_state.last_source_number, 3)
        self.assertEqual(len(api.created), 3)
        self.assertTrue(any(method == "PATCH" and path.endswith("/43") for method, path, _ in api.requests))
        Mirror(api, store).run(max_items=10)
        self.assertEqual(len(api.created), 3)

    def test_recovers_from_successful_create_before_checkpoint(self):
        api = FakeAPI([issue(1), issue(2), issue(3)])
        api.existing.append({"number": 99, "body": marker(2)})
        store = FakeStore(State(page=1, offset=0, last_source_number=0))
        result = Mirror(api, store).run(max_items=1)
        self.assertEqual(result.last_source_number, 3)
        self.assertEqual(len(api.created), 1)
        self.assertEqual(api.created[0]["title"], "[Upstream Issue #3] Bug 3")

    def test_resume_across_page_boundary(self):
        api = FakeAPI([issue(n) for n in range(1, 105)])
        store = FakeStore(State(page=1, offset=99, last_source_number=99, total_mirrored=99))
        result = Mirror(api, store).run(max_items=3)
        self.assertEqual([obj["title"] for obj in api.created], [f"[Upstream Issue #{n}] Bug {n}" for n in (100, 101, 102)])
        self.assertEqual((result.page, result.offset), (2, 2))

    def test_does_not_advance_checkpoint_on_create_error(self):
        api = FakeAPI([issue(1)])
        orig = api.request
        def failing(method, path, payload=None):
            if method == "POST" and path == "/repos/demoh2019/Cgame/issues":
                raise APIError(403, "secondary rate limit")
            return orig(method, path, payload)
        api.request = failing
        store = FakeStore()
        with self.assertRaises(APIError):
            Mirror(api, store).run(max_items=1)
        self.assertEqual(store.state.last_source_number, 0)
        self.assertFalse(api.created)

    def test_labels_are_created_when_missing(self):
        api = FakeAPI([issue(2)]); api.labels.clear()
        Mirror(api, FakeStore()).run(max_items=1)
        self.assertEqual(api.labels, {"upstream-mirror-pr", "upstream-mirror-issue"})

    def test_state_validation(self):
        with self.assertRaises(ValueError): State.from_json({"offset": 100})
        with self.assertRaises(ValueError): State.from_json({"page": 0})
        self.assertEqual(State.from_json({"page": 3}).page, 3)




class FakeCheckpointAPI:
    def __init__(self):
        self.calls = []
        self.branch = False
        self.content = None
        self.sha = None
        self.conflict = False

    def request(self, method, path, payload=None):
        self.calls.append((method, path, payload))
        if method == "GET" and "/contents/" in path:
            if self.content is None:
                raise APIError(404, "Not Found")
            return {"sha": self.sha, "content": base64.b64encode(self.content).decode()}
        if method == "GET" and path.endswith("/git/ref/heads/upstream-mirror-state"):
            if not self.branch:
                raise APIError(404, "Not Found")
            return {"object": {"sha": "1" * 40}}
        if method == "GET" and path.endswith("/git/ref/heads/master"):
            return {"object": {"sha": "2" * 40}}
        if method == "POST" and path.endswith("/git/refs"):
            self.branch = True
            self.branch_payload = payload
            return {"ref": payload["ref"]}
        if method == "PUT" and "/contents/" in path:
            if self.conflict:
                raise APIError(409, "Concurrent write")
            self.content = base64.b64decode(payload["content"])
            self.sha = "newsha"
            return {"content": {"sha": "newsha"}}
        raise AssertionError((method, path))


class TestCheckpoint(unittest.TestCase):
    def test_initial_state_then_create_isolated_branch(self):
        api = FakeCheckpointAPI()
        store = RemoteCheckpoint(api)
        self.assertEqual(store.load(), State())
        store.save(State(page=5, offset=22, last_source_number=420, total_mirrored=420))
        self.assertTrue(api.branch)
        self.assertEqual(api.branch_payload["sha"], "2" * 40)
        self.assertEqual(json.loads(api.content)["last_source_number"], 420)
        self.assertFalse(any("/git/ref/heads/master" in p and m != "GET" for m, p, _ in api.calls))

    def test_checkpoint_reload_roundtrip_and_sha(self):
        api = FakeCheckpointAPI(); api.branch = True
        store = RemoteCheckpoint(api)
        store.save(State(page=2, offset=13, last_source_number=111))
        store2 = RemoteCheckpoint(api)
        state = store2.load()
        self.assertEqual((state.page, state.offset, state.last_source_number), (2, 13, 111))
        store2.save(State(page=3, last_source_number=200))
        puts = [payload for method, path, payload in api.calls if method == "PUT"]
        self.assertEqual(puts[1]["sha"], "newsha")

    def test_checkpoint_conflict_is_not_overwritten(self):
        api = FakeCheckpointAPI(); api.branch = True; api.conflict = True
        with self.assertRaisesRegex(RuntimeError, "Concurrent checkpoint"):
            RemoteCheckpoint(api).save(State(last_source_number=10))


class TestNewUpstreamEvents(unittest.TestCase):
    def test_completed_partial_page_sees_new_items_later(self):
        api = FakeAPI([issue(1), issue(2)])
        store = FakeStore()
        state = Mirror(api, store).run(max_items=10)
        self.assertTrue(state.finished)
        self.assertEqual((state.page, state.offset), (1, 2))
        api.source.append(issue(3))
        state = Mirror(api, store).run(max_items=10)
        self.assertEqual(len(api.created), 3)
        self.assertTrue(state.finished)
        self.assertEqual(state.last_source_number, 3)

    def test_empty_source_keeps_first_page(self):
        api = FakeAPI([])
        store = FakeStore()
        state = Mirror(api, store).run(max_items=10)
        self.assertTrue(state.finished)
        api.source.append(issue(9))
        Mirror(api, store).run(max_items=10)
        self.assertEqual(len(api.created), 1)

    def test_resuming_completed_checkpoint_with_no_new_items_is_noop(self):
        api = FakeAPI([issue(1)])
        store = FakeStore()
        Mirror(api, store).run(max_items=10)
        count = len(api.created)
        Mirror(api, store).run(max_items=10)
        self.assertEqual(len(api.created), count)


if __name__ == "__main__":
    unittest.main()
