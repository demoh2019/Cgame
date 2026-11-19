"""Guard iterative Coulomb rolling/spinning friction for GodotPhysics3D.

This tests the source contract. The companion GDScript workload is an actual
dynamics check and must run on a compiled GodotPhysics3D engine.
"""

import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
MODULE = ROOT / "modules/godot_physics_3d"
STRESS = ROOT / "tests/stress"


class ContactAngularFrictionContracts(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.cpp = (MODULE / "godot_body_pair_3d.cpp").read_text(encoding="utf-8")
        cls.header = (MODULE / "godot_body_pair_3d.h").read_text(encoding="utf-8")
        cls.helper = (ROOT / "servers/physics_contact_angular_friction.h").read_text(encoding="utf-8")
        cls.runner = (STRESS / "run.py").read_text(encoding="utf-8")
        cls.dispatcher = (STRESS / "stress.gd").read_text(encoding="utf-8")
        cls.workload = (STRESS / "physics_contact_angular_friction_3d.gd").read_text(encoding="utf-8")

    def test_new_contacts_can_obtain_friction_from_current_normal_load(self):
        before_solve = self.cpp.split("bool GodotBodyPair3D::pre_solve(real_t p_step) {", 1)[1]
        pre_solve = before_solve.split("void GodotBodyPair3D::solve(real_t p_step) {", 1)[0]
        solver = before_solve.split("void GodotBodyPair3D::solve(real_t p_step) {", 1)[1]
        solver = solver.split("GodotBodyPair3D::GodotBodyPair3D(", 1)[0]

        # No torque is issued during warmstarting. Geometry is retained
        # even when the previous frame's accumulated normal force is zero.
        self.assertIn("angular_friction_contact_mask = 0;", pre_solve)
        self.assertIn("accumulated_spinning_impulse = 0.0;", pre_solve)
        self.assertIn("accumulated_rolling_impulse = Vector3();", pre_solve)
        self.assertIn("if (!c.active || c.depth <= 0.0 || c.mass_normal <= 0.0)", pre_solve)
        self.assertIn("angular_friction_contact_mask |= uint8_t(1) << i;", pre_solve)
        self.assertNotIn("normal_load_impulse += c.acc_normal_impulse", pre_solve)
        self.assertNotIn("apply_torque_impulse(", pre_solve)

        # The current frame's normal impulses are available BEFORE the
        # torsional friction update in the same solve iteration.
        self.assertIn("normal_load_impulse += contacts[i].acc_normal_impulse;", solver)
        self.assertLess(solver.index("c.acc_normal_impulse = MAX("), solver.index("normal_load_impulse += contacts[i].acc_normal_impulse;"))
        self.assertIn("GodotPhysicsContactAngularFriction::clamped_impulse(", solver)

    def test_impulses_are_bounded_across_iterations_and_load_changes(self):
        self.assertIn("real_t accumulated_spinning_impulse = 0.0;", self.header)
        self.assertIn("Vector3 accumulated_rolling_impulse;", self.header)
        self.assertIn("uint8_t angular_friction_contact_mask = 0;", self.header)
        self.assertIn("CLAMP(accumulated_spinning_impulse + unconstrained_delta, -limit, limit)", self.cpp)
        self.assertIn("const Vector3 delta = next_impulse - accumulated_rolling_impulse;", self.cpp)
        self.assertIn("next_impulse *= limit / Math::sqrt(length_squared);", self.cpp)
        self.assertIn("normal_load_impulse >= 0.0", self.cpp)
        self.assertIn("Math::is_finite(limit) && limit >= 0.0", self.cpp)
        self.assertIn("angular_friction_normal.dot(c.normal) < real_t(0.98)", self.cpp)
        self.assertIn("!Math::is_finite(p_relative_angular_velocity)", self.helper)

    def test_stress_checks_new_contact_and_no_airborne_damping(self):
        case = "physics_contact_angular_friction_3d"
        self.assertIn(f'"{case}"', self.runner)
        self.assertIn(f'"{case}":', self.dispatcher)
        self.assertIn('ProjectSettings.set_setting("physics/3d/solver/spinning_friction"', self.workload)
        self.assertIn('ProjectSettings.set_setting("physics/3d/solver/rolling_friction"', self.workload)
        self.assertIn("loaded_spin.early_speed", self.workload)
        self.assertIn("loaded_roll.early_speed", self.workload)
        self.assertIn("free_flight_undamped", self.workload)
        self.assertIn("in_air.final_speed > 18.0", self.workload)
        project = (STRESS / "project.godot").read_text(encoding="utf-8")
        self.assertIn('3d/physics_engine="GodotPhysics3D"', project)


if __name__ == "__main__":
    unittest.main()
