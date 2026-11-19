"""Verify that 2D and 3D large-island graph coloring uses the same bit-scan helper.

This source-level contract is an adjunct to the compiled exhaustive test in
tests/servers/test_physics_constraint_color.cpp. It does not benchmark the
native physics solver and cannot replace the C++ test.
"""

from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
HEADER = ROOT / "servers/physics_constraint_color.h"
CPP_2D = ROOT / "modules/godot_physics_2d/godot_step_2d.cpp"
CPP_3D = ROOT / "modules/godot_physics_3d/godot_step_3d.cpp"
NATIVE = ROOT / "tests/servers/test_physics_constraint_color.cpp"


class PhysicsConstraintColorBitScanContracts(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.header = HEADER.read_text(encoding="utf-8")
        cls.cpp2 = CPP_2D.read_text(encoding="utf-8")
        cls.cpp3 = CPP_3D.read_text(encoding="utf-8")
        cls.native = NATIVE.read_text(encoding="utf-8")

    def test_unchanged_color_limits_and_greedy_parity(self):
        for solver in (self.cpp2, self.cpp3):
            self.assertIn("MAX_LARGE_ISLAND_COLORS = 16;", solver)
            self.assertIn('#include "servers/physics_constraint_color.h"', solver)
            self.assertIn(
                "godot_physics_first_available_constraint_color<MAX_LARGE_ISLAND_COLORS>(forbidden)",
                solver,
            )
            self.assertNotIn("for (uint32_t candidate = 0; candidate < MAX_LARGE_ISLAND_COLORS; ++candidate)", solver)
            self.assertIn("if (color < MAX_LARGE_ISLAND_COLORS)", solver)

    def test_scan_is_bounded_and_zero_mask_is_checked_before_scan(self):
        self.assertIn("valid_mask = (uint32_t(1) << COLOR_COUNT) - 1", self.header)
        self.assertIn("const uint32_t available = ~p_used_colors & valid_mask", self.header)
        self.assertIn("if (available == 0)", self.header)
        self.assertIn("return COLOR_COUNT;", self.header)
        self.assertIn("__builtin_ctz(available)", self.header)
        self.assertIn("_BitScanForward(&first_color, available)", self.header)
        self.assertIn("while ((available & (uint32_t(1) << first_color)) == 0)", self.header)

    def test_native_exhaustive_parity_and_overflow(self):
        self.assertIn("TEST_FORCE_LINK(test_physics_constraint_color)", self.native)
        self.assertIn("for (uint32_t used = 0; used <= 0xFFFFu; ++used)", self.native)
        self.assertIn("CHECK(mismatches == 0);", self.native)
        self.assertIn("CHECK(mismatches_high_bits == 0);", self.native)
        self.assertIn("godot_physics_first_available_constraint_color<31>(0x7FFFFFFFu) == 31", self.native)


if __name__ == "__main__":
    unittest.main()
