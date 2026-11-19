"""Source-contract guards for the FileAccessPackedByteArray fast path.

Native Godot C++ cases live in tests/core/io/test_file_access.cpp.
These guards also run without building the complete engine.
"""

from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[3]
SOURCE = ROOT / "core/io/file_access_packed_byte_array.cpp"
TESTS = ROOT / "tests/core/io/test_file_access.cpp"


class PackedByteArrayIOContracts(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.source = SOURCE.read_text(encoding="utf-8")
        cls.tests = TESTS.read_text(encoding="utf-8")

    def method(self, method_name):
        fragment = self.source.split("FileAccessPackedByteArray::" + method_name + "(", 1)[1]
        return fragment.split("\n}\n", 1)[0]

    def test_read_is_const_pointer_copy(self):
        body = self.method("get_buffer")
        self.assertIn("data.ptr() + pos", body)
        self.assertNotIn("data.ptrw()", body)
        self.assertIn("if (read > 0)", body)

    def test_bounds_saturate_instead_of_wrapping(self):
        for name in ("get_buffer", "store_buffer"):
            body = self.method(name)
            self.assertIn("pos < length ? length - pos : 0", body)
            self.assertNotIn("data.size() - pos", body)

    def test_write_only_detaches_cow_when_nonempty(self):
        body = self.method("store_buffer")
        self.assertIn("if (write > 0)", body)
        self.assertLess(body.index("if (write > 0)"), body.index("data.ptrw()"))

    def test_shrink_clamps_cursor_only_after_success(self):
        body = self.method("resize")
        self.assertIn("err == OK && pos > uint64_t(data.size())", body)
        self.assertIn("return err;", body)

    def test_native_regressions_present(self):
        self.assertIn("PackedByteArray shrink clamps cursor", self.tests)
        self.assertIn("PackedByteArray COW stays shared", self.tests)
        self.assertIn("PackedByteArray partial block I/O", self.tests)
        self.assertIn("PackedByteArray resize failure", self.tests)
        self.assertIn("PackedByteArray reads and writes never cross EOF", self.tests)


if __name__ == "__main__":
    unittest.main()
