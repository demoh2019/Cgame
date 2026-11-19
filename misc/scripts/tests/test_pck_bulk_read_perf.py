"""Contract tests for unsigned, bounded PCK bulk reads and actual byte counts."""

from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[3]
SOURCE = ROOT / "core/io/file_access_pack.cpp"
NATIVE = ROOT / "tests/core/io/test_pck_packer.cpp"


class PCKBulkReadContracts(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.source = SOURCE.read_text(encoding="utf-8")
        cls.native = NATIVE.read_text(encoding="utf-8")

    def body(self):
        return self.source.split("uint64_t FileAccessPack::get_buffer(", 1)[1].split(
            "void FileAccessPack::set_big_endian(", 1
        )[0]

    def test_unsigned_saturating_available(self):
        body = self.body()
        self.assertIn("const uint64_t available = pos < pf.size ? pf.size - pos : 0;", body)
        self.assertIn("MIN(p_length, available)", body)
        self.assertNotIn("int64_t to_read = p_length;", body)

    def test_advance_by_actual_bytes(self):
        body = self.body()
        self.assertIn("bytes_read = f->get_buffer(p_dst, to_read)", body)
        self.assertIn("pos += bytes_read;", body)
        self.assertNotIn("pos += to_read;", body)
        self.assertIn("bytes_read > to_read", body)

    def test_zero_length_request_is_side_effect_free(self):
        self.assertIn("if (eof || p_length == 0)", self.body())

    def test_short_read_marks_eof(self):
        self.assertIn("bytes_read < to_read", self.body())

    def test_native_cases_cover_large_and_short_reads(self):
        self.assertIn("FileAccessPack bounded bulk reads and unsigned lengths", self.native)
        self.assertIn("FileAccessPack reports physical short reads accurately", self.native)
        self.assertIn("UINT64_MAX", self.native)
        self.assertIn("metadata.size = 10", self.native)


if __name__ == "__main__":
    unittest.main()
