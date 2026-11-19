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
        self.assertIn("AHashMap<GodotBody3D *, uint32_t> occupied_colors;", header)
        self.assertIn("occupied_colors.clear();", self.coloring)
        self.assertIn("constraint_colors.resize(constraint_count);", self.coloring)
        self.assertIn("color_batch_count = count;", self.coloring)
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
        self.assertIn("!_solve_large_island(constraint_islands[large_island_index])", code)
        self.assertIn("_solve_island(large_island_job_index, nullptr);", code)
        self.assertIn("get_priority() >= current_priority", code)

    def test_same_color_has_no_shared_rigid_bodies(self):
        block = self.coloring
        self.assertIn("occupied_colors.getptr(body)", block)
        self.assertIn("forbidden |= *mask;", block)
        self.assertIn("(forbidden & (uint32_t(1) << candidate)) == 0", block)
        self.assertIn("*mask |= bit;", block)
        self.assertIn("occupied_colors.insert(body, bit);", block)
        self.assertIn("constraint_colors[i] = color;", block)
        # Static and kinematic bodies are read-only only for contact-only
        # islands. Mixed islands continue reserving every body pointer.
        self.assertIn("bool contact_only_island = true;", block)
        self.assertIn("!p_constraint_island[i]->permits_parallel_immovable_body_sharing()", block)
        self.assertIn("(!contact_only_island || body->get_mode() > PS3DE::BODY_MODE_KINEMATIC)", block)
        self.assertIn("(contact_only_island && body->get_mode() <= PS3DE::BODY_MODE_KINEMATIC)", block)

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

    def test_dominant_island_runs_after_independent_jobs(self):
        code = self.source
        header = STEP_HEADER.read_text(encoding="utf-8")
        self.assertIn("uint32_t deferred_large_island_index = UINT32_MAX;", header)
        self.assertIn("void _solve_island_except_large(", header)
        self.assertIn("void GodotStep3D::_solve_island_except_large(", code)
        self.assertIn(
            "solve_island_indices.is_empty() ? p_island_index : solve_island_indices[p_island_index]",
            code,
        )
        self.assertIn("island_index != deferred_large_island_index", code)
        self.assertIn("if (large_island_count == 1)", code)
        self.assertIn("Physics3DOtherConstraintIslands", code)
        self.assertIn("_solve_island_except_large(i, nullptr);", code)
        self.assertIn("deferred_large_island_index = UINT32_MAX;", code)
        # Waiting on the ordinary island group is mandatory before the
        # colored solver can reuse its scratch and launch nested worker jobs.
        start = code.index("if (large_island_count == 1)")
        end = code.index("} else if (solve_island_count < MIN_PARALLEL_SOLVE_ISLANDS", start)
        dominant = code[start:end]
        self.assertLess(
            dominant.index("wait_for_group_task_completion(group_task);"),
            dominant.index("if (!_solve_large_island("),
        )

    def test_two_large_islands_use_regular_parallel_jobs(self):
        code = self.source
        self.assertIn("if (++large_island_count == 2)", code)
        self.assertIn("large_island_count < 2", code)
        self.assertIn("Physics3DConstraintSolveIslands", code)
        self.assertIn("large_island_job_index = i;", code)
        self.assertIn("large_island_index = index;", code)
        self.assertIn("large_island_job_index, nullptr", code)

    def test_stress_comparison_has_identical_geometry(self):
        script = STRESS.read_text(encoding="utf-8")
        runner = RUNNER.read_text(encoding="utf-8")
        workload = WORKLOAD.read_text(encoding="utf-8")
        for name in (
            "physics_large_island_3d_serial",
            "physics_large_island_3d_parallel",
            "physics_large_island_3d_priority",
            "physics_multi_island_3d_serial",
            "physics_multi_island_3d_parallel",
            "physics_multi_island_3d_two_large",
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
        self.assertIn("extra_islands: int = 0", workload)
        self.assertIn("for island_id in range(extra_islands)", workload)
        self.assertIn("for i in range(extra_island_size)", workload)
        self.assertIn("PhysicsServer3D.free_rid(joint)", workload)
        self.assertIn("LargeIsland3DStress.new().run(self, scale, frames, true, false, 20, 16)", script)
        self.assertIn("LargeIsland3DStress.new().run(self, scale, frames, true, false, 1, 320)", script)

    def test_runtime_regression_runs_all_modes(self):
        script = RUNTIME.read_text(encoding="utf-8")
        self.assertIn("[false, false, 20, 16]", script)
        self.assertIn("[true, false, 20, 16]", script)
        self.assertIn("[true, true, 20, 16]", script)
        self.assertIn("[true, false, 1, 320]", script)
        self.assertIn("await LargeIsland3DStress.new().run(", script)
        self.assertIn("result.has(\"error\")", script)
        self.assertIn('int(result["joints"]) < 256', script)


if __name__ == "__main__":
    unittest.main()
