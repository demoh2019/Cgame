"""Source and numerical contract tests for optional SoftBody3D link damping.

Run:
  python3 -m unittest discover -s tests/stress -p test_physics_softbody_link_damping.py -v
Native C++ doctests: [PhysicsLinkDamping] with tests=yes Cgame.
"""

import math
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]


def damp_1d(va, vb, inv_a, inv_b, fraction):
    """Independent scalar reference for equal-direction two-node viscous damper."""
    if not 0.0 <= fraction <= 1.0 or inv_a + inv_b <= 0.0:
        return va, vb
    j = -fraction * (vb - va) / (inv_a + inv_b)
    return va - inv_a * j, vb + inv_b * j


class SoftBodyLinkDampingContracts(unittest.TestCase):
    def test_full_fraction_equal_mass_velocity(self):
        self.assertEqual(damp_1d(0, 10, 1, 1, 1), (5.0, 5.0))

    def test_pinned_node_never_moves(self):
        self.assertEqual(damp_1d(0, 10, 0, 1, 1), (0.0, 0.0))
        self.assertEqual(damp_1d(10, 0, 1, 0, 1), (0.0, 0.0))

    def test_inverse_mass_momentum_conservation(self):
        va, vb = damp_1d(0, 8, 1, 3, 1)
        self.assertAlmostEqual(va + vb / 3, 8 / 3)
        self.assertAlmostEqual(vb - va, 0.0)

    def test_energy_reduced_by_relaxation(self):
        for fraction in (0.01, 0.25, 0.5, 1.0):
            va, vb = damp_1d(0, 8, 1, 1, fraction)
            self.assertLessEqual(va * va + vb * vb, 64)

    def test_half_steps_match_single_exponential_step(self):
        fraction = 1 - math.exp(-1 / 2)
        a, b = damp_1d(0, 8, 1, 1, fraction)
        a, b = damp_1d(a, b, 1, 1, fraction)
        single = damp_1d(0, 8, 1, 1, 1 - math.exp(-1))
        self.assertAlmostEqual(a, single[0], places=12)
        self.assertAlmostEqual(b, single[1], places=12)

    def test_project_setting_is_off_by_default_and_sanitized(self):
        settings = (ROOT / "servers/physics_3d/physics_server_3d.cpp").read_text()
        self.assertIn('physics/3d/solver/soft_body_link_damping"', settings)
        self.assertIn('suffix:1/s"), 0.0)', settings)
        space = (ROOT / "modules/godot_physics_3d/godot_space_3d.cpp").read_text()
        self.assertIn('Math::is_finite(configured_link_damping)', space)
        self.assertIn('get_soft_body_link_damping()', (ROOT / "modules/godot_physics_3d/godot_space_3d.h").read_text())

    def test_disabled_fast_path_and_velocity_integration(self):
        body = (ROOT / "modules/godot_physics_3d/godot_soft_body_3d.cpp").read_text()
        begin = body.index("void GodotSoftBody3D::solve_constraints(")
        before_projection = body.index("node.x = node.q + node.v * p_delta;", begin)
        dashpot = body.index("physics_softbody_damp_link(", begin)
        self.assertLess(dashpot, before_projection)
        self.assertIn("if (link_damping > real_t(0.0) && p_delta > real_t(0.0))", body)
        self.assertIn("1.0 - Math::exp(-double(link_damping) * double(p_delta))", body)
        self.assertNotIn("GLOBAL_GET(", body)

    def test_kernel_transactional_and_broad_scale(self):
        helper = (ROOT / "servers/physics_softbody_link_damping.h").read_text()
        self.assertIn("const double separation_squared", helper)
        self.assertIn("const Vector3 next_a(", helper)
        self.assertIn("const Vector3 next_b(", helper)
        self.assertLess(helper.index("if (!next_a.is_finite() || !next_b.is_finite())"), helper.index("r_velocity_a = next_a;"))
        native = (ROOT / "tests/servers/test_physics_softbody_link_damping.cpp").read_text()
        self.assertEqual(native.count('TEST_CASE("[PhysicsLinkDamping]'), 8)


if __name__ == "__main__":
    unittest.main()
