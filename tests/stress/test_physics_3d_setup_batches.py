"""Reference and source contracts for low-overhead 3D constraint setup.

The algorithm remains identical for each individual constraint; the thread
pool now schedules contiguous 16-element chunks instead of single elements.
Run GodotPhysics3D's headless regressions for end-to-end coverage.
"""

from pathlib import Path
import random
import unittest

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "modules/godot_physics_3d/godot_step_3d.cpp"
HEADER = ROOT / "modules/godot_physics_3d/godot_step_3d.h"
BATCH_SIZE = 16
INLINE_LIMIT = 32


def setup_batches(total: int) -> list[range]:
    """Reference implementation of the C++ batch-index partition."""
    if total < INLINE_LIMIT:
        return [range(total)]
    count = (total + BATCH_SIZE - 1) // BATCH_SIZE
    return [
        range(index * BATCH_SIZE, min((index + 1) * BATCH_SIZE, total))
        for index in range(count)
    ]


class Physics3DSetupBatches(unittest.TestCase):
    def test_setup_uses_one_group_task_per_batch(self):
        source = SOURCE.read_text(encoding="utf-8")
        header = HEADER.read_text(encoding="utf-8")
        self.assertIn("static constexpr uint32_t PARALLEL_SETUP_BATCH_SIZE = 16;", source)
        self.assertIn("MIN_PARALLEL_SETUP_CONSTRAINTS = 32;", source)
        self.assertIn("void _setup_constraint_batch(", header)
        self.assertIn("void GodotStep3D::_setup_constraint_batch(", source)
        self.assertIn("const uint32_t begin = p_batch_index * PARALLEL_SETUP_BATCH_SIZE;", source)
        self.assertIn(
            "const uint32_t end = MIN(begin + PARALLEL_SETUP_BATCH_SIZE, all_constraints.size());",
            source,
        )
        self.assertIn("_setup_constraint(constraint_index, nullptr);", source)
        self.assertIn(
            "const uint32_t batch_count = (total_constraint_count + PARALLEL_SETUP_BATCH_SIZE - 1) / PARALLEL_SETUP_BATCH_SIZE;",
            source,
        )
        self.assertIn(
            "&GodotStep3D::_setup_constraint_batch, nullptr, batch_count",
            source,
        )
        self.assertNotIn(
            "&GodotStep3D::_setup_constraint, nullptr, total_constraint_count",
            source,
        )
        self.assertIn("wait_for_group_task_completion(group_task)", source)

    def test_every_constraint_is_prepared_once_without_empty_tasks(self):
        rng = random.Random(20261119)
        counts = list(range(0, 300)) + [rng.randint(1, 20000) for _ in range(500)]
        for count in counts:
            batches = setup_batches(count)
            covered = [index for batch in batches for index in batch]
            self.assertEqual(covered, list(range(count)), f"count={count}")
            if count < INLINE_LIMIT:
                self.assertEqual(len(batches), 1)
            else:
                self.assertEqual(len(batches), (count + BATCH_SIZE - 1) // BATCH_SIZE)
                self.assertTrue(all(0 < len(batch) <= BATCH_SIZE for batch in batches))

    def test_million_constraint_workload_has_no_overflow(self):
        total = 1_000_000
        batch_count = (total + BATCH_SIZE - 1) // BATCH_SIZE
        self.assertEqual(batch_count, 62500)
        self.assertEqual((batch_count - 1) * BATCH_SIZE, 999984)
        self.assertEqual(
            min(batch_count * BATCH_SIZE, total), total
        )
        self.assertLess(batch_count, total)

    def test_dense_3d_stress_still_available(self):
        runner = (ROOT / "tests/stress/run.py").read_text(encoding="utf-8")
        cases = (ROOT / "tests/stress/stress.gd").read_text(encoding="utf-8")
        self.assertIn('"physics_dense_3d"', runner)
        self.assertIn('"physics_dense_3d":', cases)


if __name__ == "__main__":
    unittest.main()
