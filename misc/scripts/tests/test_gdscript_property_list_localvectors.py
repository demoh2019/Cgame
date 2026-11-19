#!/usr/bin/env python3
"""GDScript property-list allocation and pointer-sort regression contracts.

The engine-executable inheritance and static-member test lives in
misc/benchmarks/gdscript_property_lists/regression.gd.
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

    def test_script_property_sort_uses_pointer_and_local_capacity(self):
        self.assertIn("LocalVector<_GDScriptPropertySort> sorted;", self.script_props)
        self.assertIn("sorted.reserve(sptr->members.size());", self.script_props)
        self.assertIn("sorted.push_back({ E.value.index, &E.value.property_info });", self.script_props)
        self.assertIn("r_list->push_back(*member.info);", self.script_props)

    def test_inheritance_uses_contiguous_stack_not_list(self):
        self.assertIn("LocalVector<const GDScript *> classes;", self.static_props)
        self.assertIn("classes.push_back(top);", self.static_props)
        self.assertNotIn("List<const GDScript *> classes;", self.static_props)

    def test_base_first_order_retained_for_static_properties(self):
        self.assertIn("for (uint32_t i = classes.size(); i > 0; --i)", self.static_props)
        self.assertIn("const GDScript *current = classes[i - 1];", self.static_props)

    def test_static_property_sort_uses_pointers_not_second_hash_lookup(self):
        self.assertIn("LocalVector<_GDScriptPropertySort> sorted;", self.static_props)
        self.assertIn("sorted.reserve(current->static_variables_indices.size());", self.static_props)
        self.assertIn("sorted.push_back({ member.value.index, &member.value.property_info });", self.static_props)
        self.assertIn("p_properties->push_back(*member.info);", self.static_props)
        self.assertNotIn("static_variables_indices[", self.static_props)

    def test_instance_property_sort_uses_pointers(self):
        self.assertIn("LocalVector<_GDScriptPropertySort> sorted;", self.instance_props)
        self.assertIn("sorted.reserve(sptr->members.size());", self.instance_props)
        self.assertIn("sorted.push_back({ member.value.index, &member.value.property_info });", self.instance_props)
        self.assertIn("PropertyInfo pinfo = *member.info;", self.instance_props)
        self.assertNotIn("sptr->member_indices[E.name]", self.instance_props)

    def test_script_categories_and_property_validators_preserved(self):
        self.assertIn("r_list->push_back(sptr->get_class_category());", self.script_props)
        self.assertIn("r_properties->push_back(sptr->get_class_category());", self.instance_props)
        self.assertIn("validate_property(pinfo);", self.instance_props)
        self.assertIn("sorted.sort();", self.script_props)
        self.assertIn("sorted.sort();", self.static_props)
        self.assertIn("sorted.sort();", self.instance_props)

    def test_declared_only_filtering_preserved(self):
        self.assertIn("if (!sptr->members.has(E.key))", self.script_props)
        self.assertIn("if (!sptr->members.has(member.key))", self.instance_props)

    def test_engine_script_checks_both_property_orders(self):
        s = REGRESSION.read_text(encoding="utf-8")
        self.assertIn('["child_first", "child_second", "base_first", "base_second"]', s)
        self.assertIn('["base_static_first", "base_static_second", "child_static_first", "child_static_second"]', s)
        self.assertIn("DerivedScript.get_script_property_list()", s)
        self.assertIn("DerivedScript.get_property_list()", s)
        self.assertIn("quit(1)", s)


if __name__ == "__main__":
    unittest.main()
