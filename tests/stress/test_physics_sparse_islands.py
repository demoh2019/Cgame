"""Source and workload contracts for low-RAM sparse physics islands."""
import unittest
from pathlib import Path

import run


ROOT = Path(__file__).resolve().parents[2]
STRESS = Path(__file__).parent / "stress.gd"


class SparsePhysicsIslandTests(unittest.TestCase):
    def test_physics_steppers_do_not_preallocate_512_slots_per_island(self):
        for dimension in ("2d", "3d"):
            path = ROOT / "modules" / f"godot_physics_{dimension}" / f"godot_step_{dimension}.cpp"
            source = path.read_text(encoding="utf-8")
            with self.subTest(dimension=dimension):
                self.assertNotIn("body_island.reserve(BODY_ISLAND_SIZE_RESERVE)", source)
                self.assertNotIn("constraint_island.reserve(ISLAND_SIZE_RESERVE)", source)
                self.assertNotIn("#define BODY_ISLAND_SIZE_RESERVE 512", source)
                self.assertNotIn("#define ISLAND_SIZE_RESERVE 512", source)
                self.assertIn("body_island.clear()", source)
                self.assertIn("constraint_island.clear()", source)

    def test_physics_step_avoids_worker_pool_for_zero_or_one_work_item(self):
        """No lock/group/task allocation for idle steps or one-item batches."""
        for dimension in ("2d", "3d"):
            source = (
                ROOT / "modules" / f"godot_physics_{dimension}" /
                f"godot_step_{dimension}.cpp"
            ).read_text(encoding="utf-8")
            with self.subTest(dimension=dimension):
                self.assertIn("if (total_constraint_count == 1)", source)
                self.assertIn("_setup_constraint(0, nullptr);", source)
                self.assertIn("else if (total_constraint_count > 1)", source)
                self.assertIn("if (island_count == 1)", source)
                self.assertIn("_solve_island(0, nullptr);", source)
                self.assertIn("else if (island_count > 1)", source)
                # At least two independent islands still use the parallel path.
                self.assertIn("add_template_group_task", source)
                self.assertIn("wait_for_group_task_completion(group_task)", source)

    def test_sparse_scenarios_are_registered_and_measure_physics(self):
        script = STRESS.read_text(encoding="utf-8")
        for dimension in ("2d", "3d"):
            case = f"physics_sparse_{dimension}"
            with self.subTest(case=case):
                self.assertIn(case, run.CASES)
                self.assertIn(f'func _{case}(scale: int, frames: int)', script)
                self.assertIn(f'"{case}":', script)
                self.assertIn("peak_physics_ms", script)
                self.assertIn("peak_collision_pairs", script)
                self.assertIn("frame_p95_ms", script)
                self.assertIn(case, run.choose_cases([case], "headless"))


if __name__ == "__main__":
    unittest.main()
