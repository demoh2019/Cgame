"""Upstream #123791: VM typed container checks do not create transient Ref wrappers."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[3]
VM = ROOT / "modules/gdscript/gdscript_vm.cpp"


class TypedContainerVMLookupTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.cpp = VM.read_text(encoding="utf-8")
        cls.src = (ROOT / "modules/gdscript/tests/scripts/runtime/features/typed_container_vm_fastpath.gd").read_text()
        cls.output = (ROOT / "modules/gdscript/tests/scripts/runtime/features/typed_container_vm_fastpath.out").read_text()

    def test_container_type_header_included(self):
        self.assertIn('#include "core/variant/container_type_validate.h"', self.cpp)

    def test_array_metadata_read_directly_in_three_paths(self):
        self.assertEqual(self.cpp.count("const ContainerType &array_type = array->get_element_type();"), 3)

    def test_dictionary_metadata_read_directly_in_three_paths(self):
        self.assertEqual(self.cpp.count("const ContainerType &key_dict_type = dictionary->get_key_type();"), 3)
        self.assertEqual(self.cpp.count("const ContainerType &value_dict_type = dictionary->get_value_type();"), 3)

    def test_old_array_getters_not_used_in_vm(self):
        for old in ("array->get_typed_builtin()", "array->get_typed_class_name()", "array->get_typed_script()"):
            self.assertNotIn(old, self.cpp)

    def test_old_dictionary_getters_not_used_in_vm(self):
        for old in ("dictionary->get_typed_key_builtin()", "dictionary->get_typed_key_class_name()",
                    "dictionary->get_typed_key_script()", "dictionary->get_typed_value_builtin()",
                    "dictionary->get_typed_value_class_name()", "dictionary->get_typed_value_script()"):
            self.assertNotIn(old, self.cpp)

    def test_array_script_type_resolved_without_ref(self):
        self.assertGreaterEqual(self.cpp.count("Script *script_type = Object::cast_to<Script>(type->operator Object *());"), 3)

    def test_dictionary_types_resolved_without_ref(self):
        self.assertEqual(self.cpp.count("Script *key_script_type = Object::cast_to<Script>(key_type->operator Object *());"), 3)
        self.assertEqual(self.cpp.count("Script *value_script_type = Object::cast_to<Script>(value_type->operator Object *());"), 3)

    def test_debug_error_reporting_preserved(self):
        for kind in ("Trying to assign an array", "Trying to assign a dictionary",
                     "Trying to return a value", 'return type is "Dictionary['):
            self.assertIn(kind, self.cpp)

    def test_array_is_opcode_is_covered_by_runtime_test(self):
        self.assertIn("dynamic_numbers is Array[int]", self.src)
        self.assertIn("dynamic_numbers is Array[String]", self.src)

    def test_dictionary_is_opcode_is_covered_by_runtime_test(self):
        self.assertIn("dynamic_labels is Dictionary[int, String]", self.src)
        self.assertIn("dynamic_labels is Dictionary[int, int]", self.src)

    def test_typed_return_opcodes_covered(self):
        self.assertIn("-> Array[int]:", self.src)
        self.assertIn("-> Dictionary[int, String]:", self.src)

    def test_expected_output_has_mixed_positive_and_negative_cases(self):
        self.assertEqual(self.output.splitlines(), ["GDTEST_OK", "true", "false", "true", "false", "true", "true"])


if __name__ == "__main__":
    unittest.main()
