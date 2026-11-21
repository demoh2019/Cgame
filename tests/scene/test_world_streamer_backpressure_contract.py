"""Native WorldStreamer adaptive backpressure contracts and independent numeric model.

Does not substitute for compiling the custom Godot engine or timing a GPU frame.
"""
from pathlib import Path
import math
import unittest
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[2]
HEADER = ROOT / "scene/main/world_streamer.h"
CPP = ROOT / "scene/main/world_streamer.cpp"
XML = ROOT / "doc/classes/WorldStreamer.xml"
GAME = ROOT / "game/scripts/client/online_main.gd"
GAME_TEST = ROOT / "game/tests/test_world_streamer_backpressure.gd"
RUNNER = ROOT / "game/tests/run_all.gd"


def pressure_step(previous, frame_delta):
    previous = max(0.0, min(1.0, previous if math.isfinite(previous) else 0.0))
    if not math.isfinite(frame_delta) or frame_delta <= 0.0:
        return previous
    if frame_delta > .030:
        return min(1.0, previous + .16)
    if frame_delta < .020:
        return max(0.0, previous - .05)
    return previous


def effective_slots(configured, pressure):
    return max(1, max(configured, 1) - (2 if pressure >= .8 else 1 if pressure >= .4 else 0))


def effective_cpu(configured, pressure):
    configured = max(0, min(configured, 1_000_000))
    if pressure >= .8:
        return min(configured, max(250, configured // 2))
    if pressure >= .4:
        return min(configured, max(250, configured * 3 // 4))
    return configured


def effective_unloads(configured, pressure):
    configured = max(0, min(configured, 64))
    if configured == 0:
        return 0
    pressure = max(0.0, min(pressure if math.isfinite(pressure) else 0.0, 1.0))
    if pressure >= .8:
        return max(1, (configured + 1) // 2)
    if pressure >= .4:
        return max(1, (configured * 3 + 3) // 4)
    return configured


class TestWorldStreamerPressureContracts(unittest.TestCase):
    def test_native_pressure_and_frame_work_contract(self):
        header = HEADER.read_text()
        cpp = CPP.read_text()
        for method in (
            "advance_chunk_pressure", "calculate_adaptive_instantiation_slots",
            "calculate_adaptive_chunk_work_usec", "calculate_adaptive_unload_slots",
            "get_effective_unloads_per_update", "get_last_frame_chunk_work_usec",
            "get_last_frame_chunk_attempt_count", "set_adaptive_chunk_budget_enabled",
        ):
            self.assertIn(method, header)
            self.assertIn(method, cpp)
        self.assertIn("adaptive_chunk_budget_enabled = false", header)
        self.assertIn("streaming_frame_pressure = advance_chunk_pressure(", cpp)
        self.assertIn("get_effective_instantiations_per_frame()", cpp)
        self.assertIn("get_effective_chunk_work_usec()", cpp)
        self.assertIn("_record_chunk_work(generation_started_usec)", cpp)
        self.assertIn("_record_chunk_work(finalization_started_usec)", cpp)
        self.assertIn("_finish_chunk_work_frame()", cpp)
        self.assertIn("frame_chunk_attempt_count++", cpp)
        self.assertIn("active_chunk_work_budget_usec > 0", cpp)
        self.assertIn("active_instantiation_budget", cpp)
        # ResourceLoader still performs asynchronous loading, and the scene
        # tree is never modified from any worker thread in the new code.
        self.assertIn("ResourceLoader::load_threaded_get_status", cpp)
        self.assertNotIn("WorkerThreadPool::", cpp)

    def test_godot_docs_and_game_opt_in(self):
        root = ET.parse(XML).getroot()
        names = {e.attrib["name"] for e in root.findall("./methods/method")}
        names.update(e.attrib["name"] for e in root.findall("./members/member"))
        for n in (
            "adaptive_chunk_budget_enabled", "advance_chunk_pressure",
            "calculate_adaptive_instantiation_slots", "calculate_adaptive_chunk_work_usec",
            "calculate_adaptive_unload_slots", "get_effective_unloads_per_update",
            "get_last_frame_chunk_work_usec", "get_last_frame_chunk_attempt_count",
        ):
            self.assertIn(n, names)
        game = GAME.read_text()
        test = GAME_TEST.read_text()
        self.assertIn('if "adaptive_chunk_budget_enabled" in streamer:', game)
        self.assertIn("streamer.adaptive_chunk_budget_enabled = true", game)
        for name in (
            "Albion/StreamChunkCPUus", "Albion/StreamChunkAttempts",
            "Albion/StreamPressurePct", "Albion/StreamEffectiveSlots",
            "Albion/StreamEffectiveCPUus", "Albion/StreamEffectiveUnloads",
        ):
            self.assertIn(name, game)
        self.assertIn("streamer.refresh()", test)
        self.assertIn("get_last_frame_chunk_attempt_count()", test)
        self.assertIn("test_world_streamer_backpressure.gd", RUNNER.read_text())

    def test_pressure_recovery_and_thresholds(self):
        pressure = 0.0
        for _ in range(6):
            pressure = pressure_step(pressure, .04)
        self.assertGreater(pressure, .9)
        self.assertEqual(effective_slots(3, pressure), 1)
        self.assertEqual(effective_cpu(2500, pressure), 1250)
        for _ in range(25):
            pressure = pressure_step(pressure, .016)
        self.assertEqual(pressure, 0.0)
        self.assertEqual(effective_slots(3, pressure), 3)
        self.assertEqual(effective_cpu(2500, pressure), 2500)
        self.assertEqual(pressure_step(.5, float("nan")), .5)
        self.assertEqual(pressure_step(float("nan"), .025), 0.0)

    def test_adaptive_unloads_are_bounded_and_recover(self):
        self.assertEqual(effective_unloads(0, 1.0), 0)
        self.assertEqual(effective_unloads(12, .4), 9)
        self.assertEqual(effective_unloads(12, .8), 6)
        self.assertEqual(effective_unloads(48, .8), 24)
        self.assertEqual(effective_unloads(200, .8), 32)
        self.assertEqual(effective_unloads(12, float("nan")), 12)
        for configured in range(1, 65):
            for pressure in (0, .39, .4, .79, .8, 1.0):
                self.assertTrue(1 <= effective_unloads(configured, pressure) <= configured)
        cpp = CPP.read_text()
        self.assertIn("MIN(count, get_effective_unloads_per_update())", cpp)
        self.assertIn("if (max_unloads_per_update == 0)", cpp)

    def test_soft_budget_preserves_progress_and_off_mode(self):
        for slots in range(1, 8):
            for configured in (0, 100, 900, 2500, 4000):
                for pressure in (0, .3999, .4, .7999, .8, 1.0):
                    self.assertGreaterEqual(effective_slots(slots, pressure), 1)
                    self.assertLessEqual(effective_slots(slots, pressure), slots)
                    self.assertGreaterEqual(effective_cpu(configured, pressure), 0)
                    self.assertLessEqual(effective_cpu(configured, pressure), configured)
        self.assertEqual(effective_slots(3, .4), 2)
        self.assertEqual(effective_slots(3, .8), 1)
        self.assertEqual(effective_cpu(2500, .4), 1875)
        self.assertEqual(effective_cpu(2500, .8), 1250)


if __name__ == "__main__":
    unittest.main()
