"""Contract tests for bounded Jolt contact reporting scratch buffers.

The code is intentionally exercised by a native stress case in CI because these
source-level checks cannot validate real contact simulation or allocator RSS.
"""

from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[2]
LISTENER = ROOT / "modules/jolt_physics/spaces/jolt_contact_listener_3d.cpp"
RUNTIME = ROOT / "tests/stress/physics_jolt_contact_scratch_regression.gd"


def should_release(capacity: int, used: int, minimum: int) -> bool:
    """Reference model of the C++ high-water/slack rule (non-overflow inputs)."""
    return capacity > max(minimum, used * 4)


class JoltContactScratchContracts(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.code = LISTENER.read_text(encoding="utf-8")
        cls.contacts = cls.code.split(
            "void JoltContactListener3D::_flush_contacts() {", 1
        )[1].split("void JoltContactListener3D::_flush_area_body_events() {", 1)[0]
        cls.area = cls.code.split(
            "void JoltContactListener3D::_flush_area_body_events() {", 1
        )[1].split("void JoltContactListener3D::_dispatch_area_enter(", 1)[0]

    def test_shared_scratch_policy_preserves_steady_dense_workloads(self):
        s = self.code
        self.assertIn("MAX_CACHED_CONTACT_MANIFOLDS = 2048", s)
        self.assertIn("MAX_CACHED_CONTACT_PAIR_SLOTS = 4096", s)
        self.assertIn("MAX_CACHED_AREA_EVENTS = 2048", s)
        self.assertIn("r_buffer.get_capacity() > allowed_capacity", s)
        self.assertIn("r_buffer.reset();", s)
        self.assertIn("r_buffer.clear();", s)
        self.assertIn("used > UINT32_MAX / 4 ? UINT32_MAX : used * 4", s)

    def test_peak_capacity_released_after_contacts_become_quiet(self):
        self.assertIn("thread_local AHashMap<JPH::SubShapeIDPair, Manifold *, ShapePairHasher>", self.contacts)
        self.assertIn("used_manifold_pairs > UINT32_MAX / 4 ?", self.contacts)
        self.assertIn("deepest_manifolds.get_capacity() > allowed_pair_capacity", self.contacts)
        self.assertIn("deepest_manifolds.reset();", self.contacts)
        self.assertIn("deepest_manifolds.clear();", self.contacts)
        self.assertIn("clear_contact_scratch(tl.manifolds, MAX_CACHED_CONTACT_MANIFOLDS);", self.contacts)
        # Do not release while iterating over the manifolds!
        self.assertLess(
            self.contacts.index("for (const KeyValue<JPH::SubShapeIDPair"),
            self.contacts.index("deepest_manifolds.reset();"),
        )

    def test_events_are_not_dropped_before_dispatch(self):
        for event in ("area_enters", "area_exits", "area_soft_body_overlaps"):
            with self.subTest(event=event):
                self.assertIn(f"clear_contact_scratch(tl.{event}, MAX_CACHED_AREA_EVENTS);", self.area)
                self.assertNotIn(f"tl.{event}.clear();", self.area)
        self.assertIn("_dispatch_area_enter(shape_pair);", self.area)
        self.assertIn("_dispatch_area_exit(shape_pair);", self.area)
        # Persistent overlap tracking cannot be capped like temporary scratch.
        self.assertNotIn("area_overlaps.reset();", self.area)
        self.assertNotIn("area_soft_body_overlaps.reset();", self.area)

    def test_duplicate_area_exits_cannot_overflow_reservation(self):
        # Event callbacks can produce redundant exits after a subshape shift.
        # The estimate must remain signed and reserve only for growth.
        area = self.area
        self.assertIn("int64_t estimated_overlap_count = area_overlaps.size();", area)
        self.assertIn(
            "estimated_overlap_count += int64_t(tl.area_enters.size()) - int64_t(tl.area_exits.size());",
            area,
        )
        self.assertIn(
            "if (estimated_overlap_count > int64_t(area_overlaps.size())) {", area
        )
        self.assertIn(
            "area_overlaps.reserve(uint32_t(MIN(estimated_overlap_count, int64_t(UINT32_MAX))));",
            area,
        )
        self.assertNotIn("new_overlap_count -= tl.area_exits.size();", area)
        for active, enters, exits in (
            (0, 0, 1), (1, 0, 4), (1, 1, 6), (1, 2, 1),
            (1024, 4096, 8192), (4096, 8192, 32),
        ):
            expected = active + enters - exits
            self.assertGreaterEqual(min(max(0, expected), 2**32 - 1), 0)

    def test_persistent_high_water_mark_and_quiet_scene(self):
        for minimum in (2048, 4096):
            self.assertFalse(should_release(minimum * 2, minimum, minimum))
            self.assertFalse(should_release(minimum, 0, minimum))
            self.assertTrue(should_release(minimum * 8, 0, minimum))
            self.assertTrue(should_release(minimum * 8, 128, minimum))

    def test_runtime_stress_reports_contacts_then_quiets_scene(self):
        s = RUNTIME.read_text(encoding="utf-8")
        self.assertIn("const BODY_COUNT := 4096", s)
        self.assertIn("const KEEP_COUNT := 64", s)
        self.assertIn("PhysicsServer3D.body_set_max_contacts_reported(body, 4)", s)
        self.assertIn("for i in range(KEEP_COUNT, BODY_COUNT)", s)
        self.assertIn("await physics_frame", s)
        self.assertIn("JOLT_CONTACT_SCRATCH_RESULT:", s)
        self.assertIn("peak_pairs <= 0 or not quiet_transform.origin.is_finite()", s)


if __name__ == "__main__":
    unittest.main()
