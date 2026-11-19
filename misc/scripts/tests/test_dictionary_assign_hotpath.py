#!/usr/bin/env python3
"""One-pass Dictionary::assign conversion and atomic error regression contracts."""
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
SOURCE = (ROOT / "core/variant/dictionary.cpp").read_text(encoding="utf-8")
VALIDATOR = (ROOT / "core/variant/container_type_validate.h").read_text(encoding="utf-8")
METHOD = SOURCE.split("void Dictionary::assign(const Dictionary &p_dictionary) {", 1)[1].split(
    "\nconst Variant *Dictionary::next(", 1)[0]


class DictionaryAssignmentFastPath(unittest.TestCase):
    def test_eliminates_temporary_key_value_arrays(self):
        self.assertNotIn("Vector<Variant> key_array;", METHOD)
        self.assertNotIn("Vector<Variant> value_array;", METHOD)
        self.assertNotIn("key_data[", METHOD)
        self.assertNotIn("value_data[", METHOD)

    def test_one_pass_through_source_entries(self):
        self.assertEqual(METHOD.count("for (const KeyValue<Variant, Variant> &kv : p_dictionary._p->variant_map)"), 1)

    def test_fast_path_for_same_types(self):
        self.assertIn("if (!key_needs_conversion && !value_needs_conversion)", METHOD)
        self.assertIn("_p->variant_map = p_dictionary._p->variant_map;", METHOD)

    def test_validate_only_incompatible_entries(self):
        self.assertIn("Variant tkey;", METHOD)
        self.assertIn("Variant tvalue;", METHOD)
        self.assertIn('typed_key.validate(*key, tkey, "", false)', METHOD)
        self.assertIn('typed_value.validate(*value, tvalue, "", false)', METHOD)

    def test_atomic_publish_after_full_validation(self):
        self.assertIn("variant_map.insert(*key, *value);", METHOD)
        self.assertIn("variant_map.size() != ++inserted", METHOD)
        self.assertIn("_p->variant_map = std::move(variant_map);", METHOD)
        self.assertLess(METHOD.index("variant_map.size() != ++inserted"), METHOD.index("_p->variant_map = std::move(variant_map);"))

    def test_key_collision_failure(self):
        self.assertIn("collides with an existing key after conversion.", METHOD)

    def test_validator_error_controls_default_to_legacy_behavior(self):
        self.assertIn("bool p_output_errors = true", VALIDATOR)
        self.assertIn("_internal_validate(p_variant, r_tmp_variant, p_operation, p_output_errors)", VALIDATOR)

    def test_type_checks_happen_before_conversion(self):
        self.assertIn("Variant::can_convert_strict(typed_key_source.variant_type, typed_key.variant_type)", METHOD)
        self.assertIn("Variant::can_convert_strict(typed_value_source.variant_type, typed_value.variant_type)", METHOD)


if __name__ == "__main__":
    unittest.main()
