"""Regression contracts for conservative rotational CCD broadphase bounds."""

import math
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]


def factor(angle: float) -> float:
    if not math.isfinite(angle) or angle == 0:
        return 0.0
    return 2.0 * math.sin(min(abs(angle), math.pi) / 2.0)


def pad(low: tuple, high: tuple, pivot: tuple, angle: float) -> float:
    radius = math.hypot(*(max(abs(a - p), abs(b - p)) for a, b, p in zip(low, high, pivot)))
    return radius * factor(angle)


class RotationalBroadphaseContracts(unittest.TestCase):
    def test_space_settings_and_defaults(self):
        for dim in ("2d", "3d"):
            with self.subTest(dim=dim):
                key = f"physics/{dim}/solver/ccd_rotational_bounds"
                assert key in (ROOT / f"servers/physics_{dim}/physics_server_{dim}.cpp").read_text()
                assert key in (ROOT / f"modules/godot_physics_{dim}/godot_space_{dim}.cpp").read_text()
                assert "ccd_rotational_bounds = false" in (ROOT / f"modules/godot_physics_{dim}/godot_space_{dim}.h").read_text()

    def test_serial_and_parallel_same_angular_step(self):
        for dim in ("2d", "3d"):
            with self.subTest(dim=dim):
                code = (ROOT / f"modules/godot_physics_{dim}/godot_body_{dim}.h").read_text()
                step = (ROOT / f"modules/godot_physics_{dim}/godot_step_{dim}.cpp").read_text()
                assert "apply_deferred_motion(real_t p_step)" in code
                assert "body->apply_deferred_motion(p_delta)" in step
                source = (ROOT / f"modules/godot_physics_{dim}/godot_body_{dim}.cpp").read_text()
                assert "_update_shapes_with_motion(motion, angular_velocity" in source

    def test_rotation_and_translation_conservative_envelope(self):
        # Each corner's path is contained by the starting AABB expanded by
        # the maximum angular displacement chord, then swept by translation.
        for dim in (2, 3):
            low = tuple(3.0 + i for i in range(dim))
            high = tuple(6.0 + i for i in range(dim))
            pivot = tuple(0.0 for _ in range(dim))
            translation = tuple(1.5 * (i + 1) for i in range(dim))
            for angle in (0.0, 0.01, 0.5, math.pi, 5.0):
                padding = pad(low, high, pivot, angle)
                lo = [min(a, a + t) - padding for a, t in zip(low, translation)]
                hi = [max(b, b + t) + padding for b, t in zip(high, translation)]
                for sample in range(101):
                    frac = sample / 100.0
                    theta = angle * frac
                    # Sample a 2D rotation in the XY-plane, for both cases.
                    corner = high
                    x = pivot[0] + math.cos(theta) * (corner[0] - pivot[0]) - math.sin(theta) * (corner[1] - pivot[1]) + translation[0] * frac
                    y = pivot[1] + math.sin(theta) * (corner[0] - pivot[0]) + math.cos(theta) * (corner[1] - pivot[1]) + translation[1] * frac
                    self.assertGreaterEqual(x + 1e-10, lo[0])
                    self.assertLessEqual(x, hi[0] + 1e-10)
                    self.assertGreaterEqual(y + 1e-10, lo[1])
                    self.assertLessEqual(y, hi[1] + 1e-10)

    def test_native_and_source_wiring(self):
        helper = (ROOT / "servers/physics_ccd_rotational_bounds.h").read_text()
        tests = (ROOT / "tests/servers/test_godot_physics_ccd_rotational_bounds.cpp").read_text()
        assert "p_bounds.position - p_pivot" in helper
        assert "TEST_FORCE_LINK(test_godot_physics_ccd_rotational_bounds)" in tests
        for dim in ("2d", "3d"):
            source = (ROOT / f"modules/godot_physics_{dim}/godot_collision_object_{dim}.cpp").read_text()
            assert "is_ccd_rotational_bounds_enabled()" in source
            assert "godot_physics_ccd_rotational_padding(" in source


if __name__ == "__main__":
    unittest.main()
