"""2D rectangle/rectangle SAT duplicate-axis elimination contracts.

When two exact basis matrices match, their face axes are duplicates.
Skipping B's two tests has exactly the same SAT separation decisions
for arbitrary half-extents, margin and swept projections. Real physics
queries/manifolds are tested by the companion headless GDScript.
"""
from pathlib import Path
import math
import random
import re
import unittest


ROOT = Path(__file__).resolve().parents[2]
SAT = ROOT / "modules/godot_physics_2d/godot_collision_solver_2d_sat.cpp"
RUNTIME = ROOT / "tests/stress/physics_rectangle_shared_axes_2d_regression.gd"
WORKLOAD = ROOT / "tests/stress/physics_rectangle_shared_axes_2d.gd"
RUNNER = ROOT / "tests/stress/run.py"
STRESS = ROOT / "tests/stress/stress.gd"


def dot(a, b):
    return a[0] * b[0] + a[1] * b[1]


def basis_projection(half, axes, test_axis):
    return sum(abs(dot(axes[i], test_axis)) * half[i] for i in range(2))


def separated(delta, half_a, half_b, basis_a, basis_b, candidates, margin=0.0,
              motion_a=(0.0, 0.0), motion_b=(0.0, 0.0)):
    # Generic rectangle SAT, including swept interval bounds and margins.
    for axis in candidates:
        length = math.hypot(*axis)
        if length == 0:
            continue
        normal = (axis[0] / length, axis[1] / length)
        center_distance = dot(delta, normal)
        radius_a = basis_projection(half_a, basis_a, normal)
        radius_b = basis_projection(half_b, basis_b, normal)
        travel_a = dot(motion_a, normal)
        travel_b = dot(motion_b, normal)
        # Projections are intervals; the additional swept motion extends
        # the lower/upper bounds without altering the SAT candidate axes.
        amin = min(0.0, travel_a) - radius_a - margin
        amax = max(0.0, travel_a) + radius_a + margin
        bmin = center_distance + min(0.0, travel_b) - radius_b - margin
        bmax = center_distance + max(0.0, travel_b) + radius_b + margin
        if amin > bmax or bmin > amax:
            return True
    return False


class SharedRectangleSAT2D(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        source = SAT.read_text(encoding="utf-8")
        begin = source.index("static void _collision_rectangle_rectangle(")
        end = source.index("static void _collision_rectangle_capsule(", begin)
        cls.code = source[begin:end]

    def test_only_identical_bases_skip_duplicate_face_axes(self):
        code = self.code
        self.assertIn("const bool identical_rectangle_axes =", code)
        self.assertIn("p_transform_a.columns[0] == p_transform_b.columns[0]", code)
        self.assertIn("p_transform_a.columns[1] == p_transform_b.columns[1]", code)
        self.assertIn("if (!identical_rectangle_axes) {", code)
        self.assertIn("separator.test_axis(p_transform_a.columns[0].normalized())", code)
        self.assertIn("separator.test_axis(p_transform_a.columns[1].normalized())", code)
        self.assertIn("separator.test_axis(p_transform_b.columns[0].normalized())", code)
        self.assertIn("separator.test_axis(p_transform_b.columns[1].normalized())", code)

    def test_cached_axes_sweeps_margins_and_manifold_remain(self):
        code = self.code
        self.assertLess(code.index("separator.test_previous_axis()"),
                        code.index("const bool identical_rectangle_axes"))
        self.assertLess(code.index("separator.test_cast()"),
                        code.index("const bool identical_rectangle_axes"))
        self.assertIn("if (p_with_margin) {", code)
        self.assertIn("rectangle_A->get_box_axis", code)
        self.assertIn("if (p_cast_A)", code)
        self.assertIn("if (p_cast_B)", code)
        self.assertIn("separator.generate_contacts();", code)
        self.assertLess(code.index("if (!identical_rectangle_axes)"),
                        code.index("if (p_with_margin) {"))

    def test_reduced_two_axes_equal_four_on_10000_random_pairs(self):
        rng = random.Random(20261120)
        for _ in range(10000):
            theta = rng.uniform(-math.pi, math.pi)
            c, s = math.cos(theta), math.sin(theta)
            scale_x = rng.uniform(0.1, 4.0)
            scale_y = rng.uniform(0.1, 4.0)
            shear = rng.uniform(-0.8, 0.8)
            # Exact same potentially sheared, nonuniformly scaled basis
            # on both rectangles: repeated directions remain identical.
            basis = ((c * scale_x, s * scale_x),
                     (c * shear - s * scale_y, s * shear + c * scale_y))
            half_a = (rng.uniform(0.05, 4.0), rng.uniform(0.05, 4.0))
            half_b = (rng.uniform(0.05, 4.0), rng.uniform(0.05, 4.0))
            delta = (rng.uniform(-15, 15), rng.uniform(-15, 15))
            margin = rng.choice((0.0, rng.uniform(0.0, 0.5)))
            motion_a = (rng.uniform(-2.0, 2.0), rng.uniform(-2.0, 2.0))
            motion_b = (rng.uniform(-2.0, 2.0), rng.uniform(-2.0, 2.0))
            self.assertEqual(
                separated(delta, half_a, half_b, basis, basis,
                          basis, margin, motion_a, motion_b),
                separated(delta, half_a, half_b, basis, basis,
                          basis + basis, margin, motion_a, motion_b),
            )

    def test_runtime_compares_identity_shared_rotation_scale_and_different_basis(self):
        code = RUNTIME.read_text(encoding="utf-8")
        self.assertIn("for mode in range(4):", code)
        self.assertIn("basis.scaled_local(Vector2(1.35, 0.8))", code)
        self.assertIn("basis.x.rotated(0.31)", code)
        self.assertIn("for margin in [0.0, 0.03]", code)
        self.assertIn("state.intersect_shape(query, 8)", code)
        self.assertIn("state.collide_shape(query, 8)", code)
        self.assertIn("point.is_finite()", code)

    def test_runner_registers_all_three_benchmarks(self):
        script = STRESS.read_text(encoding="utf-8")
        runner = RUNNER.read_text(encoding="utf-8")
        workload = WORKLOAD.read_text(encoding="utf-8")
        self.assertIn("func run(tree: SceneTree, scale: int, frames: int, orientation: int)", workload)
        self.assertIn("mini(256 * scale, 4096)", workload)
        self.assertIn('"frame_p95_ms": stats["p95"]', workload)
        self.assertIn('"peak_collision_pairs": peak_pairs', workload)
        for suffix, mode in (("axis_aligned", 0), ("shared_rotation", 1), ("misaligned", 2)):
            case = f"physics_rect_sat_{suffix}_2d"
            self.assertIn(f'"{case}"', runner)
            self.assertIn(f'"{case}":', script)
            self.assertIn(f"RectangleSAT2DStress.new().run(self, scale, frames, {mode})", script)
        gd_cases = re.search(r"const CASES := \[([\s\S]*?)\]", script)
        py_cases = re.search(r"^CASES = \(([\s\S]*?)^\)", runner, re.MULTILINE)
        self.assertIsNotNone(gd_cases)
        self.assertIsNotNone(py_cases)
        gd_names = re.findall(r'"([^"]+)"', gd_cases.group(1))
        py_names = re.findall(r'"([^"]+)"', py_cases.group(1))
        self.assertEqual(gd_names, py_names)
        self.assertEqual(len(set(gd_names)), len(gd_names))


if __name__ == "__main__":
    unittest.main()
