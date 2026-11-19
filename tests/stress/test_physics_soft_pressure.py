"""Soft-body zero-volume pressure and dead link-gradient regressions.

Run: python3 -m unittest discover -s tests/stress -p 'test_physics_soft_pressure.py'
This checks source invariants and geometric reference cases; native integration
and performance tests still require the Cgame editor binary.
"""

from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[2]
CPP = ROOT / "modules/godot_physics_3d/godot_soft_body_3d.cpp"
HEADER = ROOT / "modules/godot_physics_3d/godot_soft_body_3d.h"


def six_times_volume(a, b, c, origin=(0.0, 0.0, 0.0)):
    u = [a[i] - origin[i] for i in range(3)]
    v = [b[i] - origin[i] for i in range(3)]
    w = [c[i] - origin[i] for i in range(3)]
    cross = (v[1] * w[2] - v[2] * w[1],
             v[2] * w[0] - v[0] * w[2],
             v[0] * w[1] - v[1] * w[0])
    return sum(u[i] * cross[i] for i in range(3))


class SoftBodyPressureContracts(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        source = CPP.read_text(encoding="utf-8")
        start = source.index("void GodotSoftBody3D::apply_forces(")
        end = source.index("Vector3 GodotSoftBody3D::_compute_area_windforce(", start)
        cls.forces = source[start:end]
        start = source.index("void GodotSoftBody3D::solve_constraints(")
        end = source.index("void GodotSoftBody3D::solve_links(", start)
        cls.solver = source[start:end]
        cls.header = HEADER.read_text(encoding="utf-8")

    def test_volume_only_computed_when_pressure_active(self):
        code = self.forces
        self.assertIn("const bool apply_pressure = pressure_coefficient > CMP_EPSILON", code)
        self.assertIn("if (!apply_pressure && !apply_wind)", code)
        self.assertIn("if (apply_pressure) {\n\t\t\tvolume +=", code)
        self.assertIn("if (apply_wind) {", code)

    def test_degenerate_mesh_cannot_divide_by_zero(self):
        code = self.forces
        self.assertIn("if (!(absolute_volume > CMP_EPSILON))", code)
        self.assertLess(code.index("if (!(absolute_volume > CMP_EPSILON))"),
                        code.index("pressure_coefficient / absolute_volume"))
        self.assertIn("return;", code[code.index("if (!(absolute_volume > CMP_EPSILON))"):])

    def test_no_unused_link_gradient_data_or_division(self):
        self.assertNotIn("Vector3 c3;", self.header)
        self.assertNotIn("real_t c2 =", self.header)
        self.assertNotIn("link.c3 =", self.solver)
        self.assertNotIn("link.c2 =", self.solver)
        self.assertIn("solve_links(1.0, ti);", self.solver)

    def test_planar_face_has_zero_enclosed_volume(self):
        self.assertEqual(six_times_volume((1, 0, 0), (0, 1, 0), (2, 1, 0)), 0.0)

    def test_tetrahedral_face_signed_volume(self):
        self.assertEqual(six_times_volume((1, 0, 0), (0, 1, 0), (0, 0, 1)), 1.0)


if __name__ == "__main__":
    unittest.main()
