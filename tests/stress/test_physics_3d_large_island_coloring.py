"""Source contracts and stress registration for opt-in 3D large-island coloring.

Run alongside the executable Godot regression; these checks only validate
structure and safety guards, not performance or simulation correctness.
"""

from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[2]
STEP = ROOT / "modules/godot_physics_3d/godot_step_3d.cpp"
STEP_HEADER = ROOT / "modules/godot_physics_3d/godot_step_3d.h"
SPACE_H = ROOT / "modules/godot_physics_3d/godot_space_3d.h"
SPACE_CPP = ROOT / "modules/godot_physics_3d/godot_space_3d.cpp"
SERVER_CPP = ROOT / "servers/physics_3d/physics_server_3d.cpp"
STRESS = ROOT / "tests/stress/stress.gd"
RUNNER = ROOT / "tests/stress/run.py"
WORKLOAD = ROOT / "tests/stress/physics_large_island_3d.gd"
RUNTIME = ROOT / "tests/stress/physics_large_island_3d_regression.gd"


class LargeIsland3DColoringContracts(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.source = STEP.read_text(encoding="utf-8")
        start = cls.source.index("bool GodotStep3D::_solve_large_island(")
        end = cls.source.index("void GodotStep3D::_check_suspend(", start)
        cls.coloring = cls.source[start:end]

    def test_setting_is_opt_in_and_cached_once_per_space(self):
        self.assertIn(
            'GLOBAL_DEF(PropertyInfo(Variant::BOOL, "physics/3d/solver/parallel_large_islands"), false)',
            SERVER_CPP.read_text(encoding="utf-8"),
        )
        self.assertIn(
            'GLOBAL_GET("physics/3d/solver/parallel_large_islands")',
            SPACE_CPP.read_text(encoding="utf-8"),
        )
        header = SPACE_H.read_text(encoding="utf-8")
        self.assertIn("bool parallel_large_islands = false;", header)
        self.assertIn("is_parallel_large_islands_enabled() const", header)

    def test_3d_solver_reuses_scratch_for_large_islands(self):
        header = STEP_HEADER.read_text(encoding="utf-8")
        self.assertIn("LocalVector<GodotConstraint3D *> colored_constraints;", header)
        self.assertIn("uint32_t color_batch_offset = 0;", header)
        self.assertIn("bool _solve_large_island(", header)
        self.assertIn("colored_constraints.resize(constraint_count);", self.coloring)
        self.assertIn("HashMap<GodotBody3D *, uint32_t> occupied_colors;", self.coloring)
        self.assertIn("MIN_PARALLEL_COLOR_CONSTRAINTS", self.coloring)
        self.assertIn("MIN_PARALLEL_LARGE_ISLAND", self.coloring)

    def test_soft_bodies_and_priority_constraints_fallback(self):
        block = self.coloring
        self.assertIn("constraint->get_priority() != 1", block)
        self.assertIn("constraint->get_soft_body_count() != 0", block)
        self.assertIn("constraint->get_body_count() == 0", block)
        self.assertIn("return false;", block)
        self.assertIn("get_body_ptr() == nullptr", block)
        self.assertIn("if (parallelizable_count < MIN_PARALLEL_LARGE_ISLAND)", block)
        code = self.source
        self.assertIn("!_solve_large_island(constraint_islands[island_index])", code)
        self.assertIn("_solve_island(0, nullptr);", code)
        self.assertIn("get_priority() >= current_priority", code)

    def test_same_color_has_no_shared_rigid_bodies(self):
        block = self.coloring
        self.assertIn("occupied_colors.getptr(body)", block)
        self.assertIn("forbidden |= *mask;", block)
        self.assertIn("(forbidden & (uint32_t(1) << candidate)) == 0", block)
        self.assertIn("*mask |= bit;", block)
        self.assertIn("occupied_colors.insert(body, bit);", block)
        self.assertIn("constraint_colors[i] = color;", block)
        # Both static and kinematic bodies are conservatively included.
        self.assertNotIn("get_mode() == PS3DE::BODY_MODE_STATIC", block)

    def test_color_barrier_and_serial_overflow(self):
        block = self.coloring
        self.assertIn('SNAME("Physics3DLargeIslandColor")', block)
        self.assertIn("wait_for_group_task_completion(group)", block)
        self.assertIn("color != MAX_LARGE_ISLAND_COLORS", block)
        self.assertIn("colored_constraints[i]->solve(delta);", block)
        self.assertIn("return true;", block)
        self.assertLess(
            block.index("wait_for_group_task_completion(group)"),
            block.index("return true;"),
        )

    def test_stress_comparison_has_identical_geometry(self):
        script = STRESS.read_text(encoding="utf-8")
        runner = RUNNER.read_text(encoding="utf-8")
        workload = WORKLOAD.read_text(encoding="utf-8")
        for name in (
            "physics_large_island_3d_serial",
            "physics_large_island_3d_parallel",
            "physics_large_island_3d_priority",
        ):
            self.assertIn(f'"{name}"', runner)
            self.assertIn(f'"{name}":', script)
        self.assertIn("LargeIsland3DStress.new().run(self, scale, frames, false)", script)
        self.assertIn("LargeIsland3DStress.new().run(self, scale, frames, true)", script)
        self.assertIn("PhysicsServer3D.joint_make_pin(", workload)
        self.assertIn("PhysicsServer3D.joint_set_solver_priority(joint, 2)", workload)
        self.assertIn("ProjectSettings.set_setting(setting_path, saved_setting)", workload)
        self.assertIn("320 * scale", workload)
        self.assertIn("max_joint_spacing", workload)

    def test_runtime_regression_runs_all_modes(self):
        script = RUNTIME.read_text(encoding="utf-8")
        self.assertIn("[[false, false], [true, false], [true, true]]", script)
        self.assertIn("await LargeIsland3DStress.new().run(", script)
        self.assertIn("result.has(\"error\")", script)
        self.assertIn('int(result["joints"]) < 256', script)


if __name__ == "__main__":
    unittest.main()
