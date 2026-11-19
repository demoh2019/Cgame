#!/usr/bin/env python3
"""Regression contract for known-size hash and Dictionary preallocation.

The suite checks 17 hot-path reserve points; native Doctest coverage tests
HashMap, HashSet and Dictionary semantics separately. This is not a benchmark.
"""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[3]
CONTRACTS = {
    "core/config/project_settings.cpp": ["HashSet<StringName> cache(scene_groups.size());"],
    "core/extension/gdextension_interface.cpp": ["HashMap<StringName, Variant> values_map(values.size());"],
    "core/io/file_access_pack.cpp": ["r_paths.reserve(r_paths.size() + p_dir->files.size());"],
    "core/io/marshalls.cpp": ["dict.reserve(MIN(count, 65536));"],
    "core/io/remote_filesystem_client.cpp": ["HashSet<String> files_processed(MIN(file_count, 65536u));"],
    "core/io/resource.cpp": ["dst.reserve(src.size());"],
    "core/io/resource_format_binary.cpp": ["d.reserve(MIN(len, 65536u));"],
    "core/io/resource_loader.cpp": ["deps_dict.reserve(p_map.size());"],
    "core/math/color.cpp": ["named_colors_hashmap.reserve(named_color_count);"],
    "core/object/script_language.cpp": ["ret.reserve(map.size());"],
    "core/os/os.cpp": [
        "benchmark_marks.reserve(benchmark_marks_final.size());",
        "results.reserve(benchmark_marks_final.size());",
    ],
    "core/string/translation.cpp": [
        "d.reserve(translation_map.size());",
        "translation_map.reserve(p_messages.size());",
    ],
    "core/variant/variant.cpp": ["type_names.reserve(Variant::VARIANT_MAX);"],
    "core/variant/variant_parser.cpp": [
        "builtin_types.reserve(Variant::VARIANT_MAX - 1);",
    ],
}


class HashPreallocationContracts(unittest.TestCase):
    def test_all_known_size_reserves_present(self):
        self.assertEqual(len(CONTRACTS), 14)
        for path, expected in CONTRACTS.items():
            source = (ROOT / path).read_text(encoding="utf-8")
            for marker in expected:
                with self.subTest(path=path, marker=marker):
                    expected_count = 2 if path.endswith("variant_parser.cpp") else 1
                    self.assertEqual(source.count(marker), expected_count)

    def test_native_regressions_cover_all_containers(self):
        source = (ROOT / "tests/core/templates/test_hash_preallocation.cpp").read_text(encoding="utf-8")
        self.assertIn("TEST_FORCE_LINK(test_hash_preallocation)", source)
        self.assertEqual(source.count('TEST_CASE("[HashPreallocation]'), 7)
        self.assertIn("HashMap<int, int> map;", source)
        self.assertIn("HashSet<int> set;", source)
        self.assertIn("Dictionary dict;", source)

    def test_bounds_are_known_before_reserve(self):
        source = (ROOT / "core/io/resource_format_binary.cpp").read_text(encoding="utf-8")
        self.assertLess(source.find("len &= 0x7FFFFFFF;"), source.find("d.reserve(MIN(len, 65536u));"))
        source = (ROOT / "core/io/marshalls.cpp").read_text(encoding="utf-8")
        self.assertIn("dict.reserve(MIN(count, 65536));", source)
        source = (ROOT / "core/string/translation.cpp").read_text(encoding="utf-8")
        self.assertIn("translation_map.clear();\n\ttranslation_map.reserve(p_messages.size());", source)


if __name__ == "__main__":
    unittest.main()
