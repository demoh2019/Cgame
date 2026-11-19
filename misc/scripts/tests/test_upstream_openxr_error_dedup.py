"""Regression tests for upstream Godot #125557 OpenXR frame-error throttling.

Source contracts check all XR call sites. The behavioral test compiles and runs
the actual production C++ helper in isolation with minimal logging stubs.
This does not require an OpenXR runtime or a full Godot build.
"""

from pathlib import Path
import os
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[3]
CPP = ROOT / "modules/openxr/openxr_api.cpp"
HEADER = ROOT / "modules/openxr/openxr_api.h"


def _function(source, signature):
    start = source.index(signature)
    opening = source.index("{", start)
    depth = 0
    for position in range(opening, len(source)):
        if source[position] == "{":
            depth += 1
        elif source[position] == "}":
            depth -= 1
            if depth == 0:
                return source[start:position + 1]
    raise AssertionError(f"Unclosed function: {signature}")


class OpenXRFrameErrorTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.cpp = CPP.read_text(encoding="utf-8")
        cls.header = HEADER.read_text(encoding="utf-8")
        cls.helper = _function(cls.cpp, "void OpenXRAPI::report_frame_loop_error(")

    def test_tracking_has_independent_wait_begin_and_end_states(self):
        self.assertIn("XrResult last_wait_frame_error = XR_SUCCESS;", self.header)
        self.assertIn("XrResult last_begin_frame_error = XR_SUCCESS;", self.header)
        self.assertIn("XrResult last_end_frame_error = XR_SUCCESS;", self.header)

    def test_begin_end_tracking_stays_in_render_state(self):
        state = self.header.split("struct RenderState {", 1)[1]
        self.assertIn("last_begin_frame_error", state)
        self.assertIn("last_end_frame_error", state)
        self.assertNotIn("last_wait_frame_error", state)

    def test_wait_frame_reports_by_result(self):
        self.assertIn(
            'report_frame_loop_error(last_wait_frame_error, result, "xrWaitFrame() was not successful");',
            self.cpp,
        )
        self.assertIn("last_wait_frame_error = XR_SUCCESS;", self.cpp)

    def test_begin_frame_reports_by_result(self):
        self.assertIn(
            'report_frame_loop_error(render_state.last_begin_frame_error, result, "failed to begin frame");',
            self.cpp,
        )
        self.assertIn("render_state.last_begin_frame_error = XR_SUCCESS;", self.cpp)

    def test_both_end_frame_paths_report_errors(self):
        self.assertIn(
            'report_frame_loop_error(render_state.last_end_frame_error, result, "failed to end frame");',
            self.cpp,
        )
        self.assertIn(
            'report_frame_loop_error(render_state.last_end_frame_error, result, '
            '"rendering skipped and failed to end frame");',
            self.cpp,
        )
        self.assertEqual(self.cpp.count("render_state.last_end_frame_error = XR_SUCCESS;"), 2)

    def test_logging_helper_has_verbose_repeat_and_normal_first_error(self):
        self.assertIn("if (p_result == r_last_error)", self.helper)
        self.assertIn("print_verbose(", self.helper)
        self.assertIn("print_error(", self.helper)
        self.assertIn("r_last_error = p_result;", self.helper)

    def test_no_old_per_frame_log_calls(self):
        for old_log in (
            'print_line("OpenXR: xrWaitFrame() was not successful',
            'print_line("OpenXR: failed to begin frame',
            'print_line("OpenXR: failed to end frame',
            'print_line("OpenXR: rendering skipped and failed to end frame',
        ):
            with self.subTest(old_log=old_log):
                self.assertNotIn(old_log, self.cpp)

    def test_actual_cpp_helper_deduplicates_and_recovers_after_success(self):
        compiler = shutil.which(os.environ.get("CXX", "c++"))
        if not compiler:
            self.skipTest("A C++ compiler is not available")

        # Compile the original function body verbatim with tiny substitutes for
        # Godot's string/error utilities, then exercise transitions.
        harness = """
#include <string>
#include <vector>
using XrResult = int;
constexpr XrResult XR_SUCCESS = 0;
static std::vector<std::string> errors, verbose;
template <typename... Args>
std::string vformat(const char *format, Args...) { return format; }
void print_error(const std::string &value) { errors.push_back(value); }
void print_verbose(const std::string &value) { verbose.push_back(value); }
class OpenXRAPI {
public:
    std::string get_error_string(XrResult) const { return "XR_ERROR"; }
    void report_frame_loop_error(XrResult &last, XrResult result, const char *message);
};
""" + self.helper + """
int main() {
    OpenXRAPI api;
    XrResult wait = XR_SUCCESS, begin = XR_SUCCESS;
    api.report_frame_loop_error(wait, -1, "xrWaitFrame");
    if (wait != -1 || errors.size() != 1 || !verbose.empty()) return 1;
    api.report_frame_loop_error(wait, -1, "xrWaitFrame");
    if (errors.size() != 1 || verbose.size() != 1) return 2;
    api.report_frame_loop_error(wait, -2, "xrWaitFrame");
    if (wait != -2 || errors.size() != 2) return 3;
    api.report_frame_loop_error(begin, -1, "xrBeginFrame");
    if (begin != -1 || errors.size() != 3) return 4;
    api.report_frame_loop_error(wait, -2, "xrWaitFrame");
    if (errors.size() != 3 || verbose.size() != 2) return 5;
    wait = XR_SUCCESS; // Success resets the per-call error slot.
    api.report_frame_loop_error(wait, -2, "xrWaitFrame");
    if (errors.size() != 4 || wait != -2) return 6;
    return 0;
}
"""
        with tempfile.TemporaryDirectory() as tmp:
            cpp = Path(tmp) / "openxr_error_test.cpp"
            executable = Path(tmp) / "openxr_error_test"
            cpp.write_text(harness, encoding="utf-8")
            build = subprocess.run(
                [compiler, "-std=c++17", "-Wall", "-Wextra", "-Werror", str(cpp), "-o", str(executable)],
                capture_output=True, text=True,
            )
            self.assertEqual(build.returncode, 0, build.stdout + build.stderr)
            run = subprocess.run([str(executable)], capture_output=True, text=True)
            self.assertEqual(run.returncode, 0, run.stdout + run.stderr)


if __name__ == "__main__":
    unittest.main()
