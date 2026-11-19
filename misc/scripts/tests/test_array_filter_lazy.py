#!/usr/bin/env python3
"""Source regressions for allocation-on-first-match Array::filter.

The native C++ tests exercise behavior; these contracts guarantee the fast
empty-result path does not allocate the element buffer.
"""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[3]
CORE = ROOT / "core/variant/array.cpp"
NATIVE = ROOT / "tests/core/variant/test_array_filter_lazy.cpp"

class TestArrayFilterLazy(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        source = CORE.read_text(encoding="utf-8")
        begin = source.index("Array Array::filter(const Callable &p_callable) const {")
        end = source.index("\nArray Array::map(", begin)
        cls.section = source[begin:end]
        cls.native = NATIVE.read_text(encoding="utf-8")

    def test_element_buffer_is_allocated_only_after_a_true_predicate(self):
        code = self.section
        first_predicate = code.index("if (result.operator bool())")
        allocation = code.index("new_arr.resize(size() - i);")
        self.assertLess(first_predicate, allocation)
        self.assertIn("if (write == nullptr)", code[first_predicate:allocation])
        self.assertIn("new_arr.resize(size() - i);", code)
        self.assertNotIn("new_arr.resize(", code[:first_predicate])

    def test_all_rejected_keeps_zero_element_storage(self):
        self.assertIn("Variant *write = nullptr;", self.section)
        self.assertIn("if (write != nullptr) {\n\t\tnew_arr.resize(accepted_count);", self.section)

    def test_callback_order_and_dynamic_source_loop_unchanged(self):
        self.assertIn("for (int i = 0; i < size(); i++)", self.section)
        self.assertIn("argptrs[0] = &get(i);", self.section)
        self.assertIn("p_callable.callp(argptrs, 1, result, ce);", self.section)
        self.assertIn("write[accepted_count++] = get(i);", self.section)

    def test_type_constraint_assigned_after_resizing(self):
        self.assertIn("new_arr._p->typed = _p->typed;", self.section)
        self.assertGreater(
            self.section.index("new_arr._p->typed = _p->typed;"),
            self.section.index("new_arr.resize(accepted_count);")
        )

    def test_source_extension_can_grow_buffer_safely(self):
        self.assertIn("if (accepted_count == new_arr.size())", self.section)
        self.assertIn("new_arr.resize(accepted_count + 1);", self.section)
        self.assertIn("write = new_arr._p->array.ptrw();", self.section)

    def test_native_cases_cover_core_semantics(self):
        self.assertIn("TEST_FORCE_LINK(test_array_filter_lazy)", self.native)
        self.assertEqual(self.native.count('TEST_CASE("[ArrayFilterLazy]'), 10)
        for term in (
            "All rejected leaves an empty result",
            "All accepted retains source order",
            "Partial acceptance keeps ordering",
            "Late first match allocates only the remaining suffix",
            "Empty typed results",
            "Nonempty typed results",
            "Empty input does not invoke",
            "Source mutations from callbacks",
            "Growing the source from callbacks",
            "Repeated empty-filter queries"
        ):
            self.assertIn(term, self.native)

if __name__ == "__main__":
    unittest.main()
