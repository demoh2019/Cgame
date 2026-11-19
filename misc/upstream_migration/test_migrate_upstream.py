#!/usr/bin/env python3
"""Offline regression suite. Run: python -m unittest -v test_migrate_upstream.py"""
import io
import json
import os
import tempfile
import unittest
from contextlib import redirect_stdout
from unittest.mock import patch

import migrate_upstream as m


class FakeAPI:
    def __init__(self, *, source_issues=(), source_prs=(), dest_issues=(), dest_prs=(), labels=(), comments=None):
        self.source_issues = list(source_issues)
        self.source_prs = list(source_prs)
        self.dest_issues = list(dest_issues)
        self.dest_prs = list(dest_prs)
        self.labels = list(labels)
        self.comments = comments or {}
        self.posts = []
        self.patches = []
        self.raise_on_post = None

    def pages(self, path):
        if f"/{m.SOURCE}/issues?" in path:
            return iter(self.source_issues)
        if f"/{m.SOURCE}/pulls?" in path:
            return iter(self.source_prs)
        if f"/{m.TARGET}/issues?" in path:
            return iter(self.dest_issues)
        if f"/{m.TARGET}/pulls?" in path:
            return iter(self.dest_prs)
        if f"/{m.TARGET}/labels?" in path:
            return iter(self.labels)
        if "/comments?" in path:
            return iter(self.comments.get(path, []))
        raise AssertionError(f"Unexpected request: {path}")

    def post(self, path, body):
        if self.raise_on_post is not None:
            raise self.raise_on_post
        self.posts.append((path, body))
        return {"number": len(self.posts) + 900, "html_url": "https://github.com/demoh2019/Cgame/issues/900"}

    def patch(self, path, body):
        self.patches.append((path, body))
        return body


def issue(n=12, **kwargs):
    return {"number": n, "title": "Some bug", "body": "Steps to reproduce",
            "user": {"login": "original-author"}, "state": "open", "created_at": "2026-01-01T00:00:00Z",
            "updated_at": "2026-02-01T00:00:00Z", "labels": [], **kwargs}


def pr(n=13, **kwargs):
    return {"number": n, "title": "Fix the bug", "body": "PR description", "state": "open",
            "user": {"login": "contributor"}, "base": {"ref": "master"}, "created_at": "2026-01-01", **kwargs}


class RepositoryTargetTests(unittest.TestCase):
    def test_uses_canonical_fork_repository(self):
        self.assertEqual(m.TARGET, "demoh2019/Cgame")

    def test_does_not_write_to_source_repository(self):
        self.assertNotEqual(m.TARGET, m.SOURCE)

    def test_backport_target_branch(self):
        self.assertEqual(m.TARGET_BASE, "develop")

    def test_destination_api_uses_canonical_name(self):
        self.assertTrue(m.page_path(m.TARGET, "issues", "open").startswith(
            "/repos/demoh2019/Cgame/issues?"
        ))


class ParserTests(unittest.TestCase):
    def test_origin_issue_valid_link(self):
        self.assertEqual(m.origin_issue_number("source https://github.com/godotengine/godot/issues/125618"), 125618)

    def test_origin_issue_rejects_other_project(self):
        self.assertIsNone(m.origin_issue_number("https://github.com/another/godot/issues/88"))

    def test_origin_issue_handles_empty(self):
        self.assertIsNone(m.origin_issue_number(None))

    def test_origin_pr_source_url(self):
        self.assertEqual(m.origin_pr_number("See https://github.com/godotengine/godot/pull/125593"), 125593)

    def test_origin_pr_title(self):
        self.assertEqual(m.origin_pr_number("", "Backport upstream #125502: fix Control"), 125502)

    def test_origin_pr_title_case_insensitive(self):
        self.assertEqual(m.origin_pr_number("", "PORT #1234"), 1234)

    def test_origin_pr_does_not_take_unrelated_issue_number(self):
        self.assertIsNone(m.origin_pr_number("Fixes issue #12500", "Fix crash"))

    def test_issue_body_attribution(self):
        s = m.issue_body(issue())
        self.assertIn("https://github.com/godotengine/godot/issues/12", s)
        self.assertIn("@original-author", s)
        self.assertIn("2026-01-01", s)
        self.assertIn("Steps to reproduce", s)

    def test_issue_body_missing_body(self):
        i = issue()
        i['body'] = None
        self.assertIn("<!-- upstream-issue: godotengine/godot#12 -->", m.issue_body(i))

    def test_issue_body_labels(self):
        i = issue()
        i['labels'] = [{"name": "bug"}, {"name": "topic:rendering"}]
        self.assertIn("`bug`, `topic:rendering`", m.issue_body(i))

    def test_imported_comment_attribution_and_marker(self):
        s = m.imported_comment({"id": 314, "user": {"login": "alice"},
                                "created_at": "2025-03-09", "html_url": "https://example/comment", "body": "solution"})
        self.assertIn("@alice", s)
        self.assertIn("upstream-comment-id: 314", s)
        self.assertIn("solution", s)

    def test_archived_pr_makes_state_explicit(self):
        i = pr()
        i['state'] = 'closed'
        i['merged_at'] = '2026-01-02'
        b = m.pr_archive_body(i)
        self.assertIn('state: **merged**', b)
        self.assertIn('pull/13', b)

    def test_paths_validate_state(self):
        with self.assertRaises(ValueError):
            m.page_path('x/y', 'releases', 'all')

    def test_paths_validate_kind(self):
        with self.assertRaises(ValueError):
            m.page_path('x/y', 'issues', 'latest')

    def test_paths_include_pages(self):
        self.assertIn('page=7', m.page_path('x/y', 'issues', 'all', 7))

    def test_args_dry_run(self):
        a = m.parse_args(['issues'])
        self.assertFalse(a.apply)
        self.assertEqual(a.limit, 20)

    def test_args_apply(self):
        a = m.parse_args(['issues', '--apply', '--comments', '--open-only', '--start-page', '4'])
        self.assertTrue(a.apply)
        self.assertTrue(a.comments)
        self.assertTrue(a.open_only)
        self.assertEqual(a.start_page, 4)

    def test_args_negative_limit(self):
        with redirect_stdout(io.StringIO()), self.assertRaises(SystemExit):
            m.parse_args(['issues', '--limit', '-1'])

    def test_args_zero_page(self):
        with redirect_stdout(io.StringIO()), self.assertRaises(SystemExit):
            m.parse_args(['prs', '--start-page', '0'])


class IndexTests(unittest.TestCase):
    def test_existing_issues_and_pr_archives(self):
        api = FakeAPI(dest_issues=[
            {"number": 1, "body": "Source https://github.com/godotengine/godot/issues/123"},
            {"number": 2, "body": "Archived https://github.com/godotengine/godot/pull/456"},
            {"number": 3, "body": "A PR", "pull_request": {"url": "url"}},
        ], dest_prs=[{"number": 4, "title": "Port upstream #789", "body": "backport"}])
        issues, archives, prs = m.target_indexes(api)
        self.assertEqual(set(issues), {123})
        self.assertEqual(set(archives), {456})
        self.assertEqual(set(prs), {789})

    def test_empty_indexes(self):
        self.assertEqual(m.target_indexes(FakeAPI()), ({}, {}, {}))


class IssueTests(unittest.TestCase):
    def test_dry_run_no_write(self):
        api = FakeAPI(source_issues=[issue()])
        with redirect_stdout(io.StringIO()):
            stats = m.migrate_issues(api, m.Settings(limit=20), {})
        self.assertEqual(stats['created'], 0)
        self.assertEqual(stats['scanned'], 1)
        self.assertEqual(api.posts, [])

    def test_applies_open_issue(self):
        api = FakeAPI(source_issues=[issue()])
        with redirect_stdout(io.StringIO()):
            stats = m.migrate_issues(api, m.Settings(apply=True), {})
        self.assertEqual(stats['created'], 1)
        self.assertEqual(len(api.posts), 1)
        self.assertIn('/issues', api.posts[0][0])
        self.assertEqual(api.patches, [])

    def test_copies_existing_labels(self):
        i = issue()
        i['labels'] = [{"name": "bug", "color": "ffee00"}]
        api = FakeAPI(source_issues=[i], labels=[{"name": "bug"}])
        with redirect_stdout(io.StringIO()):
            m.migrate_issues(api, m.Settings(apply=True), {})
        self.assertEqual(len(api.posts), 1)
        self.assertEqual(api.posts[0][1]['labels'], ['bug'])

    def test_creates_missing_label_only_once(self):
        a, b = issue(12), issue(13)
        for i in (a, b):
            i['labels'] = [{"name": "crash", "color": "123abc"}]
        api = FakeAPI(source_issues=[a, b])
        with redirect_stdout(io.StringIO()):
            m.migrate_issues(api, m.Settings(apply=True), {})
        label_posts = [body for path, body in api.posts if path.endswith('/labels')]
        self.assertEqual(len(label_posts), 1)
        self.assertEqual(label_posts[0]['color'], '123abc')

    def test_skips_existing_issue(self):
        api = FakeAPI(source_issues=[issue()])
        with redirect_stdout(io.StringIO()):
            stats = m.migrate_issues(api, m.Settings(apply=True), {12: {"number": 1}})
        self.assertEqual(stats['existing'], 1)
        self.assertEqual(api.posts, [])

    def test_closes_originally_closed_issue(self):
        i = issue()
        i['state'] = 'closed'
        api = FakeAPI(source_issues=[i])
        with redirect_stdout(io.StringIO()):
            m.migrate_issues(api, m.Settings(apply=True), {})
        self.assertEqual(len(api.patches), 1)
        self.assertEqual(api.patches[0][1], {"state": "closed"})

    def test_issue_disabled_diagnostic(self):
        api = FakeAPI(source_issues=[issue()])
        api.raise_on_post = m.GitHubError(410, "Issues disabled")
        with self.assertRaisesRegex(RuntimeError, "Enable Settings"):
            with redirect_stdout(io.StringIO()):
                m.migrate_issues(api, m.Settings(apply=True), {})

    def test_ignores_pr_in_issues_endpoint(self):
        i = issue()
        i['pull_request'] = {'url': 'https://example/pr'}
        api = FakeAPI(source_issues=[i, issue(14)])
        with redirect_stdout(io.StringIO()):
            stats = m.migrate_issues(api, m.Settings(apply=True), {})
        self.assertEqual(stats['scanned'], 1)
        self.assertEqual(stats['created'], 1)

    def test_respects_limit(self):
        api = FakeAPI(source_issues=[issue(x) for x in range(10, 16)])
        with redirect_stdout(io.StringIO()):
            stats = m.migrate_issues(api, m.Settings(apply=True, limit=2), {})
        self.assertEqual(stats['scanned'], 2)
        self.assertEqual(stats['created'], 2)

    def test_comments_are_imported(self):
        i = issue()
        source = f'/repos/{m.SOURCE}/issues/12/comments?per_page=100'
        dest = f'/repos/{m.TARGET}/issues/901/comments?per_page=100'
        c = {'id': 50, 'body': 'Comment text', 'user': {'login': 'bob'}}
        api = FakeAPI(source_issues=[i], comments={source: [c], dest: []})
        with redirect_stdout(io.StringIO()):
            stats = m.migrate_issues(api, m.Settings(apply=True, comments=True), {})
        self.assertEqual(stats['comments'], 1)
        self.assertIn('upstream-comment-id: 50', api.posts[-1][1]['body'])

    def test_existing_comment_not_reimported(self):
        source = f'/repos/{m.SOURCE}/issues/12/comments?per_page=100'
        dest = f'/repos/{m.TARGET}/issues/1/comments?per_page=100'
        c = {'id': 50, 'body': 'Comment text'}
        api = FakeAPI(source_issues=[issue()], comments={source: [c], dest: [{"body": "upstream-comment-id: 50"}]})
        with redirect_stdout(io.StringIO()):
            stats = m.migrate_issues(api, m.Settings(apply=True, comments=True), {12: {"number": 1}})
        self.assertEqual(stats['comments'], 0)
        self.assertEqual(api.posts, [])


class PullRequestTests(unittest.TestCase):
    def test_dryrun_open_code(self):
        api = FakeAPI(source_prs=[pr()])
        with redirect_stdout(io.StringIO()):
            stats = m.migrate_prs(api, m.Settings(code=True), {}, {})
        self.assertEqual(stats['created'], 0)
        self.assertEqual(stats['scanned'], 1)

    def test_no_automatic_pr_creation_without_code_flag(self):
        api = FakeAPI(source_prs=[pr()])
        with redirect_stdout(io.StringIO()):
            stats = m.migrate_prs(api, m.Settings(apply=True), {}, {})
        self.assertEqual(stats['skipped'], 1)
        self.assertEqual(api.posts, [])

    def test_existing_pr_skipped(self):
        api = FakeAPI(source_prs=[pr()])
        with redirect_stdout(io.StringIO()):
            stats = m.migrate_prs(api, m.Settings(apply=True, code=True), {13: {}}, {})
        self.assertEqual(stats['existing'], 1)

    def test_historical_merged_archive_dry_run(self):
        i = pr()
        i['state'] = 'closed'
        i['merged_at'] = '2026-01-15'
        api = FakeAPI(source_prs=[i])
        with redirect_stdout(io.StringIO()):
            stats = m.migrate_prs(api, m.Settings(archive_closed_prs=True), {}, {})
        self.assertEqual(stats['archived'], 0)
        self.assertEqual(api.posts, [])

    def test_historical_archive_produces_closed_issue(self):
        i = pr()
        i['state'] = 'closed'
        api = FakeAPI(source_prs=[i])
        with redirect_stdout(io.StringIO()):
            stats = m.migrate_prs(api, m.Settings(apply=True, archive_closed_prs=True), {}, {})
        self.assertEqual(stats['archived'], 1)
        self.assertIn('PR #13', api.posts[0][1]['title'])
        self.assertEqual(api.patches[0][1]['state'], 'closed')

    def test_open_pr_backport_call(self):
        api = FakeAPI(source_prs=[pr()])
        with patch.object(m, 'backport_pr', return_value='https://github.com/example/pull/1') as call:
            with redirect_stdout(io.StringIO()):
                stats = m.migrate_prs(api, m.Settings(apply=True, code=True), {}, {})
        self.assertEqual(stats['created'], 1)
        call.assert_called_once()

    def test_unrelated_branch_not_ported_to_master(self):
        i = pr()
        i['base'] = {'ref': '3.x'}
        api = FakeAPI(source_prs=[i])
        with patch.object(m, 'backport_pr') as call:
            with redirect_stdout(io.StringIO()):
                stats = m.migrate_prs(api, m.Settings(apply=True, code=True), {}, {})
        self.assertEqual(stats['skipped'], 1)
        call.assert_not_called()

    def test_conflicts_are_recorded(self):
        api = FakeAPI(source_prs=[pr()])
        with patch.object(m, 'backport_pr', return_value='conflict'):
            with redirect_stdout(io.StringIO()):
                stats = m.migrate_prs(api, m.Settings(apply=True, code=True), {}, {})
        self.assertEqual(stats['conflicts'], 1)

    def test_backport_failure_is_not_overwritten(self):
        api = FakeAPI(source_prs=[pr()])
        with patch.object(m, 'backport_pr', side_effect=ValueError('git failed')):
            with redirect_stdout(io.StringIO()):
                stats = m.migrate_prs(api, m.Settings(apply=True, code=True), {}, {})
        self.assertEqual(stats['conflicts'], 1)
        self.assertEqual(stats['created'], 0)

    def test_pr_jsonl_archive(self):
        api = FakeAPI(source_prs=[pr()])
        with tempfile.TemporaryDirectory() as d:
            out = os.path.join(d, 'archive.jsonl')
            with redirect_stdout(io.StringIO()):
                m.migrate_prs(api, m.Settings(apply=True, archive_path=out), {}, {})
            with open(out, encoding='utf-8') as f:
                obj = json.loads(f.readline())
        self.assertEqual(obj['number'], 13)


class HTTPTests(unittest.TestCase):
    def test_rejects_requests_outside_repo_endpoint(self):
        client = m.GitHub('token', pause=0)
        with self.assertRaises(ValueError):
            client.request('GET', '/user')

    def test_requires_token(self):
        with self.assertRaises(ValueError):
            m.GitHub('')

    def test_post_is_not_retried_after_network_failure(self):
        from urllib.error import URLError
        client = m.GitHub('token', pause=0)
        with patch.object(m, 'urlopen', side_effect=URLError('offline')) as transport:
            with self.assertRaises(RuntimeError):
                client.post('/repos/a/b/issues', {'title': 'oops'})
        self.assertEqual(transport.call_count, 1)

    def test_pagination_detects_loop(self):
        client = m.GitHub('token', pause=0)
        url = 'https://api.github.com/repos/x/y/issues?page=1'
        with patch.object(client, 'request', return_value=([], {'Link': f'<{url}>; rel="next"'})):
            with self.assertRaisesRegex(ValueError, 'loop'):
                list(client.pages('/repos/x/y/issues?page=1'))

    def test_pagination_rejects_external_host(self):
        client = m.GitHub('token', pause=0)
        with patch.object(client, 'request', return_value=([], {'Link': '<https://attacker.com/evil>; rel="next"'})):
            with self.assertRaisesRegex(ValueError, 'host'):
                list(client.pages('/repos/x/y/issues'))

    def test_pagination_follows_valid_next_page(self):
        client = m.GitHub('token', pause=0)
        first = '/repos/x/y/issues?page=1'
        next_url = 'https://api.github.com/repos/x/y/issues?page=2'
        with patch.object(client, 'request', side_effect=[([{'number': 1}], {'Link': f'<{next_url}>; rel="next"'}),
                                                            ([{'number': 2}], {})]):
            self.assertEqual([x['number'] for x in client.pages(first)], [1, 2])


class GitIntegrationTests(unittest.TestCase):
    """Run real git operations against temporary local bare repositories, no network."""

    def test_backport_open_pr_creates_draft_and_branch_with_patch(self):
        import subprocess
        from pathlib import Path

        def run(*argv, cwd=None):
            return subprocess.run(["git", *map(str, argv)], cwd=cwd, check=True,
                                  stdout=subprocess.PIPE, stderr=subprocess.PIPE).stdout.decode().strip()

        with tempfile.TemporaryDirectory() as root:
            base = Path(root)
            upstream = base / "godotengine" / "godot.git"
            fork = base / "demoh2019" / "Cgame.git"
            upstream.parent.mkdir()
            fork.parent.mkdir()
            run("init", "--bare", upstream)
            run("init", "--bare", fork)
            seed = base / "seed"
            run("init", "-b", "master", seed)
            run("config", "user.email", "test@example.org", cwd=seed)
            run("config", "user.name", "Git Test", cwd=seed)
            (seed / "engine.txt").write_text("base\n", encoding="utf-8")
            run("add", "engine.txt", cwd=seed)
            run("commit", "-m", "Seed", cwd=seed)
            run("remote", "add", "upstream", upstream, cwd=seed)
            run("remote", "add", "origin", fork, cwd=seed)
            run("push", "upstream", "master", cwd=seed)
            run("push", "origin", "master", cwd=seed)
            run("switch", "-c", "develop", cwd=seed)
            (seed / "fork-only.txt").write_text("fork enhancement\n", encoding="utf-8")
            run("add", "fork-only.txt", cwd=seed)
            run("commit", "-m", "Fork enhancement", cwd=seed)
            run("push", "origin", "develop", cwd=seed)
            run("switch", "master", cwd=seed)
            run("switch", "-c", "feature", cwd=seed)
            (seed / "engine.txt").write_text("base\nfix\n", encoding="utf-8")
            run("add", "engine.txt", cwd=seed)
            run("commit", "-m", "Fix bug", cwd=seed)
            run("push", "upstream", "HEAD:refs/pull/987/head", cwd=seed)
            checkout = base / "clone"
            run("clone", "-b", "master", fork, checkout)
            run("remote", "add", "upstream", upstream, cwd=checkout)
            api = FakeAPI()
            outcome = m.backport_pr(api, pr(987), str(checkout))
            self.assertIn("https://github.com", outcome)
            self.assertEqual(len(api.posts), 1)
            path, metadata = api.posts[0]
            self.assertEqual(path, f"/repos/{m.TARGET}/pulls")
            self.assertTrue(metadata['draft'])
            self.assertEqual(metadata['head'], 'upstream-pr-987')
            self.assertEqual(metadata['base'], 'develop')
            self.assertIn('original', metadata['body'].lower() if 'original' in metadata['body'].lower() else metadata['body'])
            inspect = base / "inspect"
            run("clone", "-b", "upstream-pr-987", fork, inspect)
            self.assertEqual((inspect / "engine.txt").read_text(encoding="utf-8"), "base\nfix\n")
            self.assertEqual((inspect / "fork-only.txt").read_text(encoding="utf-8"), "fork enhancement\n")

    def test_backport_rejects_non_repo_path(self):
        import subprocess
        with tempfile.TemporaryDirectory() as root:
            with self.assertRaises(subprocess.CalledProcessError):
                m.backport_pr(FakeAPI(), pr(987), root)


if __name__ == '__main__':
    unittest.main()
