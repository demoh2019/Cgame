"""Source-level regression contracts for low-overhead Jolt worker instrumentation.

The native engine test suite and runtime physics stress remain responsible for
correctness and performance. These checks catch accidental unconditional timer
and spinlock use in every Jolt worker job.
"""

from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[2]
JOB_CPP = ROOT / "modules/jolt_physics/spaces/jolt_job_system.cpp"
JOB_H = ROOT / "modules/jolt_physics/spaces/jolt_job_system.h"
SERVER = ROOT / "modules/jolt_physics/jolt_physics_server_3d.cpp"


class JoltJobProfilingContracts(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.source = JOB_CPP.read_text(encoding="utf-8")
        cls.header = JOB_H.read_text(encoding="utf-8")
        cls.server = SERVER.read_text(encoding="utf-8")
        cls.execute = cls.source.split("void JoltJobSystem::Job::_execute(void *p_user_data) {", 1)[1].split(
            "\nJoltJobSystem::Job::Job(", 1
        )[0]
        cls.pre_step = cls.source.split("void JoltJobSystem::pre_step() {", 1)[1].split(
            "\nvoid JoltJobSystem::post_step() {", 1
        )[0]

    def test_profiling_is_disabled_by_default(self):
        self.assertIn("inline static std::atomic<bool> timings_enabled = false;", self.header)
        self.assertIn("#ifdef DEBUG_ENABLED", self.header)

    def test_profiler_active_flag_is_sampled_once_per_step(self):
        self.assertIn("EngineDebugger::get_singleton()", self.pre_step)
        self.assertIn('engine_debugger->is_profiling(SNAME("servers"))', self.pre_step)
        self.assertIn("timings_enabled.store(", self.pre_step)
        self.assertIn("std::memory_order_relaxed", self.pre_step)
        self.assertIn("#ifdef DEBUG_ENABLED", self.pre_step)

    def test_worker_timers_and_lock_are_only_used_when_enabled(self):
        body = self.execute
        self.assertIn("timings_enabled.load(std::memory_order_relaxed)", body)
        self.assertIn("if (collect_timings) {", body)
        self.assertEqual(body.count("Time::get_singleton()->get_ticks_usec()"), 2)
        self.assertEqual(body.count("timings_lock.lock();"), 1)
        self.assertEqual(body.count("timings_lock.unlock();"), 1)
        self.assertLess(body.index("timings_enabled.load("), body.index("job->Execute();"))
        self.assertLess(body.index("job->Execute();"), body.rindex("if (collect_timings) {"))
        self.assertLess(body.rindex("if (collect_timings) {"), body.index("timings_lock.lock();"))
        self.assertIn("job->Release();", body)

    def test_profiling_flush_still_works_and_handles_null_debugger(self):
        flush = self.source.split("void JoltJobSystem::flush_timings() {", 1)[1]
        self.assertIn("engine_debugger != nullptr && engine_debugger->is_profiling(profiler_name)", flush)
        self.assertIn("profiler_add_frame_data(profiler_name, timings)", flush)
        self.assertIn("E.value = 0;", flush)
        self.assertIn("job_system->flush_timings();", self.server)

    def test_physics_server_toggles_profiler_around_every_space(self):
        step = self.server.split("void JoltPhysicsServer3D::step(real_t p_step) {", 1)[1].split(
            "\nvoid JoltPhysicsServer3D::sync(", 1
        )[0]
        self.assertLess(step.index("job_system->pre_step();"), step.index("active_space->step((float)p_step);"))
        self.assertLess(step.index("active_space->step((float)p_step);"), step.index("job_system->post_step();"))


if __name__ == "__main__":
    unittest.main()
