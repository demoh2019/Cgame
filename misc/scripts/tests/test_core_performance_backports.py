#!/usr/bin/env python3
"""Standalone C++ behavioral checks for Godot performance backports.

Compiles real Array::append_array() and SpinLock implementations from the
repository against minimal test doubles. Complements native doctests but does
not replace full Godot builds, platform coverage, or real-world benchmarks.
"""
from __future__ import annotations

import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def extract_function(source: str, signature: str) -> str:
    start = source.index(signature)
    opening = source.index("{", start)
    braces = 0
    for i in range(opening, len(source)):
        if source[i] == "{":
            braces += 1
        elif source[i] == "}":
            braces -= 1
            if braces == 0:
                return source[start : i + 1]
    raise AssertionError("Unbalanced C++ function: " + signature)


def compile_and_run(test: unittest.TestCase, code: str) -> str:
    cxx = shutil.which(os.environ.get("CXX", "c++"))
    if not cxx:
        test.skipTest("No C++ compiler installed")
    with tempfile.TemporaryDirectory() as directory:
        src, binary = Path(directory) / "test.cpp", Path(directory) / "test"
        src.write_text(code, encoding="utf-8")
        result = subprocess.run(
            [cxx, "-std=c++17", "-pthread", "-O2", "-Wall", "-Wextra",
             "-Werror", str(src), "-o", str(binary)],
            capture_output=True, text=True, timeout=45, check=False,
        )
        test.assertEqual(result.returncode, 0, result.stderr)
        run = subprocess.run([str(binary)], capture_output=True, text=True,
                             timeout=20, check=False)
        test.assertEqual(run.returncode, 0, run.stderr)
        return run.stdout


class TypedArrayAppendRegression(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.method = extract_function(
            read("core/variant/array.cpp"), "void Array::append_array(const Array &p_array)"
        )

    def test_fast_path_requires_no_conversion_or_temp_buffer(self):
        method = self.method
        self.assertIn("if (i == count)", method)
        self.assertIn("_p->array.append_array(source);", method)
        self.assertIn("write[i] = std::move(tmp);", method)
        self.assertLess(method.index("if (i == count)"),
                        method.index("Vector<Variant> validated_array;"))
        self.assertIn("const Vector<Variant> source = p_array._p->array;", method)

    def test_compile_actual_array_method_and_verify_both_paths(self):
        setup = r'''
#include <cassert>
#include <memory>
#include <string>
#include <utility>
#include <vector>
static int temporary_resizes = 0;
static int errors = 0;
struct Variant {
    enum Type { NIL, INT, FLOAT, STRING } type = NIL;
    double number = 0;
    std::string text;
    Variant() = default;
    explicit Variant(int v) : type(INT), number(v) {}
    explicit Variant(double v) : type(FLOAT), number(v) {}
    explicit Variant(const char *v) : type(STRING), text(v) {}
};
template<class T> struct Vector {
    std::vector<T> items;
    int size() const { return static_cast<int>(items.size()); }
    const T *ptr() const { return items.data(); }
    T *ptrw() { return items.data(); }
    void resize(int n) { ++temporary_resizes; items.resize(n); }
    void append_array(const Vector<T> &other) {
        items.insert(items.end(), other.items.begin(), other.items.end());
    }
};
struct TypedValidation {
    bool as_float = false;
    bool can_reference(const TypedValidation &other) const {
        return as_float && other.as_float;
    }
    const Variant *validate(const Variant &source, Variant &tmp, const char *) const {
        if (!as_float || source.type == Variant::FLOAT) return &source;
        if (source.type == Variant::INT) {
            tmp = Variant(source.number);
            return &tmp;
        }
        return nullptr;
    }
};
struct ArrayState {
    bool read_only = false;
    TypedValidation typed;
    Vector<Variant> array;
};
class Array {
public:
    std::shared_ptr<ArrayState> _p;
    explicit Array(bool typed = false) : _p(std::make_shared<ArrayState>()) {
        _p->typed.as_float = typed;
    }
    bool is_typed() const { return _p->typed.as_float; }
    int size() const { return _p->array.size(); }
    void append_array(const Array &p_array);
};
#define ERR_FAIL_COND_MSG(condition, message) do { if (condition) { ++errors; return; } } while (0)
#define ERR_FAIL_NULL(value) do { if ((value) == nullptr) { ++errors; return; } } while (0)
'''
        checks = r'''
int main() {
    Array target(true);
    Array compatible;
    compatible._p->array.items = {Variant(1.25), Variant(2.5), Variant(3.75)};
    target.append_array(compatible);
    assert(target.size() == 3);
    assert(temporary_resizes == 0);
    assert(target._p->array.items[0].number == 1.25);

    // After appending, mutating source cannot modify the target.
    compatible._p->array.items[0] = Variant(100.0);
    assert(target._p->array.items[0].number == 1.25);

    Array mixed;
    mixed._p->array.items = {Variant(4.25), Variant(5), Variant(6.75), Variant(7)};
    target.append_array(mixed);
    assert(target.size() == 7);
    assert(temporary_resizes == 1);
    for (const auto &v : target._p->array.items) assert(v.type == Variant::FLOAT);
    assert(target._p->array.items[4].number == 5.0);
    assert(target._p->array.items[6].number == 7.0);

    Array empty;
    target.append_array(empty);
    assert(target.size() == 7 && temporary_resizes == 1);

    Array invalid;
    invalid._p->array.items = {Variant(8.5), Variant("invalid")};
    target.append_array(invalid);
    assert(errors == 1);
    assert(target.size() == 7);
    assert(target._p->array.items.back().number == 7.0);

    target._p->read_only = true;
    target.append_array(compatible);
    assert(errors == 2 && target.size() == 7);
}
'''
        compile_and_run(self, setup + "\n" + self.method + "\n" + checks)


class SpinLockBackoffRegression(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        source = read("core/os/spin_lock.h")
        start = source.index("#else // __APPLE__")
        end = source.index("#endif // __APPLE__", start)
        cls.non_apple_lock = source[start + len("#else // __APPLE__") : end]
        cls.apple_lock = source[:start]

    def test_bounded_exponential_pause_with_acquire_and_release(self):
        code = self.non_apple_lock
        self.assertIn("int pauses = 1;", code)
        self.assertIn("static constexpr int MAX_PAUSES = 64;", code)
        self.assertIn("pauses = pauses < MAX_PAUSES ? pauses << 1 : MAX_PAUSES;", code)
        self.assertIn("std::memory_order_acquire", code)
        self.assertIn("std::memory_order_release", code)
        self.assertIn("os_unfair_lock_lock", self.apple_lock)

    def test_compile_actual_spinlock_and_stress_contended_updates(self):
        source = r'''
#include <atomic>
#include <cassert>
#include <chrono>
#include <cstddef>
#include <cstdint>
#include <iostream>
#include <thread>
#include <vector>
#define _ALWAYS_INLINE_ inline
struct Thread { static constexpr size_t CACHE_LINE_BYTES = 64; };
''' + self.non_apple_lock + r'''
int main() {
    for (unsigned threads : {1u, 2u, 4u, 8u}) {
        SpinLock spin;
        std::uint64_t value = 0;
        std::atomic<bool> ready{false};
        std::vector<std::thread> workers;
        const auto begin = std::chrono::steady_clock::now();
        for (unsigned t = 0; t < threads; ++t) {
            workers.emplace_back([&]() {
                while (!ready.load(std::memory_order_acquire)) std::this_thread::yield();
                for (int i = 0; i < 20000; ++i) {
                    spin.lock();
                    ++value;
                    spin.unlock();
                }
            });
        }
        ready.store(true, std::memory_order_release);
        for (auto &thread : workers) thread.join();
        assert(value == std::uint64_t(threads) * 20000u);
        const auto elapsed = std::chrono::duration<double, std::milli>(
            std::chrono::steady_clock::now() - begin).count();
        std::cout << threads << " workers, " << value
                  << " protected increments: " << elapsed << " ms\n";
    }
}
'''
        output = compile_and_run(self, source)
        self.assertIn("8 workers, 160000 protected increments:", output)


if __name__ == "__main__":
    unittest.main()
