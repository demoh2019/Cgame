"""Source contracts and mathematical batching checks for 3D large islands.

The C++ graph-color solver runs one worker task for a contiguous batch of
same-color constraints. Pure Python verifies coverage and non-overlapping
indices; an engine build and physics runtime regression are still required.
"""

import random
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
STEP_3D = ROOT / "modules/godot_physics_3d/godot_step_3d.cpp"
HEADER_3D = ROOT / "modules/godot_physics_3d/godot_step_3d.h"
STEP_2D = ROOT / "modules/godot_physics_2d/godot_step_2d.cpp"


def partition(color_count, worker_count):
    # C++ uses ceil(count / target_tasks), clamped to a minimum of eight.
    target_tasks = min(max(worker_count, 1), 32) * 4
    batch_size = max(8, color_count // target_tasks + int(color_count % target_tasks != 0))
    task_count = color_count // batch_size + int(color_count % batch_size != 0)
    return [
        (i * batch_size, min((i + 1) * batch_size, color_count))
        for i in range(task_count)
    ]

class LargeIslandBatchContracts(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.source = STEP_3D.read_text(encoding="utf-8")
        cls.header = HEADER_3D.read_text(encoding="utf-8")
        cls.source_2d = STEP_2D.read_text(encoding="utf-8")
        start = cls.source.index("void GodotStep3D::_solve_colored_constraint(")
        stop = cls.source.index("bool GodotStep3D::_solve_large_island(", start)
        cls.callback = cls.source[start:stop]
        start = stop
        stop = cls.source.index("void GodotStep3D::_check_suspend(", start)
        cls.coloring = cls.source[start:stop]

    def test_3d_and_2d_use_identical_worker_aware_adaptive_chunks(self):
        for source in (self.source, self.source_2d):
            self.assertIn("static constexpr uint32_t MIN_PARALLEL_COLOR_BATCH_SIZE = 8;", source)
            self.assertIn("const uint32_t target_tasks = MIN(worker_count, uint32_t(32)) * 4;", source)
            self.assertIn("const uint32_t desired_batch_size = count / target_tasks + uint32_t(count % target_tasks != 0);", source)
            self.assertIn("const uint32_t task_count = count / color_batch_size + uint32_t(count % color_batch_size != 0);", source)
            self.assertIn("&& worker_count > 1)", source)
            self.assertIn("nullptr, task_count, -1, true,", source)
        for header in (self.header, HEADER_3D.read_text(encoding="utf-8")):
            self.assertIn("uint32_t color_batch_size = 8;", header)
        self.assertIn("get_thread_count()", self.callback)

    def test_worker_callback_bounds_last_partial_chunk(self):
        self.assertIn("const uint32_t first = p_constraint_index * color_batch_size;", self.callback)
        self.assertIn("first + MIN(color_batch_size, color_batch_count - first)", self.callback)
        self.assertIn("for (uint32_t i = first; i < end; ++i)", self.callback)
        self.assertIn("colored_constraints[color_batch_offset + i]->solve(delta);", self.callback)

    def test_sequential_and_parallel_ranges_do_not_overlap(self):
        self.assertIn("color_batch_offset = start;", self.coloring)
        self.assertIn("color_batch_count = count;", self.coloring)
        self.assertIn("if (color != MAX_LARGE_ISLAND_COLORS && count >= MIN_PARALLEL_COLOR_CONSTRAINTS && worker_count > 1)", self.coloring)
        self.assertIn("wait_for_group_task_completion(group);", self.coloring)
        self.assertIn("for (uint32_t i = start; i < start + count; ++i)", self.coloring)

    def test_temporary_hash_map_replaced_with_reused_member(self):
        self.assertIn("AHashMap<GodotBody3D *, uint32_t> occupied_colors;", self.header)
        self.assertIn("LocalVector<uint8_t> constraint_colors;", self.header)
        self.assertNotIn("AHashMap<GodotBody3D *, uint32_t> occupied_colors;", self.coloring)
        self.assertIn("occupied_colors.clear();", self.coloring)
        self.assertIn("constraint_colors.resize(constraint_count);", self.coloring)
        self.assertIn("occupied_colors.get_capacity()", self.coloring)
        self.assertIn("occupied_colors.reset();", self.source)

    def test_no_reused_memory_during_regular_island_dispatch(self):
        self.assertIn("large_island_count != 1", self.source)
        self.assertIn("colored_constraints.reset();", self.source)
        self.assertIn("constraint_colors.reset();", self.source)
        self.assertIn("deferred_large_island_index = large_island_index;", self.source)
        self.assertIn("wait_for_group_task_completion(group_task);", self.source)
        other_islands = self.source.index('SNAME("Physics3DOtherConstraintIslands")')
        other_islands_barrier = self.source.index("wait_for_group_task_completion(group_task);", other_islands)
        large_island_solver = self.source.index("if (!_solve_large_island(", other_islands)
        self.assertLess(other_islands_barrier, large_island_solver)

    def test_adaptive_groups_are_contiguous_bounded_and_complete(self):
        rng = random.Random(3847)
        sizes = [0, 1, 7, 8, 9, 63, 64, 65, 255, 256, 257, 4095, 4096, 4097]
        sizes += [rng.randrange(0, 100000) for _ in range(500)]
        sizes += [1_000_000, 2_147_483_647, 4_294_967_295]
        for count in sizes:
            for workers in (1, 2, 4, 8, 16, 32, 64, 256):
                with self.subTest(count=count, workers=workers):
                    batches = partition(count, workers)
                    self.assertLessEqual(len(batches), min(max(workers, 1), 32) * 4)
                    self.assertTrue(all(0 <= start < end <= count for start, end in batches))
                    self.assertEqual(sum(end - start for start, end in batches), count)
                    self.assertEqual(batches[0][0] if batches else 0, 0)
                    self.assertEqual(batches[-1][1] if batches else 0, count)
                    for index in range(1, len(batches)):
                        self.assertEqual(batches[index - 1][1], batches[index][0])


if __name__ == "__main__":
    unittest.main()
