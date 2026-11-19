"""Reference invariants for the experimental 2D graph-colored island solver.

This checks the graph-coloring and batched-dispatch mathematics, not the
compiled Godot implementation. Run the GDScript regression for end-to-end
solver correctness and use ASan/TSan builds for concurrent memory safety.
"""

from __future__ import annotations

import random
import unittest


MAX_COLORS = 16
BATCH_SIZE = 8


def assign_colors(constraints: list[tuple[int, ...]]) -> list[int]:
    """Reference equivalent of the greedy color mask in godot_step_2d.cpp."""
    occupied_masks: dict[int, int] = {}
    assigned: list[int] = []
    for bodies in constraints:
        forbidden = 0
        for body in bodies:
            forbidden |= occupied_masks.get(body, 0)
        color = next(
            (c for c in range(MAX_COLORS) if not forbidden & (1 << c)),
            MAX_COLORS,
        )
        if not bodies:
            color = MAX_COLORS
        if color < MAX_COLORS:
            for body in bodies:
                occupied_masks[body] = occupied_masks.get(body, 0) | (1 << color)
        assigned.append(color)
    return assigned


def batch_indices(count: int) -> list[list[int]]:
    """Mirror the C++ 8-constraint contiguous group-task partition."""
    tasks = (count + BATCH_SIZE - 1) // BATCH_SIZE
    return [
        list(range(task * BATCH_SIZE, min((task + 1) * BATCH_SIZE, count)))
        for task in range(tasks)
    ]


class ColoringTests(unittest.TestCase):
    def test_random_graphs_are_race_free_within_each_color(self) -> None:
        rng = random.Random(20261119)
        for _ in range(350):
            body_count = rng.randint(2, 128)
            constraints = [
                tuple(rng.sample(range(body_count), rng.randint(1, min(4, body_count))))
                for _ in range(rng.randint(1, 450))
            ]
            colors = assign_colors(constraints)
            self.assertEqual(len(colors), len(constraints))
            for color in range(MAX_COLORS):
                touched: set[int] = set()
                for constraint, assigned in zip(constraints, colors):
                    if assigned != color:
                        continue
                    self.assertTrue(touched.isdisjoint(constraint))
                    touched.update(constraint)
            self.assertTrue(all(0 <= c <= MAX_COLORS for c in colors))

    def test_high_degree_body_uses_serial_overflow(self) -> None:
        constraints = [(0, i) for i in range(1, 120)]
        colors = assign_colors(constraints)
        self.assertEqual(colors[:MAX_COLORS], list(range(MAX_COLORS)))
        self.assertTrue(all(c == MAX_COLORS for c in colors[MAX_COLORS:]))

    def test_chain_can_be_colored_into_two_groups(self) -> None:
        constraints = [(i, i + 1) for i in range(383)]
        colors = assign_colors(constraints)
        self.assertEqual(set(colors), {0, 1})
        self.assertGreaterEqual(colors.count(0), 64)
        self.assertGreaterEqual(colors.count(1), 64)

    def test_batched_worker_coverage_has_no_overlap(self) -> None:
        for count in range(0, 4097):
            batches = batch_indices(count)
            self.assertEqual([i for batch in batches for i in batch], list(range(count)))
            self.assertTrue(all(0 < len(batch) <= BATCH_SIZE for batch in batches))
            self.assertEqual(len(batches), (count + BATCH_SIZE - 1) // BATCH_SIZE)


if __name__ == "__main__":
    unittest.main()
