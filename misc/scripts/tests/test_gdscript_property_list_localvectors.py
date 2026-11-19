#!/usr/bin/env python3
"""GDScript property-list memory and ordering source contracts.

Real script inheritance and static-field order are tested by the engine
regression project in misc/benchmarks/gdscript_property_lists.
"""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[3]
SOURCE = ROOT / "modules/gdscript/gdscript.cpp"
REGRESSION = ROOT / "misc/benchmarks/gdscript_property_lists/regression.gd"

class TestGDScriptPropertyListLocalVectors(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        source = SOURCE.read_text(encoding="utf-8")
        cls.script_props = source[
            source.index("void GDScript::_get_script_property_list("):
            source.index("\nvoid GDScript::get_script_property_list(", source.index("void GDScript::_get_script_property_list("))
        ]
        cls.static_props = source[
            source.index("void GDScript::_get_property_list("):
            source.index("\nvoid GDScript::_bind_methods(", source.index("void GDScript::_get_property_list("))
        ]
        cls.instance_props = source[
            source.index("void GDScriptInstance::get_property_list("):
            source.index("\nbool GDScriptInstance::property_can_revert(", source.index("void GDScriptInstance::get_property_list("))
        ]

    def test_declared_members_use_reserved_localvector(self):
        self.assertIn("LocalVector<_GDScriptMemberSort> msort;", self.script_props)
        self.assertIn("msort.reserve(sptr->members.size());", self.script_props)
        self.assertNotIn("\t\tVector<_GDScriptMemberSort> msort;", self.script_props)

    def test_inheritance_uses_contiguous_stack_not_list(self):
        self.assertIn("LocalVector<const GDScript *> classes;", self.static_props)
        self.assertIn("classes.push_back(top);", self.static_props)
        self.assertNotIn("List<const GDScript *> classes;", self.static_props)

    def test_base_first_order_retained_for_static_properties(self):
        self.assertIn("for (uint32_t i = classes.size(); i > 0; --i)", self.static_props)
        self.assertIn("const GDScript *current = classes[i - 1];", self.static_props)

    def test_static_members_reserve_exact_declared_count(self):
        self.assertIn("LocalVector<_GDScriptMemberSort> msort;", self.static_props)
        self.assertIn("msort.reserve(current->static_variables_indices.size());", self.static_props)
        self.assertIn("msort.sort();", self.static_props)

    def test_instance_property_list_reserves_local_members(self):
        self.assertIn("LocalVector<_GDScriptMemberSort> msort;", self.instance_props)
        self.assertIn("msort.reserve(sptr->members.size());", self.instance_props)
        self.assertIn("validate_property(pinfo);", self.instance_props)

    def test_script_property_sort_and_category_preserved(self):
        self.assertIn("msort.sort();", self.script_props)
        self.assertIn("r_list->push_back(sptr->get_class_category());", self.script_props)
        self.assertIn("r_list->push_back(sptr->member_indices[member.name].property_info);", self.script_props)

    def test_engine_regression_includes_both_property_orders(self):
        s = REGRESSION.read_text(encoding="utf-8")
        self.assertIn('["child_first", "child_second", "base_first", "base_second"]', s)
        self.assertIn('["base_static_first", "base_static_second", "child_static_first", "child_static_second"]', s)
        self.assertIn("DerivedScript.get_script_property_list()", s)
        self.assertIn("DerivedScript.get_property_list()", s)
        self.assertIn("quit(1)", s)

if __name__ == "__main__":
    unittest.main()
