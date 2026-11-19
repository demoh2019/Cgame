"""Reference and source contracts for low-overhead 3D constraint setup.

The algorithm remains identical for each individual constraint; the worker
pool now schedules adaptive contiguous chunks (at least 16 constraints) and
caps the number of worker tasks per setup stage.
Run GodotPhysics3D's headless regressions for end-to-end coverage.
"""

from pathlib import Path
import random
import unittest

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "modules/godot_physics_3d/godot_step_3d.cpp"
HEADER = ROOT / "modules/godot_physics_3d/godot_step_3d.h"
MIN_BATCH_SIZE = 16
INLINE_LIMIT = 32


def setup_batches(total: int, workers: int) -> list[range]:
    """Reference equivalent of the adaptive C++ setup planner."""
    if total <= 0:
        return []
    if total < INLINE_LIMIT or workers <= 1:
        return [range(total)]
    target_tasks = min(max(1, workers), 32) * 4
    desired_batch_size = total // target_tasks + int(total % target_tasks != 0)
    batch_size = max(MIN_BATCH_SIZE, desired_batch_size)
    batch_count = total // batch_size + int(total % batch_size != 0)
    return [
        range(i * batch_size, min((i + 1) * batch_size, total))
        for i in range(batch_count)
    ]

class Physics3DSetupBatches(unittest.TestCase):
    def test_setup_uses_adaptive_worker_batches(self):
        source = SOURCE.read_text(encoding="utf-8")
        header = HEADER.read_text(encoding="utf-8")
        for text in (
            "static constexpr uint32_t MIN_PARALLEL_SETUP_BATCH_SIZE = 16;",
            "const uint32_t begin = p_batch_index * setup_batch_size;",
            "begin + MIN(setup_batch_size, all_constraints.size() - begin)",
            "const uint32_t target_tasks = MIN(setup_workers, uint32_t(32)) * 4;",
            "const uint32_t desired_batch_size = total_constraint_count / target_tasks + uint32_t(total_constraint_count % target_tasks != 0);",
            "const uint32_t batch_count = total_constraint_count / setup_batch_size + uint32_t(total_constraint_count % setup_batch_size != 0);",
            "total_constraint_count < MIN_PARALLEL_SETUP_CONSTRAINTS || setup_workers == 1",
            "&GodotStep3D::_setup_constraint_batch, nullptr, batch_count",
            "setup_pool->wait_for_group_task_completion(group_task);",
        ):
            self.assertIn(text, source)
        self.assertIn("uint32_t setup_batch_size = 16;", header)

    def test_every_constraint_is_prepared_once_without_empty_tasks(self):
        rng = random.Random(20261119)
        counts = list(range(0, 300)) + [rng.randint(1, 20000) for _ in range(500)]
        for count in counts:
            for workers in (1, 2, 4, 8, 16, 32, 64, 256):
                batches = setup_batches(count, workers)
                if count == 0:
                    self.assertEqual(batches, [])
                    continue
                self.assertEqual(batches[0].start, 0)
                self.assertEqual(batches[-1].stop, count)
                self.assertEqual(sum(len(batch) for batch in batches), count)
                self.assertTrue(all(len(batch) > 0 for batch in batches))
                self.assertTrue(all(a.stop == b.start for a, b in zip(batches, batches[1:])))
                if count < INLINE_LIMIT or workers == 1:
                    self.assertEqual(len(batches), 1)
                else:
                    self.assertLessEqual(len(batches), min(workers, 32) * 4)

    def test_million_and_uint32_max_constraints_have_bounded_tasks(self):
        for count in (1_000_000, 2_147_483_647, 4_294_967_295):
            for workers in (2, 8, 32, 64):
                batches = setup_batches(count, workers)
                self.assertLessEqual(len(batches), min(workers, 32) * 4)
                self.assertEqual(sum(len(batch) for batch in batches), count)
                self.assertEqual(batches[-1].stop, count)

    def test_dense_3d_stress_still_available(self):
        runner = (ROOT / "tests/stress/run.py").read_text(encoding="utf-8")
        cases = (ROOT / "tests/stress/stress.gd").read_text(encoding="utf-8")
        self.assertIn('"physics_dense_3d"', runner)
        self.assertIn('"physics_dense_3d":', cases)


if __name__ == "__main__":
    unittest.main()
