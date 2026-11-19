"""Jolt Area3D: buffered rigid-body overlap transitions are idempotent.

Box2D's sensor events are merged after the parallel world step. This model
guards Cgame's equivalent Jolt event flush: duplicate begin/end callbacks
must not cause extra engine events or inflated per-subshape refcounts.
"""

from pathlib import Path
import random
import unittest


ROOT = Path(__file__).resolve().parents[2]
LISTENER = ROOT / "modules/jolt_physics/spaces/jolt_contact_listener_3d.cpp"
AREA_CPP = ROOT / "modules/jolt_physics/objects/jolt_area_3d.cpp"
HASH_SET_H = ROOT / "core/templates/hash_set.h"
RUNTIME = ROOT / "tests/stress/physics_jolt_area_event_dedup_regression.gd"


def flush_merged_events(live, exits, enters):
    """Apply Jolt exit-before-enter event batches, discarding duplicates."""
    emitted = []
    for pair in exits:
        if pair in live:
            live.remove(pair)
            emitted.append(("exit", pair))
    for pair in enters:
        if pair not in live:
            live.add(pair)
            emitted.append(("enter", pair))
    return emitted


def update_shape_pairs(live, additions, removals):
    """Model JoltArea3D::_add_shape_pair/_remove_shape_pair refcount input."""
    entered = []
    exited = []
    for pair in additions:
        if pair not in live:
            live.add(pair)
            entered.append(pair)
    for pair in removals:
        if pair in live:
            live.remove(pair)
            exited.append(pair)
    return entered, exited


class JoltAreaEventDedupTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.listener = LISTENER.read_text(encoding="utf-8")
        cls.area = AREA_CPP.read_text(encoding="utf-8")
        cls.hash_set = HASH_SET_H.read_text(encoding="utf-8")
        cls.body_flush = cls.listener.split(
            "void JoltContactListener3D::_flush_area_body_events() {", 1
        )[1].split("\nvoid JoltContactListener3D::_flush_area_soft_body_events()", 1)[0]
        cls.add = cls.area.split(
            "void JoltArea3D::_add_shape_pair(", 1
        )[1].split("\nbool JoltArea3D::_remove_shape_pair(", 1)[0]
        cls.remove = cls.area.split(
            "bool JoltArea3D::_remove_shape_pair(", 1
        )[1].split("\nvoid JoltArea3D::_flush_events(", 1)[0]

    def test_exit_dispatch_requires_stored_overlap(self):
        body = self.body_flush
        self.assertIn("if (area_overlaps.erase(shape_pair)) {", body)
        self.assertIn("_dispatch_area_exit(shape_pair);", body)
        self.assertLess(body.index("area_overlaps.erase(shape_pair)"), body.index("_dispatch_area_exit(shape_pair)"))
        self.assertIn("bool erase(const TKey &p_key) {", self.hash_set)

    def test_enter_dispatch_requires_new_overlap(self):
        body = self.body_flush
        self.assertIn("if (!area_overlaps.has(shape_pair)) {", body)
        self.assertIn("area_overlaps.insert(shape_pair);", body)
        self.assertIn("_dispatch_area_enter(shape_pair);", body)
        self.assertLess(body.index("area_overlaps.has(shape_pair)"), body.index("_dispatch_area_enter(shape_pair)"))
        self.assertIn("if (estimated_overlap_count > int64_t(area_overlaps.size()))", body)

    def test_exits_precede_enters_for_subshape_replacement(self):
        body = self.body_flush
        self.assertLess(body.index("for (const JPH::SubShapeIDPair &shape_pair : tl.area_exits)"),
                        body.index("for (const JPH::SubShapeIDPair &shape_pair : tl.area_enters)"))
        live = {99}
        self.assertEqual(flush_merged_events(live, [99, 99], [99, 99]),
                         [("exit", 99), ("enter", 99)])
        self.assertEqual(live, {99})

    def test_duplicate_shape_id_pair_is_not_added_to_refcounts_twice(self):
        add = self.add
        self.assertIn("const ShapeIDPair shape_id_pair(", add)
        self.assertIn("if (p_overlap.shape_pairs.has(shape_id_pair)) {", add)
        self.assertIn("return;", add)
        self.assertIn("p_overlap.shape_pairs.insert(shape_id_pair, shape_indices);", add)
        self.assertIn("p_overlap.pending_added.push_back(shape_indices);", add)
        self.assertLess(add.index("if (p_overlap.shape_pairs.has(shape_id_pair))"), add.index("pending_added.push_back"))
        self.assertIn("p_overlap.pending_removed.push_back(shape_pair->value);", self.remove)

    def test_repeated_begin_end_reports_yield_exactly_one_event(self):
        live = set()
        self.assertEqual(flush_merged_events(live, [], [1, 1, 1, 2, 2]),
                         [("enter", 1), ("enter", 2)])
        self.assertEqual(flush_merged_events(live, [], [1, 1, 2]), [])
        self.assertEqual(flush_merged_events(live, [1, 1, 2, 2], []),
                         [("exit", 1), ("exit", 2)])
        self.assertEqual(flush_merged_events(live, [1, 2], []), [])
        self.assertFalse(live)

    def test_shape_refcounts_remain_balanced_across_redundant_contact_callbacks(self):
        live = set()
        a, b = update_shape_pairs(live, [3, 3, 3, 5, 5], [])
        self.assertEqual(a, [3, 5])
        self.assertEqual(b, [])
        a, b = update_shape_pairs(live, [3, 5], [3, 3, 5, 5])
        self.assertEqual(a, [])
        self.assertEqual(b, [3, 5])
        self.assertFalse(live)

    def test_10000_randomized_batches_preserve_event_set_semantics(self):
        rng = random.Random(20261119)
        live = set()
        for _ in range(10000):
            before = live.copy()
            exits = [rng.randrange(80) for _ in range(rng.randrange(13))]
            enters = [rng.randrange(80) for _ in range(rng.randrange(13))]
            events = flush_merged_events(live, exits, enters)
            expected = (before - set(exits)) | set(enters)
            self.assertEqual(live, expected)
            self.assertEqual(len(events), len(set(events)))
            self.assertEqual(len([p for kind, p in events if kind == "exit"]),
                             len(before & set(exits)))
            self.assertEqual(len([p for kind, p in events if kind == "enter"]),
                             len(set(enters) - (before - set(exits))))

    def test_native_multi_subshape_fixture_and_cleanup(self):
        gd = RUNTIME.read_text(encoding="utf-8")
        self.assertIn("const SHAPE_COUNT := 8", gd)
        self.assertIn("const WAVES := 4", gd)
        self.assertIn("PhysicsServer3D.area_add_shape(area, area_shape", gd)
        self.assertIn("PhysicsServer3D.AREA_BODY_ADDED", gd)
        self.assertIn("PhysicsServer3D.AREA_BODY_REMOVED", gd)
        self.assertIn("invalid_events.is_empty()", gd)
        self.assertIn("JOLT_AREA_EVENT_DEDUP_RESULT:", gd)
        self.assertIn("Jolt rigid Area3D event dedup regression passed.", gd)


if __name__ == "__main__":
    unittest.main()
