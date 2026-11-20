"""Source regressions for bounded WorldStreamer integration work.

Run: python3 -m unittest tests/scene/test_world_streamer_frame_budget.py -v

These tests can run without a custom Godot binary. A separate GDScript test
exercises real runtime chunk generation on the rebuilt Cgame engine.
"""
from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[2]
CPP = ROOT / "scene/main/world_streamer.cpp"
HEADER = ROOT / "scene/main/world_streamer.h"
GAME = ROOT / "game/scripts/client/online_main.gd"
POLICY = ROOT / "game/scripts/client/world_streaming_policy.gd"
HUD = ROOT / "game/scripts/client/ui_accessibility_layer.gd"
GRID = ROOT / "scene/main/world_streaming_grid.cpp"


class StreamingBudgetContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.cpp = CPP.read_text(encoding="utf-8")
        cls.header = HEADER.read_text(encoding="utf-8")
        cls.game = GAME.read_text(encoding="utf-8")
        cls.policy = POLICY.read_text(encoding="utf-8")
        cls.hud = HUD.read_text(encoding="utf-8")
        cls.grid = GRID.read_text(encoding="utf-8")

    def test_one_count_and_clock_across_both_internal_process_phases(self):
        body = self.cpp.split("case NOTIFICATION_INTERNAL_PROCESS:", 1)[1]
        body = body.split("} break;", 1)[0]
        self.assertIn("int frame_budget = MAX(max_instantiations_per_frame, 1);", body)
        self.assertIn(
            "const uint64_t frame_started_usec = OS::get_singleton()->get_ticks_usec();",
            body,
        )
        self.assertIn("_poll_loading(frame_budget, frame_started_usec);", body)
        self.assertIn("_run_generator_queue(frame_budget, frame_started_usec);", body)
        self.assertNotIn("_poll_loading();", body)
        self.assertNotIn("_run_generator_queue();", body)

    def test_explicit_refresh_has_one_combined_budget(self):
        body = self.cpp.split("void WorldStreamer::refresh(bool p_retry) {", 1)[1]
        body = body.split("\nvoid WorldStreamer::unload_all()", 1)[0]
        self.assertIn("int refresh_budget = MAX(max_instantiations_per_frame, 1);", body)
        self.assertIn("_poll_loading(refresh_budget, started_usec);", body)
        self.assertIn("_run_generator_queue(refresh_budget, started_usec);", body)

    def test_both_load_paths_consume_the_same_budget(self):
        gen = self.cpp.split("void WorldStreamer::_run_generator_queue(", 1)[1]
        gen = gen.split("void WorldStreamer::_poll_loading(", 1)[0]
        ready = self.cpp.split("void WorldStreamer::_poll_loading(", 1)[1]
        ready = ready.split("void WorldStreamer::_update_streaming()", 1)[0]
        for body in (gen, ready):
            self.assertIn("int &r_instantiation_budget", body)
            self.assertIn("uint64_t p_frame_started_usec", body)
            self.assertIn("r_instantiation_budget--;", body)
            self.assertIn("OS::get_singleton()->get_ticks_usec() - p_frame_started_usec", body)
            self.assertNotIn("int budget = MAX(max_instantiations_per_frame, 1);", body)
            self.assertNotIn("const uint64_t started_usec =", body)

    def test_disabling_streamer_halts_both_activation_paths(self):
        self.assertIn(
            "!enabled || r_instantiation_budget <= 0 || generate_queue.is_empty()",
            self.cpp,
        )
        self.assertIn("if (!enabled || loading.is_empty())", self.cpp)

    def test_procedural_backlog_is_exposed_read_only(self):
        self.assertIn(
            "int get_queued_generation_count() const { return int(generate_queue.size()); }",
            self.header,
        )
        self.assertIn(
            'D_METHOD("get_queued_generation_count")',
            self.cpp,
        )
        self.assertIn("_world_streamer.get_queued_generation_count()", self.hud)

    def test_stopping_reprioritizes_existing_queue(self):
        # A moving bike prefetch queue may still contain cells after the bike
        # stops. Zero lookahead must resort the existing cells nearest-first,
        # not return before the queued-work sorting algorithm.
        motion = self.grid.split("void prioritize_cells_for_motion(", 1)[1]
        motion = motion.split("void cells_to_unload(", 1)[0]
        self.assertIn("const Vector3 future = p_focus + prediction;", motion)
        self.assertIn("const Vector3i focus_cell = world_to_cell(", motion)
        self.assertIn("prediction = Vector3();", motion)
        self.assertIn("if (p_velocity.is_finite() && Math::is_finite(p_lookahead_seconds)", motion)
        self.assertIn("sorter.sort(sorted.ptr(), sorted.size());", motion)
        self.assertNotIn("!(p_lookahead_seconds > 0.0)", motion)


    def test_completed_threaded_scenes_use_the_same_camera_priority(self):
        ready = self.cpp.split("void WorldStreamer::_poll_loading(", 1)[1]
        ready = ready.split("void WorldStreamer::_update_streaming()", 1)[0]
        self.assertIn("prioritize_cells_for_motion_and_view(ready_cells", ready)
        self.assertIn("view_direction, view_priority, cell_size, _grid_axes()", ready)
        # The native streamer still uses just one shared integration budget.
        self.assertIn("r_instantiation_budget--;", ready)

    def test_fast_turn_refresh_remains_opt_in_and_budget_safe(self):
        self.assertIn("real_t fast_view_refresh_degrees = 0.0;", self.header)
        self.assertIn("last_queued_view_direction = view_direction;", self.cpp)
        tick = self.cpp.split("case NOTIFICATION_INTERNAL_PROCESS:", 1)[1]
        tick = tick.split("} break;", 1)[0]
        self.assertIn("should_refresh_for_view_turn(", tick)
        self.assertIn("time_since_update >= 0.05", tick)
        self.assertIn("time_since_update >= update_interval || early", tick)
        self.assertIn("_run_generator_queue(frame_budget, frame_started_usec);", tick)
        self.assertNotIn("_run_generator_queue(frame_budget, frame_started_usec);\n\t\t\t_run_generator_queue", tick)

    def test_bike_prediction_only_changes_priority(self):
        self.assertIn("const RIDING_LOOKAHEAD := 3.0", self.policy)
        self.assertIn("const WALK_LOOKAHEAD := 2.0", self.policy)
        self.assertIn("velocity.length_squared() < IDLE_VELOCITY_SQ", self.policy)
        self.assertIn("WorldStreamingPolicy.apply(streamer", self.game)
        self.assertIn("streamer.velocity_hint = _stream_velocity", self.game)
        self.assertIn("streamer.max_chunk_work_usec = 2500", self.game)
        self.assertIn("streamer.max_instantiations_per_frame = 3", self.game)
        self.assertIn("_access.set_world_streamer(streamer)", self.game)
        self.assertNotIn("load_radius =", self.policy)
        self.assertNotIn("unload_radius =", self.policy)


if __name__ == "__main__":
    unittest.main()
