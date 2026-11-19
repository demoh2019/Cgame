"""Source and reference contracts for batched GodotPhysics2D constraint setup.

This ensures that the new worker-aware setup planner covers each constraint
exactly once and never creates enormous task lists, including at UINT32_MAX.
C++ compilation and physical regression tests remain necessary.
"""

from pathlib import Path
import random
import unittest

ROOT = Path(__file__).resolve().parents[2]
SOURCE_2D = ROOT / "modules/godot_physics_2d/godot_step_2d.cpp"
HEADER_2D = ROOT / "modules/godot_physics_2d/godot_step_2d.h"
SOURCE_3D = ROOT / "modules/godot_physics_3d/godot_step_3d.cpp"
MIN_SETUP_BATCH = 16
MIN_PARALLEL_SETUP = 32


def ranges_for_setup(count: int, threads: int) -> list[range]:
    if count <= 0:
        return []
    if count < MIN_PARALLEL_SETUP or threads <= 1:
        return [range(count)]
    target_tasks = min(max(threads, 1), 32) * 4
    desired_size = count // target_tasks + int(count % target_tasks != 0)
    batch_size = max(MIN_SETUP_BATCH, desired_size)
    task_count = count // batch_size + int(count % batch_size != 0)
    return [
        range(index * batch_size, min((index + 1) * batch_size, count))
        for index in range(task_count)
    ]


class SetupBatchTests(unittest.TestCase):
    def test_source_contract_matches_3d(self) -> None:
        src2d = SOURCE_2D.read_text(encoding="utf-8")
        src3d = SOURCE_3D.read_text(encoding="utf-8")
        header = HEADER_2D.read_text(encoding="utf-8")
        for source in (src2d, src3d):
            for text in (
                "static constexpr uint32_t MIN_PARALLEL_SETUP_BATCH_SIZE = 16;",
                "const uint32_t target_tasks = MIN(setup_workers, uint32_t(32)) * 4;",
                "const uint32_t desired_batch_size = total_constraint_count / target_tasks + uint32_t(total_constraint_count % target_tasks != 0);",
                "const uint32_t batch_count = total_constraint_count / setup_batch_size + uint32_t(total_constraint_count % setup_batch_size != 0);",
                "total_constraint_count < MIN_PARALLEL_SETUP_CONSTRAINTS || setup_workers == 1",
            ):
                self.assertIn(text, source)
        self.assertIn("uint32_t setup_batch_size = 16;", header)
        self.assertIn("void _setup_constraint_batch(", header)
        self.assertIn("const uint32_t first = p_batch_index * setup_batch_size;", src2d)
        self.assertIn("first + MIN(setup_batch_size, all_constraints.size() - first)", src2d)
        self.assertIn("&GodotStep2D::_setup_constraint_batch, nullptr, batch_count", src2d)
        self.assertIn("setup_pool->wait_for_group_task_completion(group_task)", src2d)

    def test_random_worker_sizes_cover_all_indices_once(self) -> None:
        rng = random.Random(20261119)
        counts = list(range(0, 400)) + [rng.randrange(1, 30_000) for _ in range(500)]
        for count in counts:
            for workers in (1, 2, 4, 8, 16, 32, 64, 256):
                batches = ranges_for_setup(count, workers)
                if count == 0:
                    self.assertFalse(batches)
                    continue
                self.assertEqual(batches[0].start, 0)
                self.assertEqual(batches[-1].stop, count)
                self.assertEqual(sum(len(batch) for batch in batches), count)
                self.assertTrue(all(a.stop == b.start for a, b in zip(batches, batches[1:])))
                self.assertTrue(all(len(batch) > 0 for batch in batches))
                if count < MIN_PARALLEL_SETUP or workers == 1:
                    self.assertEqual(len(batches), 1)
                else:
                    self.assertLessEqual(len(batches), min(workers, 32) * 4)

    def test_large_counts_and_32bit_edges(self) -> None:
        for count in (1_000_000, 2_147_483_647, 4_294_967_295):
            for workers in (2, 8, 16, 32, 64):
                batches = ranges_for_setup(count, workers)
                self.assertLessEqual(len(batches), min(workers, 32) * 4)
                self.assertEqual(batches[0].start, 0)
                self.assertEqual(batches[-1].stop, count)
                self.assertEqual(sum(len(part) for part in batches), count)


if __name__ == "__main__":
    unittest.main()
