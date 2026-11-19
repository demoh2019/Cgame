"""Source contracts for PhysX-style orthotropic XPBD cloth stretching.

The C++ numerical tests and independent compiler smoke exercise the actual
rest-direction helper. These source checks do not establish engine build,
runtime stability or CPU/RAM speedup.
"""

from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
MATH = ROOT / "servers/physics_xpbd_cloth_fiber.h"
SERVER = ROOT / "servers/physics_3d/physics_server_3d.cpp"
SPACE_CPP = ROOT / "modules/godot_physics_3d/godot_space_3d.cpp"
SPACE_H = ROOT / "modules/godot_physics_3d/godot_space_3d.h"
BODY = ROOT / "modules/godot_physics_3d/godot_soft_body_3d.cpp"
NATIVE = ROOT / "tests/servers/test_physics_xpbd_cloth_fiber.cpp"
STANDALONE = ROOT / "tests/stress/physics_xpbd_cloth_fiber_standalone.cpp"


class OrthotropicClothFiberContracts(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.math = MATH.read_text(encoding="utf-8")
        cls.server = SERVER.read_text(encoding="utf-8")
        cls.space = SPACE_CPP.read_text(encoding="utf-8")
        cls.space_h = SPACE_H.read_text(encoding="utf-8")
        cls.body = BODY.read_text(encoding="utf-8")
        cls.native = NATIVE.read_text(encoding="utf-8")
        cls.standalone = STANDALONE.read_text(encoding="utf-8")

    def test_default_isotropic_and_cached_settings(self):
        self.assertIn('"physics/3d/solver/soft_body_fiber_compliance_ratio", PROPERTY_HINT_RANGE, "0,100,0.05,or_greater"), 1.0)', self.server)
        self.assertIn('"physics/3d/solver/soft_body_fiber_axis"), Vector3(1, 0, 0)', self.server)
        self.assertIn('GLOBAL_GET("physics/3d/solver/soft_body_fiber_compliance_ratio")', self.space)
        self.assertIn('GLOBAL_GET("physics/3d/solver/soft_body_fiber_axis")', self.space)
        self.assertIn("Math::is_finite(configured_fiber_ratio)", self.space)
        self.assertIn("configured_fiber_axis.is_finite()", self.space)
        self.assertIn("configured_fiber_axis.normalized()", self.space)
        self.assertIn("get_soft_body_fiber_compliance_ratio() const", self.space_h)
        self.assertIn("get_soft_body_fiber_axis() const", self.space_h)
        self.assertNotIn("GLOBAL_GET(", self.body)

    def test_xpbd_only_composes_with_existing_hardening_scratch(self):
        b = self.body
        self.assertIn('#include "servers/physics_xpbd_cloth_fiber.h"', b)
        self.assertIn("use_xpbd && fiber_ratio != real_t(1.0)", b)
        self.assertIn("if (use_tension_hardening || use_fiber_anisotropy)", b)
        self.assertIn("xpbd_link_hardening_alphas.resize(links.size());", b)
        self.assertIn("physics_xpbd_tension_hardening_alpha(", b)
        self.assertIn("physics_xpbd_cloth_fiber_alpha(link.n[0]->s, link.n[1]->s,", b)
        self.assertIn("fiber_axis, fiber_ratio, link_alpha, directional_alpha", b)
        self.assertIn("xpbd_link_hardening_alphas[link_index] = link_alpha;", b)
        self.assertIn("(use_tension_hardening || use_fiber_anisotropy) ? xpbd_link_hardening_alphas[link_index] : alpha,", b)
        self.assertIn("} else if (!xpbd_link_hardening_alphas.is_empty())", b)
        # The existing non-XPBD (legacy PBD) path remains independent.
        self.assertIn("solve_links(1.0, ti);", b)

    def test_mathematics_are_rest_direction_based_and_finite(self):
        c = self.math
        self.assertIn("p_rest_b.x) - double(p_rest_a.x)", c)
        self.assertIn("p_unit_fiber_axis.x", c)
        self.assertIn("dot * dot", c)
        self.assertIn("const double cos2 = CLAMP(", c)
        self.assertIn("(double(p_parallel_compliance_ratio) - 1.0) * cos2", c)
        self.assertIn("isotropic > max_alpha / multiplier", c)
        self.assertIn("r_alpha = value;", c)
        self.assertIn("p_parallel_compliance_ratio < 0.0", c)
        self.assertIn("!(len2 > 0.0) || !(axis2 > 0.0)", c)
        self.assertLess(c.index("if (!Math::is_finite(value))"), c.index("r_alpha = value;"))

    def test_native_and_compiler_smoke_cover_geometry_and_extremes(self):
        self.assertIn("TEST_FORCE_LINK(test_physics_xpbd_cloth_fiber)", self.native)
        for name in (
            "warp and weft compliances follow rest fibers",
            "axis reversal and rigid rest translations are invariant",
            "handles zero and isotropic ratios",
            "rejects degenerate and nonfinite input without mutation",
        ):
            self.assertIn(name, self.native)
        self.assertIn('#include "servers/physics_xpbd_cloth_fiber.h"', self.standalone)
        self.assertIn("iteration < 25000 && ok", self.standalone)
        self.assertIn("std::numeric_limits<real_t>::max()", self.standalone)


if __name__ == "__main__":
    unittest.main()
