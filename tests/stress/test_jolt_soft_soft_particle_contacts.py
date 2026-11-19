"""Reference physics and source contracts for experimental soft-soft contacts.

Native scene is tests/stress/jolt_soft_soft/soft_soft_particle_regression.gd.
This suite cannot replace a compiled Cgame Jolt run.
"""
import math
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
SPACE = ROOT / "modules/jolt_physics/spaces/jolt_space_3d.cpp"
SETTINGS = ROOT / "modules/jolt_physics/jolt_project_settings.cpp"
HEADER = ROOT / "modules/jolt_physics/jolt_project_settings.h"
SOFT_CPP = ROOT / "modules/jolt_physics/objects/jolt_soft_body_3d.cpp"
SOFT_H = ROOT / "modules/jolt_physics/objects/jolt_soft_body_3d.h"
PROJECT = ROOT / "tests/stress/jolt_soft_soft/project.godot"
FIXTURE = ROOT / "tests/stress/jolt_soft_soft/soft_soft_particle_regression.gd"


def contact_response(v_a, v_b, inv_a, inv_b, distance, radius, dt,
                     recovery=0.2, friction=0.2):
    """Reference 2D normal X and tangent Y, returning new velocities.

    Delta = impulse*(inverse mass) with Newton's third law.
    """
    if inv_a + inv_b <= 0 or distance >= radius:
        return (v_a, v_b)
    rel_x = v_b[0] - v_a[0]
    rel_y = v_b[1] - v_a[1]
    bias = min((radius - distance) * recovery / dt, 2.0)
    correction = min(max(bias - rel_x, 0.0), 8.0)
    if not correction:
        return (v_a, v_b)
    impulse = correction / (inv_a + inv_b)
    friction_impulse = min(abs(rel_y) / (inv_a + inv_b), friction * impulse)
    tangent_impulse = -math.copysign(friction_impulse, rel_y) if rel_y else 0.0
    return (
        (v_a[0] - impulse * inv_a, v_a[1] - tangent_impulse * inv_a),
        (v_b[0] + impulse * inv_b, v_b[1] + tangent_impulse * inv_b),
    )


class SoftSoftParticleContactTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.space = SPACE.read_text(encoding="utf-8")
        cls.settings = SETTINGS.read_text(encoding="utf-8")
        cls.header = HEADER.read_text(encoding="utf-8")
        cls.soft = SOFT_CPP.read_text(encoding="utf-8")
        cls.soft_header = SOFT_H.read_text(encoding="utf-8")
        cls.contact = cls.space.split("static void resolve_soft_soft_particle_contacts(", 1)[1].split(
            "static void clear_pending_index(", 1
        )[0]
        cls.prestep = cls.space.split("void JoltSpace3D::_pre_step(float p_step) {", 1)[1].split(
            "void JoltSpace3D::_post_step(", 1
        )[0]

    def test_default_is_off_and_has_zero_allocation_fast_path(self):
        self.assertIn("inline static bool soft_body_soft_contacts = false;", self.header)
        self.assertIn('simulation/soft_body_soft_contacts"), false', self.settings)
        self.assertIn("if (JoltProjectSettings::soft_body_soft_contacts &&", self.prestep)

    def test_collision_masks_and_exception_filters(self):
        self.assertIn("object_a->can_interact_with(*object_b)", self.prestep)
        self.assertIn("get_bounds().grow(radius)", self.prestep)
        self.assertIn("bounds_a.intersects(", self.prestep)
        self.assertIn("soft_body_set_collision_mask(body, mask)", FIXTURE.read_text(encoding="utf-8"))

    def test_only_actual_surface_particles_are_considered(self):
        self.assertIn("surface_particle_count = (uint32_t)physics_vertices.size();", self.soft)
        self.assertIn("get_surface_particle_count() const", self.soft_header)
        self.assertIn("MIN(p_object_a.get_surface_particle_count()", self.contact)
        self.assertIn("MIN(p_object_b.get_surface_particle_count()", self.contact)

    def test_budgets_limit_quadratic_checks(self):
        self.assertIn("MAX_SOFT_SOFT_BODY_PAIR_CHECKS = 2048", self.space)
        self.assertIn("--r_particle_budget;", self.contact)
        self.assertIn("MAX_SOFT_SOFT_CONTACT_SPEED_CORRECTION = 8.0f", self.space)
        self.assertIn("CLAMP((int)GLOBAL_GET", self.settings)
        self.assertIn("soft_body_soft_contact_max_particle_pairs", self.settings)

    def test_mass_weighted_impulses_preserve_momentum(self):
        for inv_a, inv_b in ((1, 1), (1, 3), (0, 2), (2, 0), (0.01, 100)):
            ma = 1 / inv_a if inv_a else math.inf
            mb = 1 / inv_b if inv_b else math.inf
            a = (3.0, 1.0)
            b = (-2.0, -1.0)
            result_a, result_b = contact_response(a, b, inv_a, inv_b, 0.05, 0.15, 1 / 60)
            self.assertTrue(all(math.isfinite(x) for x in result_a + result_b))
            if inv_a and inv_b:
                for axis in (0, 1):
                    self.assertAlmostEqual((result_a[axis] - a[axis]) * ma,
                                           -(result_b[axis] - b[axis]) * mb, places=5)
            if inv_a == 0:
                self.assertEqual(result_a, a)
            if inv_b == 0:
                self.assertEqual(result_b, b)

    def test_friction_reduces_relative_tangential_speed(self):
        a, b = contact_response((1, 1), (-1, -1), 1, 1, 0.03, 0.1, 1 / 60, friction=0.7)
        self.assertLessEqual(abs(b[1] - a[1]), 2)
        self.assertGreaterEqual(b[0] - a[0], -2)

    def test_no_contact_and_static_static_are_noops(self):
        a, b = (1, 3), (-2, 0)
        self.assertEqual(contact_response(a, b, 1, 1, 0.2, 0.1, 1 / 60), (a, b))
        self.assertEqual(contact_response(a, b, 0, 0, 0.02, 0.1, 1 / 60), (a, b))

    def test_godot_fixture_and_ci_commands_are_grounded(self):
        cfg = PROJECT.read_text(encoding="utf-8")
        native = FIXTURE.read_text(encoding="utf-8")
        self.assertIn("soft_body_soft_contacts=true", cfg)
        self.assertIn("soft_body_soft_contact_radius=0.16", cfg)
        self.assertIn("mask", native)
        self.assertIn("PASS: Jolt bounded soft-soft particle contact response and layer masks", native)


if __name__ == "__main__":
    unittest.main()
