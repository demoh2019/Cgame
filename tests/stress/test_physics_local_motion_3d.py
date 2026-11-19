"""Reference and source-contract tests for the 3D body motion hot loop.

Run: python3 -m unittest discover -s tests/stress -p
'test_physics_local_motion_3d.py' -v

Godot tests remain necessary to measure actual collision accuracy and speed.
"""

from __future__ import annotations

from pathlib import Path
import math
import random
import unittest


ROOT = Path(__file__).resolve().parents[2]
SPACE = ROOT / "modules/godot_physics_3d/godot_space_3d.cpp"


def transform(basis, vec):
    """A 3x3 (potentially scaled or sheared) basis times a vector."""
    return tuple(sum(basis[row][col] * vec[col] for col in range(3)) for row in range(3))


class LocalMotion3DTests(unittest.TestCase):
    def test_multiply_local_motion_matches_repeated_basis_transform(self):
        rng = random.Random(4538)
        for _ in range(10000):
            basis = tuple(tuple(rng.uniform(-5.0, 5.0) for _ in range(3)) for _ in range(3))
            motion = tuple(rng.uniform(-100.0, 100.0) for _ in range(3))
            fraction = rng.uniform(0.0, 1.0)
            full_local = transform(basis, motion)
            cached = tuple(value * fraction for value in full_local)
            repeated = transform(basis, tuple(value * fraction for value in motion))
            for value, reference in zip(cached, repeated):
                self.assertTrue(
                    math.isclose(value, reference, abs_tol=1e-11, rel_tol=1e-11),
                    f"cached={cached}, reference={repeated}",
                )

    def test_body_motion_reuses_full_local_sweep_inside_binary_search(self):
        src = SPACE.read_text(encoding="utf-8")
        begin = src.index("bool GodotSpace3D::test_body_motion(")
        end = src.index("void *GodotSpace3D::_broadphase_pair(", begin)
        motion = src[begin:end]
        self.assertIn(
            "const Vector3 full_motion_local = body_shape_xform_inv.basis.xform(p_parameters.motion);",
            motion,
        )
        self.assertIn("mshape.motion = full_motion_local * fraction;", motion)
        self.assertIn("mshape.motion = full_motion_local;", motion)
        self.assertNotIn(
            "mshape.motion = body_shape_xform_inv.basis.xform(p_parameters.motion * fraction);",
            motion,
        )
        self.assertIn("for (int k = 0; k < 8; k++)", motion)

    def test_related_3d_motion_stress_is_registered(self):
        runner = (ROOT / "tests/stress/run.py").read_text(encoding="utf-8")
        script = (ROOT / "tests/stress/stress.gd").read_text(encoding="utf-8")
        self.assertIn('"physics_motion_filter_overflow_3d"', runner)
        self.assertIn('"physics_motion_exclusions_3d"', script)


if __name__ == "__main__":
    unittest.main()
