#!/usr/bin/env python3
"""Source-level regressions for upstream Godot glTF PRs #123240 and #120391.

These guards catch partial cherry-picks and accidental reverts; they do not
replace Godot's native SceneTree tests or a compiled engine.
"""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[3]


def source(path):
    return (ROOT / path).read_text(encoding="utf-8")


class GltfPackedAccessorGuards(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.accessor = source("modules/gltf/structures/gltf_accessor.cpp")
        cls.tests = source("tests/scene/test_gltf_document.cpp")

    def test_each_packed_variant_is_written_to_result_array(self):
        kinds = ("PACKED_BYTE_ARRAY", "PACKED_INT32_ARRAY", "PACKED_INT64_ARRAY",
                 "PACKED_FLOAT32_ARRAY", "PACKED_FLOAT64_ARRAY")
        for kind in kinds:
            with self.subTest(kind=kind):
                match = re.search(
                    rf"case Variant::{kind}: \{{(.*?)\}} break;",
                    self.accessor, re.S)
                self.assertIsNotNone(match)
                self.assertIn("ret[value_index] = packed_array;", match.group(1))

    def test_packed_array_indices_are_relative_to_single_value(self):
        body = self.accessor.split("Array GLTFAccessor::decode_as_variants(", 1)[1]
        cases = body.split("case Variant::PACKED_BYTE_ARRAY:", 1)[1].split("default:", 1)[0]
        self.assertEqual(cases.count("packed_array.set(j, numbers[number_index + j]);"), 5)
        self.assertNotIn("packed_array.set(value_index,", cases)

    def test_results_preserve_accessor_count(self):
        body = self.accessor.split("Array GLTFAccessor::decode_as_variants(", 1)[1]
        self.assertIn("ret.resize(count);", body)
        self.assertIn("number_index = value_index * vector_size", body)

    def test_native_regression_has_all_packed_array_types(self):
        text = self.tests.split("Packed numeric glTF accessors preserve element values", 1)[1]
        for kind in ("PACKED_BYTE_ARRAY", "PACKED_INT32_ARRAY", "PACKED_INT64_ARRAY",
                     "PACKED_FLOAT32_ARRAY", "PACKED_FLOAT64_ARRAY"):
            with self.subTest(kind=kind):
                self.assertIn("Variant::" + kind, text)

    def test_native_regression_checks_multiple_entries(self):
        self.assertIn("CHECK(second[2] == 6", self.tests)
        self.assertIn("REQUIRE(rows.size() == 2);", self.tests)


class GltfSpotlightGuards(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.light = source("modules/gltf/extensions/gltf_light.cpp")
        cls.tests = source("tests/scene/test_gltf_document.cpp")

    def test_inner_angle_conversion_accounts_for_degrees(self):
        self.assertIn("deg_to_rad(spot_angle)", self.light)

    def test_exported_spot_inner_cone_is_strictly_below_outer(self):
        self.assertIn("l->inner_cone_angle = l->outer_cone_angle * 0.999999f;", self.light)

    def test_zero_attenuation_does_not_divide_by_zero_during_export(self):
        self.assertIn("if (angle_attenuation != 0.0f)", self.light)

    def test_equal_inner_outer_angles_do_not_divide_by_zero_on_import(self):
        self.assertIn("if (inner_cone_angle >= outer_cone_angle)", self.light)
        self.assertIn("SpotLight3D::PARAM_SPOT_ATTENUATION, 0.0f", self.light)

    def test_glTF_validation_allows_equal_cone_angles(self):
        self.assertIn("if (light->inner_cone_angle > light->outer_cone_angle)", self.light)
        self.assertNotIn("if (light->inner_cone_angle >= light->outer_cone_angle)", self.light)

    def test_native_roundtrip_regression_is_present(self):
        self.assertIn("Spotlight attenuation conversion roundtrips", self.tests)

    def test_native_equal_cone_regression_is_present(self):
        self.assertIn("Equal glTF spotlight cone angles avoid division by zero", self.tests)


if __name__ == "__main__":
    unittest.main()
