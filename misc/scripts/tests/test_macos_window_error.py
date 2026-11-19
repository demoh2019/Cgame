#!/usr/bin/env python3
"""Regression coverage for macOS main-window creation errors.

The failure conditional is extracted from the production Objective-C++ source
and compiled as C++ with a stub error-reporting macro. This tests error
propagation without requiring the macOS SDK on Linux CI.
"""

from __future__ import annotations

import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[3]
SOURCE = ROOT / "platform/macos/display_server_macos.mm"
HEADER = ROOT / "platform/macos/gl_manager_macos_legacy.h"
START = "\tif (main_window == DisplayServerEnums::INVALID_WINDOW_ID) {"


def get_failure_block() -> str:
    source = SOURCE.read_text(encoding="utf-8")
    _, _, after = source.partition(START)
    if not after:
        raise AssertionError("macOS main window failure guard not found")
    body, sep, _ = after.partition("\n\t}")
    if not sep:
        raise AssertionError("macOS main window failure guard not terminated")
    return START + body + sep


class TestMacOSWindowCreation(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.block = get_failure_block()

    def test_reports_cant_create_before_early_return(self) -> None:
        self.assertIn("r_error = ERR_CANT_CREATE;", self.block)
        self.assertIn('ERR_FAIL_MSG("Could not create main window.");', self.block)
        self.assertLess(self.block.index("r_error = ERR_CANT_CREATE;"), self.block.index("ERR_FAIL_MSG("))

    def test_error_guard_uses_invalid_window_sentinel(self) -> None:
        self.assertTrue(self.block.startswith(START))
        self.assertIn("DisplayServerEnums::INVALID_WINDOW_ID", self.block)

    def test_subsequent_window_initialization_not_removed(self) -> None:
        text = SOURCE.read_text(encoding="utf-8")
        self.assertIn("for (int i = 0; i < DisplayServerEnums::WINDOW_FLAG_MAX; i++)", text)
        self.assertIn("force_process_and_drop_events();", text)

    def test_clang_warning_state_balanced(self) -> None:
        header = HEADER.read_text(encoding="utf-8")
        self.assertEqual(header.count("GODOT_CLANG_WARNING_PUSH_AND_IGNORE("), 1)
        self.assertEqual(header.count("GODOT_CLANG_WARNING_POP"), 1)
        self.assertLess(header.index("GODOT_CLANG_WARNING_PUSH_AND_IGNORE("), header.index("GODOT_CLANG_WARNING_POP"))

    def test_extracted_cpp_failure_branch_behaves_correctly(self) -> None:
        candidate = os.environ.get("CXX", "c++")
        compiler = shutil.which(candidate)
        if not compiler:
            self.skipTest("C++ compiler not available")
        harness = r"""
#include <string>
struct DisplayServerEnums { static constexpr int INVALID_WINDOW_ID = -1; };
enum Error { OK, ERR_CANT_CREATE, ERR_ALREADY_FAILED };
std::string reported;
bool aborted = false;
#define ERR_FAIL_MSG(m) do { reported = (m); aborted = true; return; } while (false)
void construct_main_window(int main_window, Error &r_error) {
""" + self.block + r"""
}
int main() {
    Error error = OK;
    construct_main_window(-1, error);
    if (error != ERR_CANT_CREATE || !aborted || reported != "Could not create main window.") return 1;
    error = OK; aborted = false; reported.clear();
    construct_main_window(0, error);
    if (error != OK || aborted || !reported.empty()) return 2;
    error = ERR_ALREADY_FAILED; aborted = false; reported.clear();
    construct_main_window(42, error);
    if (error != ERR_ALREADY_FAILED || aborted || !reported.empty()) return 3;
    return 0;
}
"""
        with tempfile.TemporaryDirectory() as tmp:
            binary = str(Path(tmp) / "window_error_test")
            build = subprocess.run(
                [compiler, "-std=c++17", "-Wall", "-Wextra", "-Werror", "-x", "c++", "-", "-o", binary],
                input=harness,
                text=True,
                capture_output=True,
            )
            self.assertEqual(build.returncode, 0, build.stderr)
            run = subprocess.run([binary], capture_output=True, text=True)
            self.assertEqual(run.returncode, 0, run.stdout + run.stderr)


if __name__ == "__main__":
    unittest.main()
