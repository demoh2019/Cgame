"""Source-level regression checks for variable-step 3D contact warm starting.

These contracts complement the runtime test physics_warmstart_timestep_3d_regression.gd;
they do not replace compiling and executing Godot.
"""
from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[2]
SOURCE_3D = ROOT / "modules" / "godot_physics_3d" / "godot_body_pair_3d.cpp"
SPACE_3D = ROOT / "modules" / "godot_physics_3d" / "godot_space_3d.h"
SOURCE_2D = ROOT / "modules" / "godot_physics_2d" / "godot_body_pair_2d.cpp"
RUNTIME = ROOT / "tests" / "stress" / "physics_warmstart_timestep_3d_regression.gd"


class WarmStartTimestep3DContracts(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        source = SOURCE_3D.read_text(encoding="utf-8")
        start = source.index("bool GodotBodyPair3D::pre_solve(")
        end = source.index("void GodotBodyPair3D::solve(", start)
        cls.pre_solve = source[start:end]

    def test_previous_step_is_tracked_per_space(self):
        source = SPACE_3D.read_text(encoding="utf-8")
        self.assertIn("real_t previous_step = 0.0;", source)
        self.assertIn("real_t get_previous_step() const { return previous_step; }", source)
        self.assertIn("previous_step = last_step;", source)
        self.assertIn("last_step = p_step;", source)
        self.assertLess(source.index("previous_step = last_step;"), source.index("last_step = p_step;"))

    def test_timestep_changes_rescale_all_cached_impulses(self):
        block = self.pre_solve
        self.assertIn("space->get_previous_step()", block)
        self.assertIn("!Math::is_equal_approx(previous_step, p_step)", block)
        self.assertIn("p_step / previous_step", block)
        for field in (
            "acc_normal_impulse",
            "acc_tangent_impulse",
            "acc_bias_impulse",
            "acc_bias_impulse_center_of_mass",
        ):
            self.assertIn(f"c.{field} *= impulse_scale;", block)

    def test_extreme_timestep_changes_discard_previous_impulses(self):
        block = self.pre_solve
        self.assertIn("impulse_scale >= real_t(0.5)", block)
        self.assertIn("impulse_scale <= real_t(2.0)", block)
        self.assertIn("if (can_scale_impulses)", block)
        for field in ("acc_normal_impulse", "acc_bias_impulse", "acc_bias_impulse_center_of_mass"):
            self.assertIn(f"c.{field} = 0.0;", block)
        self.assertIn("c.acc_tangent_impulse = Vector3();", block)

    def test_friction_warmstart_uses_current_coulomb_limit(self):
        block = self.pre_solve
        self.assertIn("mixed_friction * c.acc_normal_impulse", block)
        self.assertIn("cached_tangent_length > cached_tangent_limit", block)
        self.assertIn("cached_tangent_limit / cached_tangent_length", block)
        self.assertLess(
            block.index("const real_t cached_tangent_limit"),
            block.index("Vector3 j_vec = c.normal * c.acc_normal_impulse"),
        )

    def test_2d_and_3d_use_same_impulse_scaling_bounds(self):
        source_2d = SOURCE_2D.read_text(encoding="utf-8")
        for snippet in (
            "get_previous_step()",
            "p_step / previous_step",
            "impulse_scale >= real_t(0.5)",
            "impulse_scale <= real_t(2.0)",
        ):
            self.assertIn(snippet, source_2d)
            self.assertIn(snippet, self.pre_solve)

    def test_runtime_regression_switches_tick_rates(self):
        source = RUNTIME.read_text(encoding="utf-8")
        self.assertIn("Engine.physics_ticks_per_second = 120", source)
        self.assertIn("Engine.physics_ticks_per_second = 30", source)
        self.assertIn("await physics_frame", source)
        self.assertIn("Engine.physics_ticks_per_second = original_ticks", source)


if __name__ == "__main__":
    unittest.main()
