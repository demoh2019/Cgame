"""3D box-box SAT source contracts and 3-axis-vs-15-axis reference."""
from pathlib import Path
import random
import unittest

ROOT = Path(__file__).resolve().parents[2]
SAT = ROOT / "modules/godot_physics_3d/godot_collision_solver_3d_sat.cpp"
RUNTIME = ROOT / "tests/stress/physics_box_box_sat_3d_regression.gd"
WORKLOAD = ROOT / "tests/stress/physics_box_box_sat_3d.gd"
RUNNER = ROOT / "tests/stress/run.py"
STRESS = ROOT / "tests/stress/stress.gd"
AXES = ((1, 0, 0), (0, 1, 0), (0, 0, 1))


def cross(a, b):
    return (a[1] * b[2] - a[2] * b[1],
            a[2] * b[0] - a[0] * b[2],
            a[0] * b[1] - a[1] * b[0])


def intersects(delta, a, b, axes):
    for axis in axes:
        if axis == (0, 0, 0):
            continue
        radius_a = sum(abs(axis[i]) * a[i] for i in range(3))
        radius_b = sum(abs(axis[i]) * b[i] for i in range(3))
        projection = abs(sum(axis[i] * delta[i] for i in range(3)))
        if projection > radius_a + radius_b:
            return False
    return True


class AlignedBoxSATContracts(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        source = SAT.read_text(encoding="utf-8")
        start = source.index("static void _collision_box_box(")
        end = source.index("static void _collision_box_capsule(", start)
        cls.code = source[start:end]

    def test_fast_path_runs_after_cached_axis_and_preserves_generic_sat(self):
        code = self.code
        gate = "if (!p_with_margin && p_transform_a.basis == Basis() && p_transform_b.basis == Basis())"
        self.assertIn(gate, code)
        self.assertIn("Vector3 axis(0, 0, 0);", code)
        self.assertIn("axis[i] = 1.0;", code)
        self.assertIn("if (!separator.test_axis(axis))", code)
        self.assertLess(code.index("if (!separator.test_previous_axis())"), code.index(gate))
        self.assertLess(code.index(gate), code.index("// test faces of A"))
        self.assertIn("p_transform_b.basis.get_column(i).normalized()", code)
        self.assertIn("p_transform_a.basis.get_column(i).cross(p_transform_b.basis.get_column(j))", code)
        self.assertIn("if (p_with_margin) {", code)
        # Both paths still generate the original SAT contact manifold.
        self.assertEqual(code.count("separator.generate_contacts();"), 2)

    def test_three_unique_axes_equal_generic_fifteen_for_unscaled_aabbs(self):
        generic = list(AXES) + list(AXES)
        generic.extend(cross(a, b) for a in AXES for b in AXES)
        self.assertEqual(len(generic), 15)
        rng = random.Random(20261119)
        samples = [
            ((0.0, 0.0, 0.0), (1.0, 1.0, 1.0), (1.0, 1.0, 1.0)),
            ((2.0, 0.0, 0.0), (1.0, 1.0, 1.0), (1.0, 1.0, 1.0)),
            ((2.01, 0.0, 0.0), (1.0, 1.0, 1.0), (1.0, 1.0, 1.0)),
        ]
        for _ in range(5000):
            samples.append((
                tuple(rng.uniform(-12.0, 12.0) for _ in range(3)),
                tuple(rng.uniform(0.05, 5.0) for _ in range(3)),
                tuple(rng.uniform(0.05, 5.0) for _ in range(3)),
            ))
        for delta, extent_a, extent_b in samples:
            self.assertEqual(intersects(delta, extent_a, extent_b, AXES),
                             intersects(delta, extent_a, extent_b, generic))

    def test_rotated_fallback_and_manifold_runtime_are_covered(self):
        code = RUNTIME.read_text(encoding="utf-8")
        self.assertIn("for rotated in [false, true]:", code)
        self.assertIn("query.margin = 0.0", code)
        self.assertIn("state.intersect_shape(query, 8)", code)
        self.assertIn("state.collide_shape(query, 8)", code)
        self.assertIn("point.is_finite()", code)
        self.assertIn("PhysicsServer3D.free_rid(static_body)", code)

    def test_both_benchmark_cases_registered(self):
        runner = RUNNER.read_text(encoding="utf-8")
        script = STRESS.read_text(encoding="utf-8")
        workload = WORKLOAD.read_text(encoding="utf-8")
        for case in ("physics_box_box_axis_aligned_3d", "physics_box_box_rotated_3d"):
            self.assertIn(f'"{case}"', runner)
            self.assertIn(f'"{case}":', script)
        self.assertIn("BoxSAT3DStress.new().run(self, scale, frames, false)", script)
        self.assertIn("BoxSAT3DStress.new().run(self, scale, frames, true)", script)
        self.assertIn('"peak_collision_pairs": peak_pairs', workload)
        self.assertIn('"frame_p95_ms": stats["p95"]', workload)
        self.assertIn("PhysicsServer3D.body_set_state(dynamic_bodies[i]", workload)


if __name__ == "__main__":
    unittest.main()
