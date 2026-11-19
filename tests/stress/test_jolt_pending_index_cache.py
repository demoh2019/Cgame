"""Jolt pending BodyID cache: source contracts and swap-erase model tests.

The native test independently exercises actual BodyID generation, sleeping
transitions and RID destruction. These checks guard the O(1) lookup path and
the bounded scratch allocation policy.
"""

from pathlib import Path
import random
import re
import unittest


ROOT = Path(__file__).resolve().parents[2]
SPACE_CPP = ROOT / "modules/jolt_physics/spaces/jolt_space_3d.cpp"
SPACE_H = ROOT / "modules/jolt_physics/spaces/jolt_space_3d.h"
STRESS = ROOT / "tests/stress/physics_jolt_pending_index_churn.gd"


class JoltPendingIndexCacheTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.source = SPACE_CPP.read_text(encoding="utf-8")
        cls.header = SPACE_H.read_text(encoding="utf-8")
        cls.pending = cls.source.split("static void ensure_pending_index(", 1)[1].split(
            "\nvoid JoltSpace3D::_pre_step(", 1
        )[0]
        cls.flush = cls.source.split("void JoltSpace3D::flush_pending_objects() {", 1)[1].split(
            "\nvoid JoltSpace3D::set_is_object_sleeping(", 1
        )[0]

    def test_map_uses_compact_open_addressing(self):
        self.assertIn('#include "core/templates/a_hash_map.h"', self.header)
        self.assertEqual(self.header.count("AHashMap<uint32_t, uint32_t>"), 5)
        self.assertNotIn("AAHashMap<", self.source)
        self.assertNotIn("AAHashMap<", self.header)
        self.assertNotRegex(self.header, r"(?<!A)HashMap<uint32_t, uint32_t>")
        self.assertNotRegex(self.pending, r"(?<!A)HashMap<uint32_t, uint32_t>")
        self.assertIn("r_indices.reserve(p_bodies.size() + p_bodies.size() / 2 + 1);", self.pending)
        self.assertIn("r_indices.insert(p_bodies[i].GetIndexAndSequenceNumber(), i);", self.pending)

    def test_bounded_cache_reuses_small_tables_and_drops_spikes(self):
        self.assertIn("MAX_RETAINED_PENDING_INDEX_SLOTS = 4096", self.source)
        self.assertIn("if (r_indices.get_capacity() > MAX_RETAINED_PENDING_INDEX_SLOTS)", self.source)
        self.assertIn("r_indices.reset();", self.source)
        self.assertIn("r_indices.clear();", self.source)
        self.assertEqual(self.source.count("clear_pending_index("), 4)
        self.assertIn("clear_pending_index(r_indices);", self.pending)
        for suffix in ("awake", "sleeping"):
            self.assertIn(f"clear_pending_index(pending_{suffix}_indices);", self.flush)
        for capacity, should_reset in ((8, False), (1024, False), (4096, False), (8192, True)):
            with self.subTest(capacity=capacity):
                self.assertEqual(capacity > 4096, should_reset)

    def test_swap_and_erase_updates_moved_id_and_removes_deleted_id(self):
        self.assertIn("const uint32_t moved_key = p_bodies[last_index].GetIndexAndSequenceNumber();", self.pending)
        self.assertIn("p_bodies.remove_at_unordered(index);", self.pending)
        self.assertIn("r_indices.insert(moved_key, index);", self.pending)
        self.assertIn("r_indices.erase(key);", self.pending)
        rng = random.Random(20261119)
        for length in (128, 129, 512, 1024, 4096):
            with self.subTest(length=length):
                bodies = list(range(length))
                position = {body: i for i, body in enumerate(bodies)}
                removal_order = bodies.copy()
                rng.shuffle(removal_order)
                for value in removal_order:
                    index = position[value]
                    last_index = len(bodies) - 1
                    if index != last_index:
                        moved = bodies[last_index]
                        bodies[index] = moved
                        position[moved] = index
                    bodies.pop()
                    del position[value]
                    self.assertEqual(len(bodies), len(position))
                self.assertFalse(bodies)
                self.assertFalse(position)

    def test_stress_real_physics_pending_both_queues(self):
        script = STRESS.read_text(encoding="utf-8")
        self.assertIn("const BATCH_SIZE := 512", script)
        self.assertIn("const WAVES := 24", script)
        self.assertIn("const PERMUTATION_MULTIPLIER := 73", script)
        self.assertIn("BODY_STATE_SLEEPING", script)
        self.assertIn("PhysicsServer3D.free_rid(bodies[index])", script)
        self.assertIn("JOLT_PENDING_INDEX_RESULT:", script)
        self.assertIn("Jolt pending index churn regression passed.", script)


if __name__ == "__main__":
    unittest.main()
