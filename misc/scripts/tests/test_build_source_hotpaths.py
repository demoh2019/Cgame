"""Behavioral regressions for SCons object registration and SCU generation.

Tests use a NodeList-like UserList, so SCons itself is not required.
"""

import os
import sys
import tempfile
import unittest
from collections import UserList
from pathlib import Path
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT))

import methods
import scu_builders


class FakeBuildEnv:
    def __init__(self, glob_results=()):
        self.glob_results = list(glob_results)
        self.glob_patterns = []

    def Glob(self, pattern):
        self.glob_patterns.append(pattern)
        return list(self.glob_results)

    def Object(self, file):
        # SCons Object(...) returns an unhashable NodeList in normal builds.
        return UserList([str(file)])


class SourceRegistrationTests(unittest.TestCase):
    def test_existing_and_repeated_objects_preserve_order_and_warning_count(self):
        env = FakeBuildEnv()
        sources = [UserList(["existing.cpp"])]
        with patch.object(methods, "print_warning") as warn:
            methods.add_source_files_orig(env, sources, [
                "existing.cpp", "a.cpp", "b.cpp", "a.cpp", "b.cpp"
            ])
        self.assertEqual([list(obj) for obj in sources], [
            ["existing.cpp"], ["a.cpp"], ["b.cpp"]
        ])
        self.assertEqual(warn.call_count, 3)

    def test_glob_omits_generated_sources_unless_requested(self):
        env = FakeBuildEnv(["b.gen.cpp", "a.cpp", "c.gen.cpp", "b.cpp"])
        sources = []
        methods.add_source_files_orig(env, sources, "*.cpp")
        self.assertEqual([list(obj) for obj in sources], [["a.cpp"], ["b.cpp"]])
        self.assertEqual(env.glob_patterns, ["*.cpp"])
        methods.add_source_files_orig(env, sources, "*.cpp", allow_gen=True)
        self.assertEqual([list(obj) for obj in sources], [
            ["a.cpp"], ["b.cpp"], ["b.gen.cpp"], ["c.gen.cpp"]
        ])

    def test_hashable_object_builders_remain_supported(self):
        env = FakeBuildEnv()
        env.Object = lambda file: str(file)
        sources = ["already.o"]
        methods.add_source_files_orig(env, sources, ["already.o", "new.o", "new.o"])
        self.assertEqual(sources, ["already.o", "new.o"])

    def test_large_duplicate_heavy_batch_is_deduplicated(self):
        env = FakeBuildEnv()
        sources = [UserList([f"original_{i}.o"]) for i in range(1000)]
        files = [f"new_{i}.o" for i in range(1000)] + [
            f"original_{i}.o" for i in range(200)
        ]
        with patch.object(methods, "print_warning") as warn:
            methods.add_source_files_orig(env, sources, files)
        self.assertEqual(len(sources), 2000)
        self.assertEqual(warn.call_count, 200)
        self.assertEqual(list(sources[-1]), ["new_999.o"])


class SCUGenerationTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.patchers = [
            patch.object(scu_builders, "base_folder_path", str(self.root) + os.sep),
            patch.object(scu_builders, "base_folder_only", self.root.name),
            patch.object(scu_builders, "_max_includes_per_scu", 2),
        ]
        for patcher in self.patchers:
            patcher.start()
            self.addCleanup(patcher.stop)

    def test_scan_preserves_cwd_and_excludes_generated_sources(self):
        folder = self.root / "module"
        folder.mkdir()
        for name in ("z.cpp", "a.cpp", "skip.gen.cpp", "except.cpp"):
            (folder / name).write_text("", encoding="utf-8")
        cwd = os.getcwd()
        includes, exceptions = scu_builders.find_files_in_folder(
            "module", "", [], "cpp", ["except"], []
        )
        self.assertEqual(os.getcwd(), cwd)
        self.assertEqual(set(includes), {
            '#include "module/z.cpp"', '#include "module/a.cpp"'
        })
        self.assertEqual(exceptions, ['#include "module/except.cpp"'])

    def test_output_writer_preserves_slice_and_does_not_rewrite_unchanged_file(self):
        directory = self.root / "generated"
        output = scu_builders.write_output_file(
            0, ["first", "second", "third"], 1, 100, str(directory), "scu_test", "cpp"
        )
        self.assertEqual(output.read_text(encoding="utf-8"), "second\nthird\n")
        with patch.object(Path, "write_text", side_effect=AssertionError("rewritten")):
            again = scu_builders.write_output_file(
                0, ["first", "second", "third"], 1, 100, str(directory), "scu_test", "cpp"
            )
        self.assertEqual(output, again)

    def test_process_folder_splits_includes_and_removes_stale_files(self):
        folder = self.root / "module"
        folder.mkdir()
        for name in ("z.cpp", "a.cpp", "b.cpp", "skip.gen.cpp", "except.cpp"):
            (folder / name).write_text("", encoding="utf-8")
        output = folder / ".scu"
        output.mkdir()
        stale = output / "scu_old.gen.cpp"
        stale.write_text("stale", encoding="utf-8")
        cwd = os.getcwd()
        scu_builders.process_folder(["module"], ["except"], includes_per_scu=2)
        self.assertEqual(os.getcwd(), cwd)
        self.assertFalse(stale.exists())
        regular = sorted(p for p in output.glob("*.gen.cpp") if "_exception" not in p.name)
        exceptions = list(output.glob("*_exception*.gen.cpp"))
        self.assertEqual(len(regular), 2)
        self.assertEqual(len(exceptions), 1)
        lines = [line for file in regular for line in file.read_text().splitlines()]
        self.assertEqual(sorted(lines), [
            '#include "module/a.cpp"',
            '#include "module/b.cpp"',
            '#include "module/z.cpp"',
        ])
        self.assertEqual(exceptions[0].read_text(), '#include "module/except.cpp"\n')


if __name__ == "__main__":
    unittest.main()
