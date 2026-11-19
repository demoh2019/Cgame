"""Source and regression contracts for Jolt's PhysicsServer3D process metrics.

The native fixture asserts active/contact counts across a dense frame and
their reset after body destruction. This source test checks the zero-hot-lock
design and that Jolt body stats are not scanned on each step.
"""

from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
SERVER_CPP = ROOT / "modules/jolt_physics/jolt_physics_server_3d.cpp"
SERVER_H = ROOT / "modules/jolt_physics/jolt_physics_server_3d.h"
SPACE_CPP = ROOT / "modules/jolt_physics/spaces/jolt_space_3d.cpp"
SPACE_H = ROOT / "modules/jolt_physics/spaces/jolt_space_3d.h"
CONTACT_CPP = ROOT / "modules/jolt_physics/spaces/jolt_contact_listener_3d.cpp"
CONTACT_H = ROOT / "modules/jolt_physics/spaces/jolt_contact_listener_3d.h"
RUNTIME = ROOT / "tests/stress/physics_jolt_process_info_regression.gd"


class JoltProcessCounterContracts(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.server = SERVER_CPP.read_text(encoding="utf-8")
        cls.header = SERVER_H.read_text(encoding="utf-8")
        cls.listener = CONTACT_CPP.read_text(encoding="utf-8")
        cls.listener_header = CONTACT_H.read_text(encoding="utf-8")
        cls.space = SPACE_CPP.read_text(encoding="utf-8")
        cls.space_header = SPACE_H.read_text(encoding="utf-8")
        cls.step = cls.server.split("void JoltPhysicsServer3D::step(real_t p_step) {", 1)[1].split(
            "void JoltPhysicsServer3D::sync()", 1
        )[0]
        cls.metrics = cls.server.split(
            "int JoltPhysicsServer3D::get_process_info(PS3DE::ProcessInfo p_process_info) {", 1
        )[1].split("void JoltPhysicsServer3D::free_space(", 1)[0]

    def test_process_info_reports_values_instead_of_unconditional_zeros(self):
        self.assertIn("int active_body_count = 0;", self.header)
        self.assertIn("int collision_manifold_count = 0;", self.header)
        self.assertIn("case PS3DE::INFO_ACTIVE_OBJECTS:", self.metrics)
        self.assertIn("return active_body_count;", self.metrics)
        self.assertIn("case PS3DE::INFO_COLLISION_PAIRS:", self.metrics)
        self.assertIn("return collision_manifold_count;", self.metrics)
        self.assertIn("case PS3DE::INFO_ISLAND_COUNT:", self.metrics)
        self.assertIn("return 0;", self.metrics)

    def test_active_counts_are_constant_time_and_cached_per_step(self):
        self.assertIn("GetNumActiveBodies(JPH::EBodyType::RigidBody)", self.step)
        self.assertIn("GetNumActiveBodies(JPH::EBodyType::SoftBody)", self.step)
        self.assertIn("get_contact_manifold_count()", self.step)
        self.assertNotIn("GetBodyStats()", self.step)
        self.assertIn("active_body_count = int(MIN(active_count, uint64_t(INT32_MAX)))", self.step)
        self.assertIn("collision_manifold_count = int(MIN(manifold_count, uint64_t(INT32_MAX)))", self.step)
        self.assertLess(self.step.index("active_space->step((float)p_step);"), self.step.index("GetNumActiveBodies("))

    def test_per_thread_contact_counters_have_no_atomic_hot_path(self):
        self.assertIn("uint64_t contact_manifold_callbacks = 0;", self.listener_header)
        self.assertIn("int contact_manifold_count = 0;", self.listener_header)
        for callback in ("OnContactAdded", "OnContactPersisted"):
            start = self.listener.index("void JoltContactListener3D::" + callback + "(")
            end = self.listener.index("\n}", start)
            body = self.listener[start:end]
            self.assertIn("++_get_thread_locals().contact_manifold_callbacks;", body)
            self.assertNotIn("timings_lock", body)
            self.assertNotIn("fetch_add", body)
        self.assertIn("tl.contact_manifold_callbacks = 0;", self.listener)
        self.assertIn("contact_manifold_count = 0;", self.listener)
        self.assertIn("const MutexLock lock(ThreadLocals::instances_mutex);", self.listener)
        self.assertIn("contact_manifold_count = int(MIN(total_callbacks, uint64_t(INT32_MAX)))", self.listener)

    def test_space_reader_and_aggregation_preserve_runtime_lifetimes(self):
        self.assertIn("int get_contact_manifold_count() const;", self.space_header)
        self.assertIn("return contact_listener->get_contact_manifold_count();", self.space)
        self.assertIn("int get_contact_manifold_count() const { return contact_manifold_count; }", self.listener_header)
        self.assertIn("contact_listener->post_step();", self.space)

    def test_native_regression_exercises_contact_creation_and_cleanup(self):
        code = RUNTIME.read_text(encoding="utf-8")
        self.assertIn("const BODY_COUNT := 64", code)
        self.assertIn("PhysicsServer3D.INFO_ACTIVE_OBJECTS", code)
        self.assertIn("PhysicsServer3D.INFO_COLLISION_PAIRS", code)
        self.assertIn("Performance.PHYSICS_3D_COLLISION_PAIRS", code)
        self.assertIn("idle_active != 0 or idle_pairs != 0", code)
        self.assertIn("JOLT_PROCESS_INFO_RESULT:", code)


if __name__ == "__main__":
    unittest.main()
