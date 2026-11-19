"""Regression contracts for Apple Embedded pressure fallback, Godot #125392."""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[3]
SOURCE = (ROOT / "drivers/apple_embedded/godot_view_apple_embedded.mm").read_text(encoding="utf-8")
GUARD = "[touch maximumPossibleForce] > 0.0 ? [touch force] / [touch maximumPossibleForce] : 0.0"


class IOSPressureFallbackTests(unittest.TestCase):
    def test_touch_drag_pressure_avoids_zero_denominator(self):
        self.assertIn(GUARD, SOURCE)

    def test_pressure_fallback_is_zero_not_nan(self):
        call = next(line for line in SOURCE.splitlines()
                    if "touch_drag(tid, prev_point.x" in line)
        self.assertIn(GUARD, call)
        self.assertIn(" : 0.0, Vector2(", call)

    def test_touch_drag_preserves_previous_and_new_coordinates(self):
        call = next(line for line in SOURCE.splitlines()
                    if "touch_drag(tid, prev_point.x" in line)
        for value in (
            "prev_point.x * self.contentScaleFactor",
            "prev_point.y * self.contentScaleFactor",
            "touchPoint.x * self.contentScaleFactor",
            "touchPoint.y * self.contentScaleFactor",
        ):
            with self.subTest(value=value):
                self.assertIn(value, call)

    def test_azimuth_and_altitude_still_propagate(self):
        self.assertIn("Vector2(azim.dx, azim.dy) * Math::cos(alt)", SOURCE)

    def test_guarded_touch_drag_occurs_once(self):
        calls = [line for line in SOURCE.splitlines() if "touch_drag(tid, prev_point.x" in line]
        self.assertEqual(len(calls), 1)
        self.assertIn(GUARD, calls[0])

    def test_guard_uses_nonzero_strict_positive_threshold(self):
        self.assertIn("[touch maximumPossibleForce] > 0.0", SOURCE)
        self.assertNotIn("[touch maximumPossibleForce] >= 0.0 ?", SOURCE)


if __name__ == "__main__":
    unittest.main()
