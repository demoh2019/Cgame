"""Source-level contract for TextureStreaming last-pass telemetry and Albion monitors.

This complements but does not replace native/Godot execution in GitHub Actions.
"""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
MOD = ROOT / "modules/texture_streaming"
GAME = ROOT / "game/scripts/client"
TESTS = ROOT / "game/tests"
CI = ROOT / ".github/workflows/native-adaptive-texture-prefetch.yml"

GAUGES = (
    ("get_streaming_texture_count", "streaming_texture_count"),
    ("get_streaming_pending_count", "streaming_pending_count"),
    ("get_streaming_budget_reduction_steps", "streaming_budget_reduction_steps"),
    ("get_streaming_requested_bytes", "streaming_requested_bytes"),
    ("get_streaming_fitted_bytes", "streaming_fitted_bytes"),
    ("get_streaming_budget_bytes", "streaming_budget_bytes"),
)


class TextureStreamingMetricsContract(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.h = (MOD / "texture_streaming.h").read_text()
        cls.cpp = (MOD / "texture_streaming.cpp").read_text()
        cls.script = (GAME / "graphics_texture_streaming.gd").read_text()
        cls.online = (GAME / "online_main.gd").read_text()
        cls.tests = (TESTS / "test_graphics_texture_streaming.gd").read_text()

    def test_native_atomic_public_api(self):
        for method, atomic in GAUGES:
            self.assertIn(f"{method}() const", self.h)
            self.assertIn(f"{atomic}.load(std::memory_order_relaxed)", self.h)
            self.assertIn(f'D_METHOD("{method}")', self.cpp)
            self.assertIn(f"{atomic}.store(", self.cpp)
        self.assertIn("std::atomic<uint32_t> streaming_texture_count{ 0 };", self.h)
        self.assertIn("std::atomic<uint64_t> streaming_fitted_bytes{ 0 };", self.h)
        self.assertIn("get_memory_budget_bytes_used", self.script)

    def test_feedback_worker_publishes_at_end_of_pass_and_stops_cleanly(self):
        loop = self.cpp.split("void TextureStreaming::_feedback_buffer_process(", 1)[1].split(
            "void TextureStreaming::_texture_reload_thread_func(", 1
        )[0]
        self.assertIn("TextureStreamingStatsPolicy::budget_reduction_steps(previous_mip, increased_mip)", loop)
        self.assertIn("TextureStreamingStatsPolicy::needs_reload(cur, candidate.target_mip)", loop)
        self.assertIn("++pending_count;", loop)
        self.assertIn("streaming_texture_count.store(uint32_t(fit_candidates.size())", loop)
        self.assertIn("streaming_requested_bytes.store(total_requested_bytes", loop)
        self.assertIn("streaming_fitted_bytes.store(assigned_bytes", loop)
        self.assertIn("streaming_budget_bytes.store(budget_bytes", loop)
        self.assertIn("streaming_pending_count.store(pending_count", loop)
        self.assertIn("streaming_budget_reduction_steps.store(budget_reduction_steps", loop)
        self.assertLess(loop.index("texture_streaming_total_memory.store(memory"),
                        loop.index("streaming_texture_count.store("))
        self.assertNotIn("RenderingServer::", loop)
        stop = self.cpp.split("void TextureStreaming::_stop_streaming(", 1)[1].split(
            "void TextureStreaming::_render_thread_specific_initialization(", 1
        )[0]
        self.assertLess(stop.index("feedback_buffer_thread.wait_to_finish();"),
                        stop.index("streaming_texture_count.store(0"))
        for _, gauge in GAUGES:
            self.assertIn(f"{gauge}.store(0, std::memory_order_relaxed);", stop)

    def test_backlog_predicate_and_native_regressions(self):
        source = (MOD / "streaming_stats_policy.h").read_text()
        self.assertIn("constexpr bool needs_reload(uint8_t p_resident_mip, uint8_t p_target_mip)", source)
        self.assertIn("p_target_mip != UINT8_MAX && p_resident_mip != p_target_mip", source)
        self.assertIn("constexpr uint32_t budget_reduction_steps(uint8_t p_before, uint8_t p_after)", source)
        tests = (MOD / "tests/test_streaming_stats_policy.h").read_text()
        self.assertIn("[TextureStreaming] wanted versus resident mip backlog semantics", tests)
        self.assertIn("[TextureStreaming] reduction steps only count budget-driven loss of mip detail", tests)
        self.assertIn("budget_reduction_steps(8, 3) == 0", tests)
        reg = (MOD / "register_types.cpp").read_text()
        self.assertIn('#include "tests/test_streaming_stats_policy.h"', reg)

    def test_game_monitor_fallback_cleanup_and_idempotence(self):
        self.assertIn("static func register_profiler_monitors() -> Array[StringName]:", self.script)
        self.assertIn('Engine.has_singleton("TextureStreaming")', self.script)
        self.assertIn("server.has_method(method_name)", self.script)
        self.assertIn("not Performance.has_custom_monitor(monitor_name)", self.script)
        self.assertIn("Performance.add_custom_monitor(monitor_name, Callable(server, method_name))", self.script)
        for method, _ in GAUGES:
            self.assertIn(method, self.script)
        self.assertIn("GraphicsTextureStreaming.register_profiler_monitors()", self.online)
        self.assertIn("_ambient_monitors.append_array(", self.online)
        self.assertIn("Performance.remove_custom_monitor(monitor_name)", self.online)
        self.assertIn("t.check(duplicate.is_empty()", self.tests)
        self.assertIn("Performance.remove_custom_monitor(monitor_name)", self.tests)
        self.assertIn("Performance.has_custom_monitor(monitor_name)", self.tests)

    def test_ci_and_documentation(self):
        yaml = CI.read_text()
        self.assertIn("test_texture_streaming_metrics_contract.py", yaml)
        self.assertIn("game/scripts/client/online_main.gd", yaml)
        self.assertIn('--test-case="*TextureStreaming*"', yaml)
        self.assertIn("run_adaptive_texture_prefetch.gd", yaml)
        documentation = (MOD / "README.md").read_text()
        self.assertIn("Unreal STAT STREAMING-style", documentation)
        self.assertIn("0 means budget fitting is disabled", documentation)
        self.assertIn("Atomic", documentation.lower().capitalize())


if __name__ == "__main__":
    unittest.main()
