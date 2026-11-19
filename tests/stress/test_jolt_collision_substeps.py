"""Regression contracts for optional Jolt collision substepping.

These are source-wiring checks. Native compilation and physics behavior are
validated separately by the whole-engine CI's physics build and CCD stress case.
"""

from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[2]
SETTINGS_CPP = ROOT / "modules/jolt_physics/jolt_project_settings.cpp"
SETTINGS_H = ROOT / "modules/jolt_physics/jolt_project_settings.h"
SPACE_CPP = ROOT / "modules/jolt_physics/spaces/jolt_space_3d.cpp"

COLLISION_STEPS = "physics/jolt_physics_3d/simulation/collision_steps"
MAX_COLLISION_STEP = "physics/jolt_physics_3d/simulation/max_collision_step_seconds"


class JoltCollisionSubstepContracts(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.settings = SETTINGS_CPP.read_text(encoding="utf-8")
        cls.header = SETTINGS_H.read_text(encoding="utf-8")
        cls.space = SPACE_CPP.read_text(encoding="utf-8")
        step_start = cls.space.index("void JoltSpace3D::step(float p_step) {")
        step_end = cls.space.index("\nvoid JoltSpace3D::", step_start + 1)
        cls.step = cls.space[step_start:step_end]

    def test_defaults_preserve_single_collision_pass(self):
        self.assertRegex(self.settings, re.escape(COLLISION_STEPS) + r'".*\), 1\);')
        self.assertRegex(self.settings, re.escape(MAX_COLLISION_STEP) + r'".*\), 0\.0f\);')

    def test_every_setting_is_registered_read_and_cached(self):
        for path, member, typ in (
            (COLLISION_STEPS, "simulation_collision_steps", "int"),
            (MAX_COLLISION_STEP, "simulation_max_collision_step_seconds", "float"),
        ):
            with self.subTest(setting=path):
                self.assertEqual(self.settings.count('"' + path + '"'), 2)
                self.assertIn(f"inline static {typ} {member};", self.header)
                self.assertIn(f'{member} = GLOBAL_GET("{path}");', self.settings)

    def test_runtime_bounds_before_cast(self):
        self.assertIn("CLAMP(JoltProjectSettings::simulation_collision_steps, 1, 8)", self.step)
        self.assertIn("max_step_seconds > 0.0f && p_step > max_step_seconds", self.step)
        self.assertIn("estimated_steps >= 8.0f ? 8 : int(Math::ceil(estimated_steps))", self.step)
        self.assertIn("collision_steps = MAX(collision_steps, needed_steps)", self.step)

    def test_update_uses_computed_steps_not_hardcoded_one(self):
        self.assertIn("physics_system->Update(p_step, collision_steps, temp_allocator, job_system)", self.step)
        self.assertNotIn("physics_system->Update(p_step, 1, temp_allocator, job_system)", self.step)

    def test_only_one_physics_update_per_engine_step(self):
        self.assertEqual(self.step.count("physics_system->Update("), 1)
        self.assertLess(self.step.index("_pre_step(p_step)"), self.step.index("physics_system->Update("))
        self.assertLess(self.step.index("physics_system->Update("), self.step.index("_post_step(p_step)"))


if __name__ == "__main__":
    unittest.main()
