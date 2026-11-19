"""XPBD closed-volume integration source contracts for GodotPhysics3D.

These check API wiring and safety invariants, not the numerical simulation.
Numerical XPBD behavior is checked in tests/servers/test_physics_xpbd_volume.cpp.
"""

from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
GLOBALS = ROOT / "servers/physics_3d/physics_server_3d.cpp"
SPACE_H = ROOT / "modules/godot_physics_3d/godot_space_3d.h"
SPACE_CPP = ROOT / "modules/godot_physics_3d/godot_space_3d.cpp"
BODY_H = ROOT / "modules/godot_physics_3d/godot_soft_body_3d.h"
BODY_CPP = ROOT / "modules/godot_physics_3d/godot_soft_body_3d.cpp"
MATH = ROOT / "servers/physics_xpbd_volume.h"
TEST = ROOT / "tests/servers/test_physics_xpbd_volume.cpp"


class XPBDVolumeSourceContracts(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.config = GLOBALS.read_text(encoding="utf-8")
        cls.space_h = SPACE_H.read_text(encoding="utf-8")
        cls.space_cpp = SPACE_CPP.read_text(encoding="utf-8")
        cls.body_h = BODY_H.read_text(encoding="utf-8")
        cls.body_cpp = BODY_CPP.read_text(encoding="utf-8")
        cls.math = MATH.read_text(encoding="utf-8")
        cls.test = TEST.read_text(encoding="utf-8")

    def test_opt_in_and_space_snapshot(self):
        self.assertIn('"physics/3d/solver/soft_body_xpbd_volume_preservation"), false)', self.config)
        self.assertIn('"physics/3d/solver/soft_body_xpbd_volume_compliance"', self.config)
        self.assertIn('soft_body_xpbd_volume_preservation = GLOBAL_GET(', self.space_cpp)
        self.assertIn('soft_body_xpbd_volume_compliance = Math::is_finite(', self.space_cpp)
        self.assertIn("is_soft_body_xpbd_volume_enabled()", self.space_h)
        self.assertIn("get_soft_body_xpbd_volume_compliance()", self.space_h)
        self.assertIn('#include "servers/physics_xpbd_volume.h"', self.body_cpp)

    def test_closed_oriented_mesh_is_required(self):
        self.assertIn("if (usage->count >= 2)", self.body_cpp)
        self.assertIn("E.value.count != 2 || E.value.winding != 0", self.body_cpp)
        self.assertIn("if (a == b)", self.body_cpp)
        self.assertIn("xpbd_volume_valid = false;", self.body_cpp)
        self.assertIn("xpbd_volume_valid = true;", self.body_cpp)
        self.assertIn("xpbd_volume_topology_checked", self.body_cpp)
        self.assertIn("nodes[0].q", self.body_cpp)
        self.assertIn("Math::is_finite(signed_volume)", self.body_cpp)

    def test_solver_lambdas_and_buffers_are_reused(self):
        self.assertIn("LocalVector<Vector3> xpbd_volume_gradients;", self.body_h)
        self.assertIn("xpbd_volume_gradients.resize(nodes.size());", self.body_cpp)
        self.assertIn("xpbd_volume_lambda = 0.0; // Only accumulate", self.body_cpp)
        self.assertEqual(self.body_cpp.count("solve_xpbd_volume_constraint(volume_alpha);"), 2)
        self.assertIn("xpbd_volume_gradients.reset();", self.body_cpp)
        self.assertIn("xpbd_volume_topology_checked = false;", self.body_cpp)
        self.assertIn("physics_xpbd_volume_delta(", self.body_cpp)
        self.assertIn("physics_xpbd_triangle_volume_terms(", self.body_cpp)
        self.assertIn("if (nodes[i].im > 0.0)", self.body_cpp)
        self.assertIn("const bool use_xpbd = compliance > 0.0", self.body_cpp)
        self.assertIn("solve_links(1.0, ti);", self.body_cpp)
        self.assertNotIn("GLOBAL_GET(", self.body_cpp)

    def test_numerical_native_tests(self):
        for text in (
            "tetra_volume_and_gradients",
            "translation invariant",
            "pinned",
            "zero",
            "compliance",
        ):
            with self.subTest(text=text):
                self.assertIn(text, self.test.lower())


if __name__ == "__main__":
    unittest.main()
