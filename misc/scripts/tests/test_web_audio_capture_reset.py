#!/usr/bin/env python3
"""Compile the real Web audio input_stop() against mock buffer/lock operations.

Regression for upstream https://github.com/godotengine/godot/pull/125546.
"""

import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[3]
SOURCE = ROOT / "platform/web/audio_driver_web.cpp"


def extract_stop():
    text = SOURCE.read_text(encoding="utf-8")
    match = re.search(r"Error\s+AudioDriverWeb::input_stop\(\)\s*\{", text)
    if not match:
        raise AssertionError("AudioDriverWeb::input_stop() not found")
    end = text.find("\n}", match.start())
    if end < 0:
        raise AssertionError("input_stop() closing brace not found")
    return text[match.start() : end + 2]


HARNESS = r"""
#include <cassert>
#include <string>
#include <vector>

enum Error { OK = 0, FAILED = 1 };

std::vector<std::string> events;
void godot_audio_input_stop() { events.push_back("stop"); }

struct MockBuffer {
    int bytes = 0;
    void clear() {
        events.push_back("clear");
        bytes = 0;
    }
};

struct AudioDriverWeb {
    int input_position = 0;
    int input_size = 0;
    MockBuffer input_buffer;
    int locks = 0;
    int unlocks = 0;
    void lock() { events.push_back("lock"); ++locks; }
    void unlock() {
        events.push_back("unlock");
        ++unlocks;
        assert(input_position == 0);
        assert(input_size == 0);
        assert(input_buffer.bytes == 0);
    }
    Error input_stop();
};

__METHOD__

int main() {
    for (int index = 0; index < 5; ++index) {
        AudioDriverWeb driver;
        driver.input_position = index * 7 + 1;
        driver.input_size = index * 11 + 2;
        driver.input_buffer.bytes = index + 10;
        events.clear();
        assert(driver.input_stop() == OK);
        assert(driver.input_position == 0);
        assert(driver.input_size == 0);
        assert(driver.input_buffer.bytes == 0);
        assert(driver.locks == 1 && driver.unlocks == 1);
        assert(events.size() == 4);
        assert(events[0] == "stop");
        assert(events[1] == "lock");
        assert(events[2] == "clear");
        assert(events[3] == "unlock");

        // Repeated stop calls must leave a clean capture state.
        events.clear();
        assert(driver.input_stop() == OK);
        assert(driver.input_position == 0 && driver.input_size == 0);
        assert(driver.locks == 2 && driver.unlocks == 2);
        assert(events.size() == 4);
    }
}
"""


class AudioCaptureResetTests(unittest.TestCase):
    def test_state_resets_inside_lock_before_unlock(self):
        method = extract_stop()
        call = method.index("godot_audio_input_stop()")
        lock = method.index("lock();")
        cleared = method.index("input_buffer.clear();")
        position = method.index("input_position = 0;")
        size = method.index("input_size = 0;")
        unlock = method.index("unlock();")
        self.assertLess(call, lock)
        self.assertLess(lock, cleared)
        self.assertLess(cleared, position)
        self.assertLess(position, size)
        self.assertLess(size, unlock)

    def test_actual_cpp_method_resets_stale_capture_state(self):
        compiler = os.environ.get("CXX", "c++")
        if not shutil.which(compiler):
            self.skipTest(f"no compiler: {compiler}")
        code = HARNESS.replace("__METHOD__", extract_stop())
        with tempfile.TemporaryDirectory(prefix="web-audio-reset-") as tmpdir:
            exe = Path(tmpdir) / "audio_reset"
            build = subprocess.run(
                [compiler, "-std=c++17", "-Wall", "-Wextra", "-Werror",
                 "-x", "c++", "-", "-o", str(exe)],
                input=code, text=True, capture_output=True, check=False,
            )
            self.assertEqual(build.returncode, 0, build.stderr)
            run = subprocess.run([str(exe)], text=True, capture_output=True, check=False)
            self.assertEqual(run.returncode, 0, run.stderr)


if __name__ == "__main__":
    unittest.main()
