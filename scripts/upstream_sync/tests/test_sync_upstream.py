import sys
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from sync_upstream import GitHub, Migrator, body_for_item, existing_upstream_pr, parse_args, parse_origin, ref_marker


class FakeGitHub:
    def __init__(self, items=(), existing=(), prs=(), detail=None, has_base=True):
        self.items, self.existing, self.prs = list(items), list(existing), list(prs)
        self.detail, self.has_base = detail, has_base
        self.created, self.patched, self.posted_prs = [], [], []

    def pages(self, path, *, start_page=1):
        if '/issues?' in path and 'godotengine/godot' in path:
            yield self.items
        elif '/issues?' in path:
            yield self.existing
        else:
            yield self.prs

    def get(self, path):
        if '/branches/' in path:
            if not self.has_base:
                from sync_upstream import APIError
                raise APIError('not found')
            return {'name':'master'}
        return self.detail

    def post(self, path, payload):
        if path.endswith('/issues'):
            self.created.append(payload)
            return {'number':len(self.created) + 1000}
        self.posted_prs.append(payload)
        return {'html_url':'https://github.com/demoh2019/godot/pull/42'}

    def patch(self, path, payload):
        self.patched.append((path,payload))


def issue(number, state='open', pr=False):
    item = {'number':number, 'title':f'Title {number}', 'body':'Details', 'state':state,
            'html_url':f'https://github.com/godotengine/godot/{"pull" if pr else "issues"}/{number}',
            'user':{'login':'upstream_author'}}
    if pr:
        item['pull_request'] = {'url':'https://api.github.com/example'}
    return item


def runner(cmd, **kwargs):
    class R:
        returncode = 0
        stderr = ''
    return R()


class MirrorTests(unittest.TestCase):
    def make(self, api, **kwargs):
        opts={'apply':True,'limit':0,'kind':'all','state':'all','start_page':1,'sleep_seconds':0,'git_runner':runner}
        return Migrator(api,'godotengine/godot','demoh2019/godot',**(opts | kwargs))

    def test_marker_roundtrip(self):
        x = ref_marker('godotengine/godot','issues',123)
        self.assertEqual(parse_origin(x),('godotengine/godot','issues',123))
        self.assertIsNone(parse_origin('arbitrary markdown'))

    def test_attribution_and_body(self):
        s = body_for_item(issue(10),'godotengine/godot','issues')
        self.assertIn('Original author: @upstream_author',s)
        self.assertIn('Details',s)
        self.assertIn('godotengine/godot/issues/10',s)

    def test_import_open_and_closed_issue(self):
        api=FakeGitHub([issue(10),issue(11,'closed')])
        m=self.make(api,kind='issues');m.run()
        self.assertEqual(m.done,2)
        self.assertEqual(len(api.created),2)
        self.assertEqual(len(api.patched),1)
        self.assertEqual(api.patched[0][1]['state'],'closed')

    def test_deduplicate_by_marker(self):
        marker=ref_marker('godotengine/godot','issues',10)
        api=FakeGitHub([issue(10)],existing=[{'body':marker}])
        m=self.make(api,kind='issues');m.run()
        self.assertEqual(m.done,0)
        self.assertEqual(m.skipped,1)

    def test_dry_run_never_writes(self):
        api=FakeGitHub([issue(10),issue(12,'closed')])
        m=self.make(api,apply=False,kind='issues');m.run()
        self.assertEqual(m.done,2)
        self.assertEqual(api.created,[])
        self.assertEqual(api.patched,[])

    def test_skip_already_ported_pr_without_marker(self):
        old={'title':'Backport upstream #99 to fork','body':'https://github.com/godotengine/godot/pull/99'}
        api=FakeGitHub([issue(99,pr=True)],prs=[old])
        m=self.make(api,kind='prs');m.run()
        self.assertEqual(m.skipped,1)
        self.assertEqual(api.posted_prs,[])

    def test_open_pr_fetches_git_head_and_creates_draft(self):
        api=FakeGitHub([issue(99,pr=True)],detail={'base':{'ref':'master'}})
        m=self.make(api,kind='prs');m.run()
        self.assertEqual(len(api.posted_prs),1)
        self.assertTrue(api.posted_prs[0]['draft'])
        self.assertEqual(api.posted_prs[0]['head'],'upstream-port/pr-99')
        self.assertEqual(m.done,1)

    def test_closed_pr_archived_as_issue(self):
        api=FakeGitHub([issue(100,pr=True,state='closed')])
        m=self.make(api,kind='prs');m.run()
        self.assertIn('archive',api.created[0]['title'])
        self.assertEqual(api.patched[0][1]['state'],'closed')

    def test_missing_stable_base_never_retargets_to_master(self):
        api=FakeGitHub([issue(103,pr=True)],detail={'base':{'ref':'3.x'}},has_base=False)
        m=self.make(api,kind='prs');m.run()
        self.assertEqual(api.posted_prs,[])
        self.assertEqual(m.skipped,1)

    def test_limit_is_number_of_new_records(self):
        api=FakeGitHub([issue(1),issue(2),issue(3)])
        m=self.make(api,kind='issues',limit=2);m.run()
        self.assertEqual(len(api.created),2)

    def test_arguments_sanitize_invalid_repo(self):
        with self.assertRaises(SystemExit):
            parse_args(['--target','../../bad'])
        with self.assertRaises(SystemExit):
            parse_args(['--start-page','0'])

    def test_legacy_pr_match_is_not_bare_issue_reference(self):
        self.assertEqual(existing_upstream_pr('Backport upstream #88','', 'godotengine/godot'),88)
        self.assertIsNone(existing_upstream_pr('Fix #88','Closes #88','godotengine/godot'))


if __name__=='__main__':
    unittest.main()