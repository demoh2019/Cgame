#!/usr/bin/env python3
"""Compile the actual GDScript builtin-argument fast-path guard with GCC/Clang.

This standalone differential test checks the guard against an independent
exhaustive reference predicate. The GDScript runtime suite separately verifies
full type conversion, typed containers and argument defaults.
"""
from __future__ import annotations

from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[3]
VM_PATH = ROOT / "modules/gdscript/gdscript_vm.cpp"
TYPES_PATH = ROOT / "modules/gdscript/gdscript_function.cpp"
SCRIPT_PATH = ROOT / "modules/gdscript/tests/scripts/runtime/features/argument_builtin_fastpath.gd"
OUTPUT_PATH = SCRIPT_PATH.with_suffix(".out")

CPP_PREFIX = r"""
#include <cassert>
#include <cstdint>

struct Variant {
    enum Type { NIL, BOOL, INT, FLOAT, STRING, OBJECT, ARRAY, DICTIONARY, TYPE_COUNT };
    Type type;
    Type get_type() const { return type; }
};
struct GDScriptDataType {
    enum Kind { VARIANT, BUILTIN, NATIVE, SCRIPT, GDSCRIPT };
    Kind kind;
    Variant::Type builtin_type;
    bool typed_array;
    bool typed_dictionary;
    bool has_container_element_type(int index) const { return index == 0 && typed_array; }
    bool has_container_element_types() const { return typed_dictionary; }
};
static bool production_fastpath(const GDScriptDataType &arg_type, const Variant &value) {
    const Variant *p_args[] = { &value };
    const int i = 0;
"""

CPP_SUFFIX = r"""
    return false;
}
static bool reference_fastpath(const GDScriptDataType &arg_type, const Variant &value) {
    if (arg_type.kind != GDScriptDataType::BUILTIN) return false;
    if (arg_type.builtin_type != value.get_type()) return false;
    if (value.get_type() == Variant::ARRAY && arg_type.typed_array) return false;
    if (value.get_type() == Variant::DICTIONARY && arg_type.typed_dictionary) return false;
    return true;
}
int main() {
    for (int kind = 0; kind <= GDScriptDataType::GDSCRIPT; ++kind) {
        for (int formal = 0; formal < Variant::TYPE_COUNT; ++formal) {
            for (int actual = 0; actual < Variant::TYPE_COUNT; ++actual) {
                for (int array_typed = 0; array_typed < 2; ++array_typed) {
                    for (int dictionary_typed = 0; dictionary_typed < 2; ++dictionary_typed) {
                        const GDScriptDataType arg_type = {
                            static_cast<GDScriptDataType::Kind>(kind),
                            static_cast<Variant::Type>(formal),
                            bool(array_typed), bool(dictionary_typed),
                        };
                        const Variant value = { static_cast<Variant::Type>(actual) };
                        assert(production_fastpath(arg_type, value) == reference_fastpath(arg_type, value));
                    }
                }
            }
        }
    }
}
"""


def extract_fastpath(vm: str) -> str:
    start = vm.index("const Variant::Type supplied_type = p_args[i]->get_type();")
    stop = vm.index("// If types already match, don't call Variant::construct()", start)
    code = vm[start:stop]
    placement = "memnew_placement(&stack[i + FIXED_ADDRESSES_MAX], Variant(*p_args[i]));"
    if code.count(placement) != 1 or code.count("continue;") != 1:
        raise ValueError("Unexpected GDScript fast-path body: inspect the VM manually.")
    return code.replace(placement, "").replace("continue;", "return true;")


class GDScriptArgumentTypeFastPathTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.vm = VM_PATH.read_text(encoding="utf-8")
        cls.types = TYPES_PATH.read_text(encoding="utf-8")
        cls.script = SCRIPT_PATH.read_text(encoding="utf-8")
        cls.expected_output = OUTPUT_PATH.read_text(encoding="utf-8")

    def test_extracted_production_guard_compiles_and_matches_reference(self):
        code = CPP_PREFIX + extract_fastpath(self.vm) + CPP_SUFFIX
        compilers = [name for name in ("g++", "clang++") if shutil.which(name)]
        self.assertTrue(compilers, "A C++ compiler is required for the differential test.")
        with tempfile.TemporaryDirectory(prefix="gdscript-arg-fastpath-") as tmp:
            source = Path(tmp) / "fastpath.cpp"
            source.write_text(code, encoding="utf-8")
            for compiler in compilers:
                executable = Path(tmp) / ("test_" + compiler.replace("+", "p"))
                subprocess.run(
                    [compiler, "-std=c++17", "-O2", "-Wall", "-Wextra", "-Werror",
                     str(source), "-o", str(executable)],
                    check=True,
                )
                subprocess.run([str(executable)], check=True)

    def test_typed_array_and_dictionary_guards_remain(self):
        guard = extract_fastpath(self.vm)
        self.assertIn("supplied_type != Variant::ARRAY || !arg_type.has_container_element_type(0)", guard)
        self.assertIn("supplied_type != Variant::DICTIONARY || !arg_type.has_container_element_types()", guard)
        self.assertLess(
            self.vm.index("// If types already match, don't call Variant::construct()"),
            self.vm.index("if (argument_types[i].is_type(*p_args[i], false))"),
        )

    def test_typed_dictionary_validation_avoids_temporary_type_copies(self):
        self.assertIn(
            "container_element_types[0].is_type_exact(dictionary.get_key_type())",
            self.types,
        )
        self.assertIn(
            "container_element_types[1].is_type_exact(dictionary.get_value_type())",
            self.types,
        )
        self.assertIn("container_element_types.size() > 1", self.types)
        self.assertNotIn(
            "GDScriptDataType key = get_container_element_type_or_variant(0)",
            self.types,
        )

    def test_gdscript_runtime_fixture_uses_callable_and_checks_containers(self):
        for phrase in (
            "var f: Callable = _plain_int",
            "f = _plain_float",
            "f = _plain_vector",
            "f = _typed_array",
            "f = _typed_dictionary",
            "f = _native_object",
            "f = _default_argument",
            "f = _variant_argument",
        ):
            self.assertIn(phrase, self.script)
        self.assertEqual(self.expected_output.splitlines(), ["GDTEST_OK"] + ["true"] * 14)


if __name__ == "__main__":
    unittest.main()
