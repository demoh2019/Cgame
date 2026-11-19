"""Structural contracts for the optimized GDScriptInstance property-list pipeline.

The native GDScript runtime fixture tests ordering and _validate_property
against a real engine build. These contracts do not replace native tests.
"""

from pathlib import Path
import unittest

SOURCE = (Path(__file__).resolve().parents[3] / "modules/gdscript/gdscript.cpp").read_text()
START = "void GDScriptInstance::get_property_list(List<PropertyInfo> *r_properties) const {"
END = "\nbool GDScriptInstance::property_can_revert("
BODY = SOURCE.split(START, 1)[1].split(END, 1)[0]

class PropertyListHotpathTests(unittest.TestCase):
    def test_one_level_iteration_through_inheritance(self):
        self.assertIn("while (sptr)", BODY)
        self.assertIn("sptr = sptr->base.ptr();", BODY)

    def test_no_linked_list_or_reverse_buffer(self):
        self.assertNotIn("List<PropertyInfo> props;", BODY)
        self.assertNotIn("props.push_front", BODY)
        self.assertNotIn("msort.reverse", BODY)
        self.assertNotIn("props.clear", BODY)

    def test_only_one_local_sort_buffer(self):
        self.assertIn("LocalVector<_GDScriptMemberSort> msort;", BODY)
        self.assertEqual(BODY.count("msort.sort();"), 1)

    def test_preserves_ordered_members(self):
        self.assertIn("for (const _GDScriptMemberSort &E : msort)", BODY)
        self.assertIn("sptr->member_indices[E.name].property_info", BODY)

    def test_preserves_class_category_before_script_members(self):
        self.assertLess(BODY.index("sptr->get_class_category()"), BODY.index("msort.sort();"))

    def test_prevents_base_member_duplication(self):
        self.assertIn("if (!sptr->members.has(F.key))", BODY)

    def test_validates_both_member_and_dynamic_properties(self):
        self.assertEqual(BODY.count("validate_property(pinfo);"), 2)
        self.assertEqual(BODY.count("r_properties->push_back(pinfo);"), 2)

    def test_exported_members_before_custom_props(self):
        self.assertLess(BODY.index("msort.sort();"), BODY.index("strings._get_property_list"))

    def test_keeps_runtime_custom_return_checks(self):
        self.assertIn("Variant::DICTIONARY", BODY)
        self.assertIn("ERR_CONTINUE(!d.has(\"name\"))", BODY)
        self.assertIn("ERR_CONTINUE(!d.has(\"type\"))", BODY)

    def test_respects_validity_guard(self):
        self.assertIn("if (likely(sptr->valid))", BODY)

    def test_local_vector_is_directly_included(self):
        self.assertIn('#include "core/templates/local_vector.h"', SOURCE)

if __name__ == "__main__":
    unittest.main()
