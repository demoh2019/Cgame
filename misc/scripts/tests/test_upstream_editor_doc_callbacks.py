"""Source contracts for safe deferred documentation callbacks (Godot #123658).

Source validation supplements, but cannot replace, real editor shutdown tests.
"""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[3]


def fragment(text, first, last):
    start = text.index(first)
    stop = text.index(last, start + len(first))
    return text[start:stop]


class DeferredDocsTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.cpp = (ROOT / 'editor/doc/editor_help.cpp').read_text(encoding='utf-8')
        cls.header = (ROOT / 'editor/doc/editor_help.h').read_text(encoding='utf-8')
        cls.load = fragment(cls.cpp, 'void EditorHelp::_load_doc_thread(', 'void EditorHelp::_gen_doc_thread(')
        cls.regen = fragment(cls.cpp, 'void EditorHelp::_gen_doc_thread(', 'void EditorHelp::_gen_extensions_docs(')
        cls.corrupt = fragment(cls.cpp, 'void EditorHelp::_load_script_doc_cache_thread(', '// Helper method to deal with')
        cls.generate = fragment(cls.cpp, 'void EditorHelp::generate_doc(', 'void EditorHelp::_notification(')
        cls.cleanup = fragment(cls.cpp, 'void EditorHelp::cleanup_doc()', 'Vector<Pair<String, int>> EditorHelp::get_sections()')

    def test_owner_inherits_object(self):
        self.assertIn('class EditorHelpDocOwner : public Object', self.header)

    def test_static_owner_pointer(self):
        self.assertIn('inline static EditorHelpDocOwner *doc_owner = nullptr;', self.header)

    def test_owner_forwards_generation(self):
        self.assertIn('EditorHelp::generate_doc(p_use_cache, p_use_script_cache)', self.header)

    def test_owner_forwards_extensions(self):
        self.assertIn('EditorHelp::_gen_extensions_docs()', self.header)

    def test_owner_forwards_script_cache(self):
        self.assertIn('EditorHelp::load_script_doc_cache()', self.header)

    def test_owner_forwards_regeneration(self):
        self.assertIn('EditorHelp::regenerate_script_doc_cache()', self.header)

    def test_load_worker_script_cache_binding(self):
        self.assertIn('callable_mp(doc_owner, &EditorHelpDocOwner::load_script_doc_cache).call_deferred();', self.load)

    def test_load_worker_extensions_binding(self):
        self.assertIn('callable_mp(doc_owner, &EditorHelpDocOwner::_gen_extensions_docs).call_deferred();', self.load)

    def test_load_worker_regeneration_binding(self):
        self.assertIn('callable_mp(doc_owner, &EditorHelpDocOwner::generate_doc).call_deferred(false, use_script_cache);', self.load)

    def test_generate_worker_script_cache_binding(self):
        self.assertIn('callable_mp(doc_owner, &EditorHelpDocOwner::load_script_doc_cache).call_deferred();', self.regen)

    def test_corrupt_cache_regeneration_binding(self):
        self.assertIn('callable_mp(doc_owner, &EditorHelpDocOwner::regenerate_script_doc_cache).call_deferred();', self.corrupt)

    def test_no_legacy_static_deferred_docs(self):
        for part in (self.load, self.regen, self.corrupt):
            with self.subTest(part=part[:32]):
                self.assertNotIn('callable_mp_static(&EditorHelp::', part)
                self.assertNotIn('callable_mp_static(EditorHelp::regenerate_script_doc_cache)', part)

    def test_owner_created_before_worker(self):
        self.assertIn('if (!doc_owner)', self.generate)
        self.assertLess(self.generate.index('doc_owner = memnew(EditorHelpDocOwner);'), self.generate.index('worker_thread.start('))

    def test_doc_allocated_as_before(self):
        self.assertIn('doc = memnew(DocTools);', self.generate)

    def test_cleanup_waits_before_deleting_owner(self):
        self.assertLess(self.cleanup.index('_wait_for_thread();'), self.cleanup.index('memdelete(doc_owner);'))

    def test_owner_freed_before_doc_data(self):
        self.assertLess(self.cleanup.index('memdelete(doc_owner);'), self.cleanup.index('memdelete(doc);'))

    def test_owner_pointer_reset(self):
        self.assertIn('memdelete(doc_owner);\n\tdoc_owner = nullptr;', self.cleanup)

    def test_doc_pointer_reset(self):
        self.assertIn('memdelete(doc);\n\tdoc = nullptr;', self.cleanup)

    def test_exactly_five_object_bound_callbacks(self):
        self.assertEqual(self.cpp.count('callable_mp(doc_owner, &EditorHelpDocOwner::'), 5)

    def test_corruption_recovery_still_deletes_cache(self):
        self.assertIn('_delete_script_doc_cache();', self.corrupt)
        self.assertLess(self.corrupt.index('_delete_script_doc_cache();'), self.corrupt.index('EditorHelpDocOwner::regenerate_script_doc_cache'))


if __name__ == '__main__':
    unittest.main()
