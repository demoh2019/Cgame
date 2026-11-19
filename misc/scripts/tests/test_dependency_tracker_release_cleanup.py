#!/usr/bin/env python3
"""Native regression for godotengine/godot#125562.

Compiles the real Dependency destructor from Godot, with enough test doubles to
run exactly the same method under both DEBUG_ENABLED and release builds.
"""

import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[3]
SOURCE = ROOT / "servers/rendering/storage/utilities.cpp"


def get_destructor():
    source = SOURCE.read_text(encoding="utf-8")
    match = re.search(r"Dependency::~Dependency\(\)\s*\{", source)
    if not match:
        raise AssertionError("Dependency destructor missing")
    closing = source.find("\n}", match.start())
    if closing == -1:
        raise AssertionError("Dependency destructor end missing")
    return source[match.start(): closing + 2]


HARNESS = r"""
#include <cassert>
#include <cstdint>
#include <unordered_set>
#include <vector>

using uint32_t = std::uint32_t;
template <typename K, typename V>
struct KeyValue {
    K key;
    V value;
};

struct Dependency;
struct DependencyTracker {
    std::unordered_set<Dependency *> dependencies;
};

struct Dependency {
    std::vector<KeyValue<DependencyTracker *, uint32_t>> instances;
    ~Dependency();
};

int warning_count = 0;
#define WARN_PRINT(message) do { ++warning_count; } while (false)

__DESTRUCTOR__

int main() {
    // No trackers: destruction must be harmless in any build mode.
    {
        Dependency empty;
    }
    assert(warning_count == 0);

    // Every tracker must forget a destroyed dependency.
    DependencyTracker first;
    DependencyTracker second;
    DependencyTracker unrelated;
    Dependency *dependency = new Dependency;
    Dependency *survivor = new Dependency;

    first.dependencies.insert(dependency);
    first.dependencies.insert(survivor);
    second.dependencies.insert(dependency);
    unrelated.dependencies.insert(survivor);

    dependency->instances.push_back({ &first, 1 });
    dependency->instances.push_back({ &second, 2 });
    survivor->instances.push_back({ &first, 3 });
    survivor->instances.push_back({ &unrelated, 4 });

    const int previous_warnings = warning_count;
    delete dependency;
    assert(first.dependencies.count(dependency) == 0);
    assert(second.dependencies.count(dependency) == 0);
    assert(first.dependencies.count(survivor) == 1);
    assert(unrelated.dependencies.count(survivor) == 1);
#ifdef DEBUG_ENABLED
    assert(warning_count == previous_warnings + 1);
#else
    assert(warning_count == previous_warnings);
#endif

    // Releasing the second dependency must not leave any dangling pointers.
    delete survivor;
    assert(first.dependencies.empty());
    assert(second.dependencies.empty());
    assert(unrelated.dependencies.empty());
#ifdef DEBUG_ENABLED
    assert(warning_count == previous_warnings + 2);
#else
    assert(warning_count == previous_warnings);
#endif

    // Multiple cleanup cycles without tracked instances.
    for (int i = 0; i < 8; ++i) {
        Dependency *d = new Dependency;
        delete d;
    }
}
"""


class DependencyTrackerLifetimeTests(unittest.TestCase):
    def test_destructor_unlinks_outside_debug_macro(self):
        body = get_destructor()
        self.assertIn("#ifdef DEBUG_ENABLED", body)
        self.assertIn("WARN_PRINT(", body)
        self.assertIn("#endif", body)
        self.assertIn("E.key->dependencies.erase(this);", body)
        self.assertLess(body.index("#endif"), body.index("E.key->dependencies.erase(this);"))
        self.assertEqual(body.count("E.key->dependencies.erase(this);"), 1)

    def test_compiled_destructor_in_debug_and_release(self):
        compiler = os.environ.get("CXX", "c++")
        if not shutil.which(compiler):
            self.skipTest(f"C++ compiler {compiler} unavailable")
        code = HARNESS.replace("__DESTRUCTOR__", get_destructor())
        with tempfile.TemporaryDirectory(prefix="dependency-lifetime-") as temporary:
            for mode, flags in (
                ("release", []),
                ("debug", ["-DDEBUG_ENABLED"]),
            ):
                with self.subTest(build_mode=mode):
                    binary = Path(temporary) / f"dependency_{mode}"
                    build = subprocess.run(
                        [compiler, "-std=c++17", "-Wall", "-Wextra", "-Werror",
                         *flags, "-x", "c++", "-", "-o", str(binary)],
                        input=code, text=True, capture_output=True, check=False,
                    )
                    self.assertEqual(build.returncode, 0, build.stderr)
                    result = subprocess.run(
                        [str(binary)], text=True, capture_output=True, check=False,
                    )
                    self.assertEqual(result.returncode, 0, result.stderr)


if __name__ == "__main__":
    unittest.main()
