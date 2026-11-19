"""Source-level invariants for upstream Godot #121025 token lifetime fix.

Native threaded resource tests run in the separate engine CI job.
These contracts protect against reintroducing leaks via unchecked unreference().
"""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[3]
SOURCE = ROOT / "core" / "io" / "resource_loader.cpp"
NATIVE = ROOT / "tests" / "core" / "io" / "test_resource.cpp"


def function_body(text: str, marker: str, next_marker: str) -> str:
    start = text.index(marker)
    end = text.index(next_marker, start + len(marker))
    return text[start:end]


class ResourceLoaderTokenLifetimeTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.source = SOURCE.read_text(encoding="utf-8")
        cls.native = NATIVE.read_text(encoding="utf-8")
        cls.worker = function_body(
            cls.source, "void ResourceLoader::_run_load_task(",
            "String ResourceLoader::_validate_local_path(")
        cls.complete = function_body(
            cls.source, "Ref<Resource> ResourceLoader::_load_complete_inner(",
            "bool ResourceLoader::_ensure_load_progress()")
        cls.clear = function_body(
            cls.source, "void ResourceLoader::clear_thread_load_tasks(",
            "void ResourceLoader::set_load_callback(")

    def test_worker_no_longer_ignores_token_destruction(self):
        self.assertNotIn("load_task.load_token->unreference();", self.worker)
        self.assertEqual(self.worker.count("if (token->unreference()) {"), 2)
        self.assertEqual(self.worker.count("memdelete(token);"), 2)

    def test_waiter_release_occurs_after_unlock(self):
        section = self.worker[self.worker.index("if (status != THREAD_LOAD_IN_PROGRESS) {"):]
        self.assertLess(section.index("thread_load_mutex.unlock();"),
                        section.index("if (token->unreference()) {"))
        self.assertLess(section.index("memdelete(token);"), section.index("return;"))

    def test_worker_finishes_using_task_before_releasing_token(self):
        self.assertLess(self.worker.index("curr_load_task = curr_load_task_backup;"),
                        self.worker.rindex("if (token->unreference()) {"))

    def test_nested_wait_keeps_own_guard_reference(self):
        self.assertIn("LoadToken *wtp_guard_token = nullptr;", self.complete)
        self.assertIn("wtp_guard_token->reference();", self.complete)
        self.assertLess(self.complete.index("wtp_guard_token->reference();"),
                        self.complete.index("_run_load_task(&load_task);"))
        self.assertIn("if (wtp_guard_token && wtp_guard_token->unreference()) {", self.complete)
        self.assertIn("memdelete(wtp_guard_token);", self.complete)

    def test_user_tokens_are_destroyed_on_clear(self):
        self.assertIn("if (user_token->unreference()) {", self.clear)
        self.assertIn("memdelete(user_token);", self.clear)

    def test_native_stress_covers_both_subthread_modes(self):
        start = self.native.index('TEST_CASE("[Resource] Threaded nested loads release task tokens")')
        block = self.native[start:]
        for fragment in (
            "for (bool sub_threads : { false, true })",
            "for (int iteration = 0; iteration < 12; ++iteration)",
            "ResourceLoader::load_threaded_request(",
            "ResourceLoader::load_threaded_get(",
            "ResourceLoader::CACHE_MODE_IGNORE",
            'get_meta("external_resource")',
        ):
            with self.subTest(fragment=fragment):
                self.assertIn(fragment, block)


if __name__ == "__main__":
    unittest.main()
