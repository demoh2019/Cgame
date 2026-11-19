"""Teardown regression contracts for upstream Godot PR #125566.

These checks verify source ordering and guards, not runtime concurrency or
correctness of a compiled Cgame editor. Native editor CI remains mandatory.
"""

from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[3]


def read(relative):
    return (ROOT / relative).read_text(encoding="utf-8")


def extract(src, begin, end):
    if src.count(begin) != 1:
        raise AssertionError("Missing or duplicate function: " + begin)
    return src.split(begin, 1)[1].split(end, 1)[0]


class EditorDocShutdownRegression(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.header = read("editor/doc/editor_help.h")
        cpp = read("editor/doc/editor_help.cpp")
        cls.generate = extract(cpp, "void EditorHelp::generate_doc(", "void EditorHelp::cleanup_doc(")
        cls.cleanup = extract(cpp, "void EditorHelp::cleanup_doc() {", "Vector<Pair<String, int>> EditorHelp::get_sections()")
        cls.load = extract(cpp, "void EditorHelp::load_script_doc_cache() {", "void EditorHelp::")
        cls.extensions = extract(cpp, "void EditorHelp::_gen_extensions_docs() {", "static void _load_script_doc_cache(")
        cls.regenerate = extract(cpp, "void EditorHelp::regenerate_script_doc_cache() {", "void EditorHelp::")
        cls.editor = extract(read("editor/editor_node.cpp"),
                             "bool EditorNode::is_cmdline_mode() {", "void EditorNode::cleanup() {")
        cls.file_system = extract(read("editor/file_system/editor_file_system.cpp"),
                                  "EditorFileSystem::~EditorFileSystem() {", "}")
        cls.file_system += "}"  # Include the final closure for completeness.

    def test_header_has_atomic_shutdown_latch(self):
        self.assertIn("inline static SafeFlag _doc_torn_down = SafeFlag(false);", self.header)

    def test_doc_generation_guarded(self):
        self.assertIn("if (_doc_torn_down.is_set())", self.generate)
        self.assertLess(self.generate.index("_doc_torn_down.is_set()"),
                        self.generate.index("doc_generation_count++"))

    def test_script_cache_load_guarded(self):
        self.assertTrue(self.load.lstrip().startswith("if (_doc_torn_down.is_set())"))

    def test_script_cache_regeneration_guarded(self):
        self.assertTrue(self.regenerate.lstrip().startswith("if (_doc_torn_down.is_set())"))

    def test_extension_docs_guarded(self):
        self.assertTrue(self.extensions.lstrip().startswith("if (_doc_torn_down.is_set())"))

    def test_doc_shutdown_latched_first(self):
        self.assertTrue(self.cleanup.lstrip().startswith("_doc_torn_down.set();"))

    def test_thread_wait_precedes_document_free(self):
        self.assertLess(self.cleanup.index("_wait_for_thread();"), self.cleanup.index("memdelete(doc);"))

    def test_shutdown_latch_before_thread_wait(self):
        self.assertLess(self.cleanup.index("_doc_torn_down.set();"), self.cleanup.index("_wait_for_thread();"))

    def test_document_pointer_cleared_after_delete(self):
        self.assertLess(self.cleanup.index("memdelete(doc);"), self.cleanup.index("doc = nullptr;"))

    def test_cmdline_fallback_when_editor_is_missing(self):
        self.assertIn("return !singleton || singleton->cmdline_mode;", self.editor)

    def test_cmdline_mode_no_longer_returns_false_for_missing_editor(self):
        self.assertNotIn("ERR_FAIL_NULL_V(singleton, false);", self.editor)

    def test_file_system_singleton_is_reset_after_teardown(self):
        self.assertIn("ResourceSaver::set_get_resource_id_for_path(nullptr);", self.file_system)
        self.assertIn("singleton = nullptr;", self.file_system)
        self.assertLess(
            self.file_system.index("ResourceSaver::set_get_resource_id_for_path(nullptr);"),
            self.file_system.index("singleton = nullptr;"),
        )


if __name__ == "__main__":
    unittest.main()
