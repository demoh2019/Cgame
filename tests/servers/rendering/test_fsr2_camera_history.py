"""Native Cgame FSR2 camera history and time-unit regression tests.

Run: python3 -m unittest tests/servers/rendering/test_fsr2_camera_history.py -v
These are source-contract and mathematical checks; they do not
replace Vulkan/Metal shader compilation or GPU frame captures.
"""

import math
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[3]
FORWARD = ROOT / "servers/rendering/renderer_rd/forward_clustered/render_forward_clustered.cpp"
FSR2 = ROOT / "servers/rendering/renderer_rd/effects/fsr2.cpp"
SDK = ROOT / "thirdparty/amd-fsr2/ffx_fsr2.h"


def camera_cut(distance, forward_cos=1.0, up_cos=1.0, fov_change=0.0):
    return distance ** 2 > 64.0 or forward_cos < 0.5 or up_cos < 0.5 or abs(fov_change) > 20.0


def frame_ms(seconds):
    valid = math.isfinite(seconds) and seconds > 0
    return max(0.001, min(seconds, 0.100)) * 1000.0 if valid else 16.67


def needs_time_reset(seconds):
    return not (math.isfinite(seconds) and seconds > 0.0) or seconds > 0.2


class Fsr2CameraHistoryTests(unittest.TestCase):
    def test_fsr2_sdk_requires_milliseconds(self):
        self.assertIn("expressed in milliseconds", SDK.read_text(encoding="utf-8"))
        source = FSR2.read_text(encoding="utf-8")
        self.assertIn("CLAMP(p_params.delta_time, 0.001f, 0.100f) * 1000.0f", source)
        self.assertIn("dispatch_desc.frameTimeDelta = safe_frame_ms;", source)
        self.assertNotIn("dispatch_desc.frameTimeDelta = p_params.delta_time;", source)

    def test_camera_jumps_reset_amds_history(self):
        source = FORWARD.read_text(encoding="utf-8")
        self.assertIn("(cur_transform.origin - prev_transform.origin).length_squared() > 64.0f", source)
        self.assertIn("prev_transform.basis.get_column(2).normalized().dot(", source)
        self.assertIn("prev_transform.basis.get_column(1).normalized().dot(", source)
        self.assertIn("Math::abs(prev_proj.get_fov() - cur_proj.get_fov()) > 20.0f", source)
        self.assertIn("params.reset_accumulation = camera_teleported || camera_rotated || lens_cut;", source)
        self.assertNotIn("params.reset_accumulation = false;", source)

    def test_walk_sprint_and_minor_camera_motion_keep_history(self):
        for distance in (0.0, 0.05, 0.7, 3.0, 8.0):
            self.assertFalse(camera_cut(distance))
        self.assertFalse(camera_cut(3.0, math.cos(math.radians(35)), 1.0, 7.0))
        self.assertFalse(camera_cut(0.0, 1.0, 1.0, 20.0))

    def test_teleport_respawn_and_major_rotation_reject_history(self):
        self.assertTrue(camera_cut(8.01))
        self.assertTrue(camera_cut(30.0))
        self.assertTrue(camera_cut(0.0, math.cos(math.radians(65))))
        self.assertTrue(camera_cut(0.0, 1.0, math.cos(math.radians(90))))
        self.assertTrue(camera_cut(0.0, 1.0, 1.0, 20.01))

    def test_time_units_60hz_low_fps_and_extreme_stalls(self):
        self.assertAlmostEqual(frame_ms(1.0 / 60.0), 1000.0 / 60.0, places=4)
        self.assertAlmostEqual(frame_ms(1.0 / 30.0), 1000.0 / 30.0, places=4)
        self.assertAlmostEqual(frame_ms(1.0 / 120.0), 1000.0 / 120.0, places=4)
        self.assertEqual(frame_ms(1.0), 100.0)
        self.assertTrue(needs_time_reset(1.0))
        self.assertFalse(needs_time_reset(1.0 / 30.0))

    def test_bad_timing_values_are_finite_and_force_history_reset(self):
        for seconds in (0.0, -1.0, float("nan"), float("inf"), -float("inf")):
            self.assertTrue(needs_time_reset(seconds))
            self.assertEqual(frame_ms(seconds), 16.67)
        source = FSR2.read_text(encoding="utf-8")
        self.assertIn("Math::is_finite(p_params.delta_time)", source)
        self.assertIn("p_params.reset_accumulation || !valid_frame_delta || p_params.delta_time > 0.2f", source)

    def test_no_additional_gpu_history_or_sharpening_passes(self):
        source = FORWARD.read_text(encoding="utf-8")
        self.assertIn("fsr2_effect->upscale(params);", source)
        self.assertEqual(source.count("params.reset_accumulation ="), 1)
        fsr2 = FSR2.read_text(encoding="utf-8")
        self.assertIn("dispatch_desc.reset = p_params.reset_accumulation", fsr2)


if __name__ == "__main__":
    unittest.main()
