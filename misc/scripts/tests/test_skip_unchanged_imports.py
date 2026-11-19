"""Source-level reimport invalidation regression checks (Godot #119758)."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[3]
SOURCE = (ROOT / "editor/file_system/editor_file_system.cpp").read_text(encoding="utf-8")
HEADER = (ROOT / "editor/file_system/editor_file_system.h").read_text(encoding="utf-8")
NATIVE = (ROOT / "tests/editor/file_system/test_editor_file_system.cpp").read_text(encoding="utf-8")
SCU = (ROOT / "scu_builders.py").read_text(encoding="utf-8")


def method():
    i = SOURCE.index("bool EditorFileSystem::_test_for_reimport(")
    return SOURCE[i:SOURCE.index("bool EditorFileSystem::_update_scan_actions(", i)]


class SkipUnchangedReimports(unittest.TestCase):
    def test_new_api_reads_metadata_from_current_disk(self):
        self.assertIn("_test_for_reimport(const String &p_path)", HEADER)
        self.assertNotIn("p_expected_import_md5", HEADER)
        self.assertIn('cf->load(path + ".import")', method())

    def test_imported_dependency_only_reimports_on_change(self):
        self.assertIn("_can_import_file(dep) && _test_for_reimport(dependency_path)", SOURCE)

    def test_uid_paths_resolved_before_lookup(self):
        self.assertIn('path.begins_with("uid://")', method())
        self.assertIn("ResourceUID::uid_to_path(path)", method())

    def test_respects_keep_skip_and_invalid_imports(self):
        for fragment in ('get_value("remap", "valid", true)', 'importer_name == "keep"',
                         'importer_name == "skip"', 'load_err == ERR_FILE_CORRUPT'):
            with self.subTest(fragment=fragment):
                self.assertIn(fragment, method())

    def test_recognizes_missing_uid_and_target_paths(self):
        self.assertIn('has_section_key("remap", "uid")', method())
        self.assertIn('key.begins_with("path")', method())
        self.assertIn('has_section_key("deps", "files")', method())

    def test_source_and_destination_hashes_checked(self):
        self.assertIn('FileAccess::get_md5(path)', method())
        self.assertIn("FileAccess::get_multiple_md5(dest_files) != dest_md5", method())

    def test_importer_version_and_setting_changes_checked(self):
        self.assertIn('get_value("remap", "importer_version", 0)', method())
        self.assertIn("importer->are_import_settings_valid(path, meta)", method())

    def test_native_combinatorial_test_includes_all_broken_cases(self):
        self.assertGreaterEqual(NATIVE.count("TEST_CASE("), 6)
        for text in ("missing uid", "source md5 no longer matches",
                     "destination file missing", "importer version mismatch",
                     "import settings are invalid"):
            with self.subTest(text=text):
                self.assertIn(text, NATIVE)

    def test_scu_scans_editor_test_folders(self):
        self.assertIn('"/editor/file_system",', SCU)


if __name__ == "__main__":
    unittest.main()
