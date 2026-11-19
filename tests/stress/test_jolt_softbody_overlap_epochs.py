"""Jolt soft-body sensor overlap regression contracts and a reference model.

Compare the epoch-based in-place overlap set to set semantics over randomized
repeated callbacks and bursty overlap churn. Native Jolt/soft-body execution
is tested separately in physics_jolt_softbody_area_overlap_regression.gd.
"""

from pathlib import Path
import random
import unittest


ROOT = Path(__file__).resolve().parents[2]
CPP = ROOT / "modules/jolt_physics/spaces/jolt_contact_listener_3d.cpp"
HEADER = ROOT / "modules/jolt_physics/spaces/jolt_contact_listener_3d.h"
STRESS = ROOT / "tests/stress/physics_jolt_softbody_area_overlap_regression.gd"


class EpochOverlapReference:
    """Unique shape pairs stamped with the last frame they were observed."""

    def __init__(self):
        self.pairs = {}
        self.epoch = 0
        self.scan_count = 0

    def step(self, callbacks):
        self.epoch = (self.epoch + 1) & 0xFFFFFFFF
        if self.epoch == 0:
            for pair in self.pairs:
                self.pairs[pair] = 0
            self.epoch = 1

        previous_count = len(self.pairs)
        persisting_count = 0
        entered = []
        for pair in callbacks:
            if pair in self.pairs:
                if self.pairs[pair] != self.epoch:
                    self.pairs[pair] = self.epoch
                    persisting_count += 1
            else:
                self.pairs[pair] = self.epoch
                entered.append(pair)

        exited = []
        if persisting_count < previous_count:
            self.scan_count += 1
            for pair in list(self.pairs):
                if self.pairs[pair] != self.epoch:
                    del self.pairs[pair]
                    exited.append(pair)
        return set(entered), set(exited)


class JoltSoftBodyOverlapEpochContracts(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.source = CPP.read_text(encoding="utf-8")
        cls.header = HEADER.read_text(encoding="utf-8")
        cls.method = cls.source.split(
            "void JoltContactListener3D::_flush_area_soft_body_events() {", 1
        )[1].split("\nvoid JoltContactListener3D::_dispatch_area_enter(", 1)[0]

    def test_generation_map_uses_open_addressing(self):
        self.assertIn(
            "AHashMap<JPH::SubShapeIDPair, uint32_t, ShapePairHasher> area_soft_body_overlaps;",
            self.header,
        )
        self.assertIn("uint32_t area_soft_body_overlap_epoch = 0;", self.header)
        self.assertIn("area_soft_body_overlaps.getptr(shape_pair)", self.method)
        self.assertIn("area_soft_body_overlaps.insert(shape_pair, area_soft_body_overlap_epoch);", self.method)
        self.assertNotIn("HashSet<JPH::SubShapeIDPair, ShapePairHasher> new_overlaps;", self.method)

    def test_once_per_step_generation_and_inplace_expiration(self):
        m = self.method
        self.assertIn("if (++area_soft_body_overlap_epoch == 0) {", m)
        self.assertIn("overlap.value = 0;", m)
        self.assertIn("area_soft_body_overlap_epoch = 1;", m)
        self.assertIn("if (*last_seen != area_soft_body_overlap_epoch) {", m)
        self.assertIn("++persisting_count;", m)
        self.assertIn("if (persisting_count < previous_count) {", m)
        self.assertIn("area_soft_body_overlaps.erase_by_index(index);", m)
        self.assertIn("_dispatch_area_enter(shape_pair);", m)
        self.assertIn("_dispatch_area_exit(exited_pair);", m)
        # The element moved into the removed index must still be inspected.
        self.assertLess(m.index("area_soft_body_overlaps.erase_by_index(index);"), m.index("} else {\n\t\t\t\t++index;"))
        self.assertIn("clear_contact_scratch(tl.area_soft_body_overlaps, MAX_CACHED_AREA_EVENTS);", m)

    def test_retain_steady_capacity_trim_shrink_and_full_empty(self):
        m = self.method
        self.assertIn("MIN_CACHED_SOFT_BODY_OVERLAP_SLOTS = 4096;", m)
        self.assertIn("live_count > UINT32_MAX / 4 ? UINT32_MAX : live_count * 4", m)
        self.assertIn("if (area_soft_body_overlaps.get_capacity() > target_capacity)", m)
        self.assertIn("if (live_count == 0) {", m)
        self.assertIn("area_soft_body_overlaps.reset();", m)
        self.assertIn("compacted.reserve(live_count + live_count / 2 + 1);", m)
        self.assertIn("area_soft_body_overlaps = std::move(compacted);", m)

    def test_duplicate_callbacks_do_not_generate_duplicate_events(self):
        sim = EpochOverlapReference()
        entered, exited = sim.step([1, 1, 1, 2, 2])
        self.assertEqual(entered, {1, 2})
        self.assertEqual(exited, set())
        entered, exited = sim.step([1, 1, 1, 1])
        self.assertEqual(entered, set())
        self.assertEqual(exited, {2})
        entered, exited = sim.step([1, 1, 1])
        self.assertEqual(entered, set())
        self.assertEqual(exited, set())
        entered, exited = sim.step([])
        self.assertEqual(entered, set())
        self.assertEqual(exited, {1})

    def test_stable_overlap_skips_expensive_scan(self):
        sim = EpochOverlapReference()
        sim.step([1, 2, 3])
        for _ in range(200):
            sim.step([3, 3, 2, 2, 1, 1])
        self.assertEqual(sim.scan_count, 0)
        self.assertEqual(set(sim.pairs), {1, 2, 3})

    def test_randomized_events_match_unique_set_difference(self):
        rng = random.Random(20261119)
        sim = EpochOverlapReference()
        previous = set()
        for _ in range(2000):
            active = set(rng.sample(range(400), rng.randrange(0, 100)))
            callbacks = [pair for pair in active for _ in range(rng.randint(1, 5))]
            rng.shuffle(callbacks)
            entered, exited = sim.step(callbacks)
            self.assertEqual(entered, active - previous)
            self.assertEqual(exited, previous - active)
            self.assertEqual(set(sim.pairs), active)
            previous = active

    def test_epoch_wrap_does_not_misclassify_existing_pairs(self):
        sim = EpochOverlapReference()
        sim.step(["old", "removed"])
        sim.epoch = 0xFFFFFFFE
        self.assertEqual(sim.step(["old"]), (set(), {"removed"}))
        # Overflow invalidates all old stamps, then marks live pairs again.
        self.assertEqual(sim.step(["old", "new"]), ({"new"}, set()))
        self.assertEqual(sim.pairs, {"old": 1, "new": 1})

    def test_native_fixture_tests_real_soft_body_sensor_cycles(self):
        gd = STRESS.read_text(encoding="utf-8")
        self.assertIn("const ROUNDS := 6", gd)
        self.assertIn("PhysicsServer3D.soft_body_create()", gd)
        self.assertIn("PhysicsServer3D.area_set_monitor_callback", gd)
        self.assertIn("PhysicsServer3D.AREA_BODY_ADDED", gd)
        self.assertIn("PhysicsServer3D.AREA_BODY_REMOVED", gd)
        self.assertIn("JOLT_SOFTBODY_AREA_OVERLAP_RESULT:", gd)
        self.assertIn("Jolt soft-body area overlap regression passed.", gd)


if __name__ == "__main__":
    unittest.main()
