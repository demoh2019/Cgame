"""Tests of the WorkerThreadPool script-language teardown contract (Godot #125357)."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[3]
SOURCE = (ROOT / "core/object/worker_thread_pool.cpp").read_text(encoding="utf-8")
SMOKE = (ROOT / "misc/scripts/tests/worker_pool_unwaited_shutdown.gd").read_text(encoding="utf-8")
BEGIN = SOURCE.index("void WorkerThreadPool::exit_languages_threads()")
END = SOURCE.index("void WorkerThreadPool::finish()", BEGIN)
TEARDOWN = SOURCE[BEGIN:END]


class WorkerPoolCallableReleaseTests(unittest.TestCase):
    def test_waits_for_all_script_languages_to_detach(self):
        self.assertIn("runlevel_data.exit_languages.num_exited_threads != threads.size()", TEARDOWN)

    def test_collects_only_completed_tasks_with_valid_script_callables(self):
        self.assertIn("E.value->completed && E.value->callable.is_valid()", TEARDOWN)

    def test_clears_task_ownership_after_copying_callback(self):
        self.assertIn("leftovers.push_back(E.value->callable);", TEARDOWN)
        self.assertIn("E.value->callable = Callable();", TEARDOWN)
        self.assertLess(TEARDOWN.index("leftovers.push_back("),
                        TEARDOWN.index("E.value->callable = Callable();"))

    def test_drops_copied_callbacks_outside_task_mutex(self):
        self.assertIn("lock.temp_unlock();", TEARDOWN)
        self.assertIn("leftovers.clear();", TEARDOWN)
        self.assertIn("lock.temp_relock();", TEARDOWN)
        self.assertLess(TEARDOWN.index("lock.temp_unlock();"),
                        TEARDOWN.index("leftovers.clear();"))
        self.assertLess(TEARDOWN.index("leftovers.clear();"),
                        TEARDOWN.index("lock.temp_relock();"))

    def test_cleanup_runs_after_threads_have_detached(self):
        self.assertLess(TEARDOWN.index("num_exited_threads != threads.size()"),
                        TEARDOWN.index("LocalVector<Callable> leftovers;"))

    def test_native_worker_pool_finish_remains_present(self):
        self.assertIn("void WorkerThreadPool::finish()", SOURCE)
        self.assertIn("task_allocator.free(E.value);", SOURCE)

    def test_smoke_uses_actual_script_callables_without_waiting_on_taskids(self):
        self.assertIn('WorkerThreadPool.add_task(Callable(self, "_noop").bind(index))', SMOKE)
        self.assertIn("WorkerThreadPool.is_task_completed(task_id)", SMOKE)
        self.assertNotIn("wait_for_task_completion(", SMOKE.split("func _initialize()")[1])

    def test_smoke_covers_multiple_jobs_and_failure_timeout(self):
        self.assertIn("const TASK_COUNT := 32", SMOKE)
        self.assertIn("const MAX_FRAMES := 600", SMOKE)
        self.assertIn("quit(1)", SMOKE)


if __name__ == "__main__":
    unittest.main()
