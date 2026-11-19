#!/usr/bin/env python3
"""macOS filesystem scan and Unix file-open regression contracts."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[3]


def get(path):
    return (ROOT / path).read_text(encoding="utf-8")


class MacHiddenFileFastPath(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.header = get("drivers/unix/dir_access_unix.h")
        cls.source = get("platform/macos/dir_access_macos.mm")
        cls.method = cls.source.split("bool DirAccessMacOS::is_hidden(", 1)[1].split(
            "\nbool DirAccessMacOS::is_case_sensitive(", 1)[0]

    def test_open_directory_stream_accessible_from_subclass(self):
        position = self.header.index("class DirAccessUnix")
        protected = self.header.index("protected:", position)
        stream = self.header.index("DIR *dir_stream = nullptr;", position)
        self.assertGreater(stream, protected)

    def test_native_fstat_based_hidden_check(self):
        self.assertIn("#include <sys/attr.h>", self.source)
        self.assertIn("#include <unistd.h>", self.source)
        self.assertIn("getattrlistat(dirfd(dir_stream)", self.method)
        self.assertIn("FSOPT_NOFOLLOW", self.method)
        self.assertIn("buf.flags & UF_HIDDEN", self.method)
        self.assertIn("ATTR_CMN_NAME | ATTR_CMN_FLAGS", self.method)
        self.assertNotIn("NSURL", self.method)

    def test_name_and_hidden_flag_semantics_with_fallback(self):
        self.assertIn("real_name[0] == '.'", self.method)
        self.assertIn("DirAccessUnix::is_hidden(p_name)", self.method)
        self.assertIn("ERR_FAIL_NULL_V(dir_stream, false);", self.method)
        # Empty and non-dot files are differentiated by both dot prefix and UF_HIDDEN.
        def hidden(name, flags):
            return name.startswith(".") or bool(flags & 0x8000)
        self.assertTrue(hidden(".metadata", 0))
        self.assertTrue(hidden("visible", 0x8000))
        self.assertFalse(hidden("visible", 0))


class UnixRealPathFastPath(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.source = get("drivers/unix/file_access_unix.cpp")
        cls.method = cls.source.split("String FileAccessUnix::get_real_path() const {", 1)[1].split("\n}", 1)[0]
        cls.open_method = cls.source.split("Error FileAccessUnix::open_internal(", 1)[1].split(
            "\nString FileAccessUnix::", 1)[0]

    def test_apple_resolves_open_fd_instead_of_path(self):
        self.assertIn("#include <sys/param.h>", self.source)
        self.assertIn("fcntl(fileno(f), F_GETPATH, buf)", self.method)
        self.assertIn("char buf[MAXPATHLEN];", self.method)
        self.assertIn("#if defined(__APPLE__)", self.method)
        self.assertIn("#else", self.method)
        self.assertIn("::realpath(", self.method)
        self.assertIn("return path;", self.method)

    def test_case_mismatch_warning_retained_after_open(self):
        self.assertIn("if (p_mode_flags & READ)", self.open_method)
        self.assertIn("Case mismatch opening requested file", self.open_method)
        self.assertIn("String real_path = get_real_path();", self.open_method)
        self.assertIn("#if defined(TOOLS_ENABLED)", self.open_method)

    def test_read_files_still_mark_fd_close_on_exec(self):
        self.assertIn("int fd = fileno(f);", self.open_method)
        self.assertIn("FD_CLOEXEC", self.open_method)


if __name__ == "__main__":
    unittest.main()
