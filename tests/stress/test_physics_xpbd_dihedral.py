"""Source contracts for optional XPBD dihedral bending in GodotPhysics3D.

Numerical gradient, convergence and compliance checks live in the native
C++ suite tests/servers/test_physics_xpbd_dihedral.cpp. These contracts
do not claim that the full engine has compiled or executed.
"""

from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
DEFS = ROOT / "servers/physics_3d/physics_server_3d.cpp"
SPACE_CPP = ROOT / "modules/godot_physics_3d/godot_space_3d.cpp"
SPACE_H = ROOT / "modules/godot_physics_3d/godot_space_3d.h"
SOFT_CPP = ROOT / "modules/godot_physics_3d/godot_soft_body_3d.cpp"
SOFT_H = ROOT / "modules/godot_physics_3d/godot_soft_body_3d.h"
MATH = ROOT / "servers/physics_xpbd_dihedral.h"
NATIVE = ROOT / "tests/servers/test_physics_xpbd_dihedral.cpp"


class DihedralXPBDContracts(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.defs = DEFS.read_text(encoding="utf-8")
        cls.space_cpp = SPACE_CPP.read_text(encoding="utf-8")
        cls.space_h = SPACE_H.read_text(encoding="utf-8")
        cls.soft_cpp = SOFT_CPP.read_text(encoding="utf-8")
        cls.soft_h = SOFT_H.read_text(encoding="utf-8")
        cls.math = MATH.read_text(encoding="utf-8")
        cls.native = NATIVE.read_text(encoding="utf-8")

    def test_default_off_settings_and_one_time_world_read(self):
        path = "physics/3d/solver/soft_body_xpbd_dihedral_compliance"
        self.assertIn(f'"{path}"', self.defs)
        self.assertIn(f'"{path}", PROPERTY_HINT_RANGE, "0,0.01,0.000001,or_greater"), 0.0)', self.defs)
        self.assertIn(f'GLOBAL_GET("{path}")', self.space_cpp)
        self.assertIn("Math::is_finite(configured_dihedral_compliance)", self.space_cpp)
        self.assertIn("get_soft_body_xpbd_dihedral_compliance()", self.space_h)
        self.assertNotIn("GLOBAL_GET(", self.soft_cpp)

    def test_mesh_adjacency_deterministic_and_nonmanifold_skipped(self):
        code = self.soft_cpp
        self.assertIn("HashMap<uint64_t, EdgeUse> edge_usage", code)
        self.assertIn("LocalVector<uint64_t> edge_order", code)
        self.assertIn("edge_order.push_back(key)", code)
        self.assertIn("for (const uint64_t key : edge_order)", code)
        self.assertIn("usage->occurrences < 3", code)
        self.assertIn("usage->occurrences != 2 || !usage->compatible", code)
        self.assertIn("usage->a == b && usage->b == a", code)
        self.assertIn("usage->c != c", code)
        self.assertIn("nodes[usage->a].s", code)
        self.assertIn("xpbd_dihedral_built = true;", code)
        self.assertIn("xpbd_dihedral_bends.reset();", code)

    def test_bends_have_compact_indices_and_reuse_lambdas(self):
        self.assertIn("uint32_t vertex[4]", self.soft_h)
        self.assertIn("real_t rest_angle", self.soft_h)
        self.assertIn("real_t lambda", self.soft_h)
        self.assertIn("build_xpbd_dihedral_bends()", self.soft_cpp)
        self.assertIn("if (use_dihedral_xpbd)", self.soft_cpp)
        self.assertIn("bend.lambda = 0.0;", self.soft_cpp)
        self.assertIn("physics_xpbd_solve_dihedral(a.x, b.x, c.x, d.x", self.soft_cpp)
        self.assertIn("xpbd_dihedral_bends.reset();", self.soft_cpp)
        self.assertIn("physics_xpbd_solve_triangle_area(", self.soft_cpp)
        self.assertIn("physics_xpbd_solve_distance(", self.soft_cpp)
        self.assertIn("solve_links(1.0, ti);", self.soft_cpp)
        self.assertIn('#include "servers/physics_xpbd_dihedral.h"', self.soft_cpp)

    def test_analytical_signed_gradients_and_wrap_safety(self):
        self.assertIn("Math::atan2(sine, cosine)", self.math)
        self.assertIn("const Vector3 grad_c = normal_a * (-edge_len / normal_a_sq);", self.math)
        self.assertIn("const Vector3 grad_d = normal_b * (-edge_len / normal_b_sq);", self.math)
        self.assertIn("const Vector3 grad_a = -grad_b - grad_c - grad_d;", self.math)
        self.assertIn("if (error > Math::PI)", self.math)
        self.assertIn("error -= Math::TAU;", self.math)
        self.assertIn("double(p_alpha_tilde) * double(r_lambda)", self.math)
        self.assertIn("if (!next_a.is_finite()", self.math)
        self.assertIn("TEST_FORCE_LINK(test_physics_xpbd_dihedral)", self.native)
        self.assertIn("central_difference", self.native)
        self.assertIn("pinned hinge endpoints", self.native)
        self.assertIn("compliance reduces fold correction", self.native)
        self.assertIn("degeneracy, all-pinned", self.native)


if __name__ == "__main__":
    unittest.main()
