"""Verify that GDScript VM named-global loads use one lookup and retain errors.

Engine-backed tests live in gdscript_test_runner_suite.h. This is the
lightweight source-contract counterpart for CI on source-only machines.
"""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[3]
VM = ROOT / "modules/gdscript/gdscript_vm.cpp"
NATIVE_SUITE = ROOT / "modules/gdscript/tests/gdscript_test_runner_suite.h"


class GDScriptNamedGlobalSingleProbeTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        vm = VM.read_text(encoding="utf-8")
        start = vm.index("OPCODE(OPCODE_STORE_NAMED_GLOBAL) {")
        end = vm.index("DISPATCH_OPCODE;", start)
        cls.body = vm[start:end]
        cls.tests = NATIVE_SUITE.read_text(encoding="utf-8")

    def test_only_one_hash_lookup_in_vm_opcode(self):
        self.assertIn("get_named_globals_map().getptr(*globalname)", self.body)
        self.assertEqual(self.body.count("get_named_globals_map()"), 1)
        self.assertNotIn("get_named_globals_map().has(", self.body)
        self.assertNotIn("get_named_globals_map()[", self.body)

    def test_missing_globals_still_produce_error(self):
        self.assertIn("if (unlikely(global_value == nullptr))", self.body)
        self.assertIn('Trying to access non-existent autoload singleton', self.body)
        self.assertIn("OPCODE_BREAK;", self.body)
        self.assertIn("*dst = *global_value;", self.body)
        self.assertIn("ip += 3;", self.body)

    def test_runtime_native_case_checks_hot_reads_and_updates(self):
        self.assertIn(
            'TEST_CASE("[GDScriptNamedGlobalFastPath] script reads updated named globals through the VM")',
            self.tests,
        )
        self.assertIn("lang->add_named_global_constant(global_name, 23)", self.tests)
        self.assertIn("lang->add_named_global_constant(global_name, 47)", self.tests)
        self.assertIn("instance->call(\"read_global\")", self.tests)
        self.assertIn("lang->remove_named_global_constant(global_name)", self.tests)
        self.assertIn("get_named_globals_map().getptr(global_name) == nullptr", self.tests)


if __name__ == "__main__":
    unittest.main()
