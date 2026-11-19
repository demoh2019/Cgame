#!/usr/bin/env python3
"""Standalone compiled test of the actual ValuePtr implementation and Object signal migration."""
from __future__ import annotations
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[3]
HEADER = ROOT / "core/templates/value_ptr.h"


class SignalMetadataTests(unittest.TestCase):
    def test_method_info_is_optional_and_only_allocated_for_user_signals(self):
        header = (ROOT / "core/object/object.h").read_text()
        source = (ROOT / "core/object/object.cpp").read_text()
        self.assertIn("ValuePtr<MethodInfo> user_signal_info;", header)
        self.assertNotIn("MethodInfo user;", header)
        self.assertIn("signal_data.user_signal_info = ValuePtr<MethodInfo>::make(p_signal);", source)
        self.assertIn("return signal_map[p_name].user_signal_info;", source)
        self.assertIn("p_signals->push_back(*E.value.user_signal_info);", source)
        self.assertIn('#include "core/templates/value_ptr.h"', header)

    def test_actual_header_has_pointer_sized_storage(self):
        source = HEADER.read_text()
        self.assertIn("T *_ptr = nullptr;", source)
        self.assertIn("ValuePtr(const ValuePtr &p_ptr)", source)
        self.assertIn("ValuePtr(ValuePtr &&p_ptr)", source)
        self.assertIn("~ValuePtr()", source)
        self.assertIn("reset();", source)

    def test_compile_and_run_real_valueptr_header(self):
        compiler = shutil.which(os.environ.get("CXX", "c++"))
        if compiler is None:
            self.skipTest("C++ compiler unavailable")

        header = HEADER.read_text().replace("#pragma once", "").replace(
            '#include "core/os/memory.h"',
            '#define _FORCE_INLINE_ inline\n'
            '#define memnew(x) new x\n#define memdelete(x) delete x\n',
        )
        preface = "#include <cassert>\n#include <cstdint>\n#include <utility>\n"
        driver = r'''
struct Tracked {
    static int live;
    int value;
    Tracked(int p_value) : value(p_value) { ++live; }
    Tracked(const Tracked &p) : value(p.value) { ++live; }
    ~Tracked() { --live; }
    bool operator==(const Tracked &p) const { return value == p.value; }
};
int Tracked::live = 0;

int main() {
    static_assert(sizeof(ValuePtr<Tracked>) == sizeof(void *));
    ValuePtr<Tracked> absent;
    assert(!absent && absent == nullptr && nullptr == absent);
    for (int i = 0; i < 10000; ++i) {
        ValuePtr<Tracked> a = ValuePtr<Tracked>::make(i);
        assert(Tracked::live == 1);
        ValuePtr<Tracked> b(a);
        assert(Tracked::live == 2 && b.ptr() != a.ptr() && b == a);
        b->value++;
        assert(a->value == i && b->value == i + 1 && b != a);
        ValuePtr<Tracked> c;
        c = a;
        assert(Tracked::live == 3);
        c = std::move(b);
        assert(Tracked::live == 2 && !b && c->value == i + 1);
        c = c;
        c = std::move(c);
        assert(c && c->value == i + 1 && Tracked::live == 2);
        a = nullptr;
        assert(!a && Tracked::live == 1);
        c.reset();
        assert(Tracked::live == 0);
    }
    assert(Tracked::live == 0);
}
'''
        # The actual header is compiled, with only Godot's allocation macro shimmed.
        program = preface + header + driver
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "value_ptr.cpp"
            binary = Path(folder) / "value_ptr"
            path.write_text(program)
            for optimize in ("-O0", "-O2"):
                build = subprocess.run(
                    [compiler, "-std=c++17", optimize, "-Wall", "-Wextra", "-Werror",
                     str(path), "-o", str(binary)],
                    text=True, capture_output=True, timeout=60,
                )
                self.assertEqual(build.returncode, 0, build.stderr)
                result = subprocess.run([str(binary)], text=True, capture_output=True, timeout=30)
                self.assertEqual(result.returncode, 0, result.stderr)


if __name__ == "__main__":
    unittest.main()
