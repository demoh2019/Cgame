"""Reference invariants for the experimental 2D graph-colored island solver.

This checks the graph-coloring and batched-dispatch mathematics, not the
compiled Godot implementation. Run the GDScript regression for end-to-end
solver correctness and use ASan/TSan builds for concurrent memory safety.
"""

from __future__ import annotations

import random
import unittest


MAX_COLORS = 16
MIN_BATCH_SIZE = 8
MIN_PARALLEL_COLOR_CONSTRAINTS = 64
MAX_WORKER_TASKS = 128


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


def parallel_color_ranges(count: int, worker_count: int) -> list[range]:
    """Mirror C++ worker-aware chunk sizing; the caller handles the serial path.

    The executor uses one worker task per range. A group is only dispatched
    when count >= 64 and worker_count > 1.
    """
    if count == 0:
        return []
    workers = max(1, worker_count)
    target_tasks = min(workers, 32) * 4
    target_batch_size = count // target_tasks + int(count % target_tasks != 0)
    batch_size = max(MIN_BATCH_SIZE, target_batch_size)
    number_of_tasks = count // batch_size + int(count % batch_size != 0)
    return [
        range(i * batch_size, min((i + 1) * batch_size, count))
        for i in range(number_of_tasks)
    ]


def is_parallel_color(count: int, worker_count: int, color: int = 0) -> bool:
    """Overflow remains serial even on high core-count machines."""
    return color != MAX_COLORS and count >= MIN_PARALLEL_COLOR_CONSTRAINTS and worker_count > 1


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

    def test_adaptive_batch_coverage_and_worker_limits(self) -> None:
        # Includes the one-thread serial fallback and machines with far
        # more logical cores than the capped task scheduler.
        for worker_count in (1, 2, 4, 8, 16, 32, 64, 256):
            for count in range(0, 2049):
                ranges = parallel_color_ranges(count, worker_count)
                if count == 0:
                    self.assertEqual(ranges, [])
                    continue
                self.assertEqual(ranges[0].start, 0)
                self.assertEqual(ranges[-1].stop, count)
                self.assertLessEqual(len(ranges), min(max(1, worker_count), 32) * 4)
                self.assertTrue(all(0 < len(part) for part in ranges))
                self.assertTrue(all(left.stop == right.start for left, right in zip(ranges, ranges[1:])))
                self.assertFalse(is_parallel_color(count, 1))
                self.assertFalse(is_parallel_color(count, worker_count, color=MAX_COLORS))
                if worker_count > 1 and count >= MIN_PARALLEL_COLOR_CONSTRAINTS:
                    self.assertTrue(is_parallel_color(count, worker_count))

    def test_large_color_limits_task_count_without_32bit_overflow(self) -> None:
        for count in (10_000, 1_000_000, 2_147_483_647, 4_294_967_295):
            for worker_count in (2, 8, 24, 128):
                ranges = parallel_color_ranges(count, worker_count)
                self.assertLessEqual(len(ranges), min(worker_count, 32) * 4)
                self.assertEqual(ranges[0].start, 0)
                self.assertEqual(ranges[-1].stop, count)
                self.assertTrue(all(b.start < b.stop for b in ranges))
                self.assertTrue(all(a.stop == b.start for a, b in zip(ranges, ranges[1:])))

    def test_color_waves_do_not_require_parallel_overflow(self) -> None:
        self.assertFalse(is_parallel_color(500_000, 32, color=MAX_COLORS))
        self.assertFalse(is_parallel_color(63, 32))
        self.assertTrue(is_parallel_color(64, 2))


if __name__ == "__main__":
    unittest.main()
