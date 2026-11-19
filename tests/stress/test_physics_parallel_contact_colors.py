"""Conflict-safe coloring of contact-only large islands in GodotPhysics.

Structural contracts test that the C++ fast path is limited to rigid contact
pairs. A small Python graph-coloring reference checks the conflict invariant.
Run the engine-level physics regression separately for actual runtime behavior.
"""

from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[2]
MAX_COLORS = 16
MIN_PARALLEL_GROUP = 64


def color_constraints(constraints, contact_only):
    """Reference: graph colors are exclusive on bodies that can be written."""
    occupied = {}
    colors = []
    for a, b in constraints:
        writable = tuple(
            body for body in (a, b)
            if not (contact_only and body == "static-floor")
        )
        forbidden = 0
        for body in writable:
            forbidden |= occupied.get(body, 0)
        selected = next(
            (color for color in range(MAX_COLORS)
             if not (forbidden & (1 << color))),
            MAX_COLORS,
        )
        if selected < MAX_COLORS:
            for body in writable:
                occupied[body] = occupied.get(body, 0) | (1 << selected)
        colors.append(selected)
    return colors


class ParallelContactColorsContracts(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.source = {}
        for dim in ("2d", "3d"):
            prefix = ROOT / "modules" / ("godot_physics_" + dim)
            step = (prefix / ("godot_step_" + dim + ".cpp")).read_text(encoding="utf-8")
            cls.source[dim] = {
                "step": step,
                "constraint": (prefix / ("godot_constraint_" + dim + ".h")).read_text(encoding="utf-8"),
                "pair": (prefix / ("godot_body_pair_" + dim + ".h")).read_text(encoding="utf-8"),
            }

    def test_only_rigid_contact_pair_opted_in(self):
        for dim, source in self.source.items():
            with self.subTest(dim=dim):
                self.assertIn("virtual bool permits_parallel_immovable_body_sharing() const { return false; }", source["constraint"])
                self.assertIn("virtual bool permits_parallel_immovable_body_sharing() const override { return true; }", source["pair"])
                self.assertEqual(source["pair"].count("permits_parallel_immovable_body_sharing"), 1)

    def test_whole_island_must_be_contact_only(self):
        for dim, source in self.source.items():
            with self.subTest(dim=dim):
                step = source["step"]
                self.assertIn("bool contact_only_island = true;", step)
                self.assertIn("!p_constraint_island[i]->permits_parallel_immovable_body_sharing()", step)
                self.assertIn("contact_only_island = false;", step)
                self.assertLess(step.index("bool contact_only_island = true;"),
                                step.index("occupied_colors;"))

    def test_coloring_skips_immovable_bodies_only_for_contact_islands(self):
        for dim, source in self.source.items():
            with self.subTest(dim=dim):
                step = source["step"]
                mode = "PS" + dim.upper() + "E::BODY_MODE_KINEMATIC"
                self.assertIn("(!contact_only_island || body->get_mode() > " + mode + ")", step)
                if dim == "2d":
                    self.assertIn("(contact_only_island && body->get_mode() <= " + mode + ")", step)

    def test_worker_barrier_and_serial_overflow_are_preserved(self):
        for dim, source in self.source.items():
            with self.subTest(dim=dim):
                step = source["step"]
                self.assertIn("wait_for_group_task_completion(group)", step)
                self.assertIn("color != MAX_LARGE_ISLAND_COLORS", step)
                self.assertIn("colored_constraints[i]->solve(delta);", step)

    def test_contact_only_floor_increases_parallelizable_batches(self):
        edges = [("static-floor", i) for i in range(300)]
        edges += [(i, i + 1) for i in range(299)]
        shared_colors = color_constraints(edges, contact_only=True)
        conservative_colors = color_constraints(edges, contact_only=False)
        shared_colored = sum(color < MAX_COLORS for color in shared_colors)
        conservative_colored = sum(color < MAX_COLORS for color in conservative_colors)
        self.assertGreater(shared_colored, conservative_colored)
        self.assertGreater(sum(color == 0 for color in shared_colors), MIN_PARALLEL_GROUP)
        # No dynamic body can occur twice inside the same colored batch.
        for color in range(MAX_COLORS):
            seen = set()
            for edge, assigned_color in zip(edges, shared_colors):
                if assigned_color != color:
                    continue
                for body in edge:
                    if body == "static-floor":
                        continue
                    self.assertNotIn(body, seen)
                    seen.add(body)

    def test_mixed_joint_island_preserves_static_ownership(self):
        edges = [("static-floor", i) for i in range(300)]
        assignments = color_constraints(edges, contact_only=False)
        # A static floor must be exclusive in a mixed island.
        self.assertEqual(assignments[:MAX_COLORS], list(range(MAX_COLORS)))
        self.assertTrue(all(color == MAX_COLORS for color in assignments[MAX_COLORS:]))


if __name__ == "__main__":
    unittest.main()
