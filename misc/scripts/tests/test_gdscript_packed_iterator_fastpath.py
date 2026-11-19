"""Validate packed-array VM iterator fast path and native fixture coverage."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[3]
VM = ROOT / "modules/gdscript/gdscript_vm.cpp"
SCRIPT = ROOT / "modules/gdscript/tests/scripts/runtime/features/packed_array_iterator_fastpath.gd"
OUT = SCRIPT.with_suffix(".out")


class PackedArrayIteratorFastPathTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.vm = VM.read_text(encoding="utf-8")
        cls.script = SCRIPT.read_text(encoding="utf-8")
        cls.out = OUT.read_text(encoding="utf-8")
        a = cls.vm.index("#define OPCODE_ITERATE_BEGIN_PACKED_ARRAY(")
        b = cls.vm.index("OPCODE_ITERATE_BEGIN_PACKED_ARRAY(BYTE", a)
        cls.begin = cls.vm[a:b]
        a = cls.vm.index("#define OPCODE_ITERATE_PACKED_ARRAY(")
        b = cls.vm.index("OPCODE_ITERATE_PACKED_ARRAY(BYTE", a)
        cls.next = cls.vm[a:b]

    def test_begin_only_reads_first_element_when_non_empty(self):
        self.assertIn("if (!array->is_empty())", self.begin)
        self.assertIn("*it = array->ptr()[0]", self.begin)
        self.assertNotIn("array->get(0)", self.begin)

    def test_next_checks_bounds_before_raw_pointer_read(self):
        self.assertIn("if (*idx >= array->size())", self.next)
        self.assertIn("array->ptr()[*idx]", self.next)
        self.assertNotIn("array->get(*idx)", self.next)
        self.assertLess(
            self.next.index("if (*idx >= array->size())"),
            self.next.index("array->ptr()[*idx]"),
        )

    def test_every_packed_type_uses_the_shared_optimized_opcode(self):
        types = [
            "BYTE", "INT32", "INT64", "FLOAT32", "FLOAT64",
            "STRING", "VECTOR2", "VECTOR3", "COLOR", "VECTOR4",
        ]
        for name in types:
            self.assertIn("OPCODE_ITERATE_BEGIN_PACKED_ARRAY(" + name + ",", self.vm)
            self.assertIn("OPCODE_ITERATE_PACKED_ARRAY(" + name + ",", self.vm)

    def test_runtime_cases_for_all_element_types_and_boundaries(self):
        for type_name in [
            "PackedByteArray", "PackedInt32Array", "PackedInt64Array",
            "PackedFloat32Array", "PackedFloat64Array", "PackedStringArray",
            "PackedVector2Array", "PackedVector3Array", "PackedColorArray",
            "PackedVector4Array",
        ]:
            self.assertIn(type_name + "())", self.script)
        self.assertIn("large_bytes.resize(4096)", self.script)
        self.assertIn("large_int32.resize(4096)", self.script)
        self.assertEqual(self.out.splitlines(), ["GDTEST_OK"] + ["true"] * 32)
        self.assertEqual(self.script.count("print("), 32)


if __name__ == "__main__":
    unittest.main()
