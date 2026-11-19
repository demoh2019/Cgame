"""Guard GodotPhysics island traversal against recursive-stack regressions."""

from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[2]


class IterativePhysicsIslandsContracts(unittest.TestCase):
    def _source(self, dim: str):
        base = ROOT / "modules" / f"godot_physics_{dim}"
        return (
            (base / f"godot_step_{dim}.cpp").read_text(encoding="utf-8"),
            (base / f"godot_step_{dim}.h").read_text(encoding="utf-8"),
        )

    def test_2d_flood_fill_uses_reusable_frontier_without_recursive_calls(self):
        cpp, header = self._source("2d")
        begin = cpp.index("void GodotStep2D::_populate_island(")
        end = cpp.index("void GodotStep2D::_setup_constraint(", begin)
        routine = cpp[begin:end]
        self.assertIn("LocalVector<GodotBody2D *> pending_bodies;", header)
        self.assertIn("pending_bodies.clear();", routine)
        self.assertIn("pending_bodies.remove_at(pending_bodies.size() - 1);", routine)
        self.assertIn("other_body->set_island_step(_step);", routine)
        self.assertNotIn("_populate_island(other_body", routine)

    def test_3d_flood_fill_handles_rigid_and_soft_body_without_recursion(self):
        cpp, header = self._source("3d")
        begin = cpp.index("void GodotStep3D::_populate_island_graph(")
        end = cpp.index("void GodotStep3D::_setup_constraint(", begin)
        routine = cpp[begin:end]
        self.assertIn("LocalVector<IslandTask> pending_island_tasks;", header)
        self.assertIn("task.soft_body->get_constraints()", routine)
        self.assertIn("constraint->get_soft_body_count()", routine)
        self.assertIn("pending_island_tasks.remove_at(", routine)
        self.assertIn("other->set_island_step(_step);", routine)
        self.assertNotIn("_populate_island(other", routine)
        self.assertNotIn("_populate_island_soft_body(other", routine)

    def test_joint_chain_cases_registered(self):
        import run
        stress_source = (Path(__file__).resolve().parent / "stress.gd").read_text(encoding="utf-8")
        for dim in ("2d", "3d"):
            name = f"physics_joint_chain_{dim}"
            with self.subTest(dim=dim):
                self.assertIn(name, run.CASES)
                self.assertIn(f"func _{name}(", stress_source)
                self.assertIn(f'"{name}":', stress_source)

    def test_stacks_mark_visits_before_queueing(self):
        for dim in ("2d", "3d"):
            cpp, _ = self._source(dim)
            with self.subTest(dim=dim):
                self.assertRegex(
                    cpp, r"other(?:_body)?->set_island_step\(_step\);\s+pending_",
                )


if __name__ == "__main__":
    unittest.main()
