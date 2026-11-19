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
