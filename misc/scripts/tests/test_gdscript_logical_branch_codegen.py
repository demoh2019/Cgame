"""Regression contracts for optimized GDScript logical branch bytecode."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[3]
BASE = ROOT / "modules/gdscript"
COMPILER = (BASE / "gdscript_compiler.cpp").read_text(encoding="utf-8")
COMPILE_H = (BASE / "gdscript_compiler.h").read_text(encoding="utf-8")
CODEGEN = (BASE / "gdscript_byte_codegen.cpp").read_text(encoding="utf-8")
CODEGEN_H = (BASE / "gdscript_byte_codegen.h").read_text(encoding="utf-8")
API = (BASE / "gdscript_codegen.h").read_text(encoding="utf-8")
FEATURES = BASE / "tests/scripts/runtime/features"
UPSTREAM = (FEATURES / "if_logical_op.gd").read_text(encoding="utf-8")
SIDE_EFFECT = (FEATURES / "if_logical_side_effects.gd").read_text(encoding="utf-8")
OUT = (FEATURES / "if_logical_side_effects.out").read_text(encoding="utf-8")


class GDScriptShortCircuitCodegen(unittest.TestCase):
    def test_new_bytecode_branch_api(self):
        for name in ("start_expr_cond_buffer", "flush_expr_cond_buffer", "write_expr_cond_jump_if",
                     "write_expr_cond_jump", "write_expr_cond_jump_end", "write_expr_cond_end"):
            with self.subTest(name=name):
                self.assertIn(name, API)
                self.assertIn(name, CODEGEN_H)
                self.assertIn(name, CODEGEN)

    def test_branch_types_are_taken_or_not_taken(self):
        self.assertIn("enum BranchType", API)
        self.assertIn("NOT_TAKEN", API)
        self.assertIn("TAKEN", API)

    def test_conditional_lowering_handles_and_or(self):
        self.assertIn("case GDScriptParser::BinaryOpNode::OP_LOGIC_AND:", COMPILER)
        self.assertIn("case GDScriptParser::BinaryOpNode::OP_LOGIC_OR:", COMPILER)
        self.assertIn("_parse_expression_cond(", COMPILER)
        self.assertIn("_parse_expression_cond(", COMPILE_H)

    def test_conditional_jumps_use_short_circuit_bytecodes(self):
        self.assertIn("GDScriptFunction::OPCODE_JUMP_IF", CODEGEN)
        self.assertIn("GDScriptFunction::OPCODE_JUMP_IF_NOT", CODEGEN)

    def test_compiler_flushes_jump_buffers(self):
        self.assertIn("flush_expr_cond_buffer(", COMPILER)
        self.assertIn("expr_cond_buffer_restore_point", CODEGEN_H)

    def test_upstream_truth_table_suite_included(self):
        self.assertIn("func three():", UPSTREAM)
        self.assertIn("if (a or b) or (c or d):", UPSTREAM)

    def test_side_effect_suite_tests_skips_and_execution(self):
        for expected in ("and skips rhs:", "or skips rhs:", "and evaluates rhs:",
                         "or evaluates rhs:", "nested skip:", "nested evaluate once:"):
            with self.subTest(expected=expected):
                self.assertIn(expected, SIDE_EFFECT)
                self.assertIn(expected + " SUCCESS", OUT)

    def test_side_effect_suite_tests_exact_once_evaluation(self):
        self.assertIn("evaluation_count == 1", SIDE_EFFECT)
        self.assertIn("evaluation_count == 0", SIDE_EFFECT)

    def test_expected_result_has_gdtest_header(self):
        self.assertTrue(OUT.startswith("GDTEST_OK\n"))


if __name__ == "__main__":
    unittest.main()
