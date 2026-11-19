"""Regressions for PCK directory index single-lookup traversal."""

from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[3]
SOURCE = ROOT / "core/io/file_access_pack.cpp"
NATIVE = ROOT / "tests/core/io/test_pck_packer.cpp"


class PackedDataIndexContracts(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.source = SOURCE.read_text(encoding="utf-8")
        cls.native = NATIVE.read_text(encoding="utf-8")

    def test_add_path_existing_directories_use_one_lookup(self):
        path = self.source.split("void PackedData::add_path(", 1)[1].split("void PackedData::remove_path(", 1)[0]
        self.assertEqual(path.count("cd->subdirs.find(ds[j])"), 1)
        self.assertNotIn("cd->subdirs.has(ds[j])", path)
        self.assertIn("cd = child->value;", path)
        self.assertIn("cd->subdirs[pd->name] = pd;", path)

    def test_remove_path_uses_one_lookup(self):
        path = self.source.split("void PackedData::remove_path(", 1)[1].split("void PackedData::add_pack_source(", 1)[0]
        self.assertEqual(path.count("cd->subdirs.find(ds[j])"), 1)
        self.assertNotIn("cd->subdirs.has(ds[j])", path)
        self.assertIn("if (!child)", path)
        self.assertIn("cd = child->value;", path)

    def test_native_index_regressions(self):
        self.assertIn("PackedData index shares directories", self.native)
        self.assertIn("PackedData index of many files", self.native)
        self.assertIn("packed->get_file_paths().size() == previous_count + 512", self.native)
        self.assertIn("packed->get_file_paths().size() == previous_count + 256", self.native)
        self.assertIn("PackedData::get_singleton()", self.native)
        self.assertIn("const uint32_t previous_count", self.native)
        self.assertIn("packed->get_file_paths().size() == previous_count", self.native)
        self.assertNotIn("PackedData packed;", self.native)


if __name__ == "__main__":
    unittest.main()
