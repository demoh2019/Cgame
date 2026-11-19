"""Source contracts for swept structural-edge CCD in GodotPhysics3D.

Supplemental source checks: numerical C++ tests are in
tests/servers/test_physics_xpbd_edge_ccd.cpp. GCC/Clang stand-alone
compilation in the dedicated CI workflow is NOT the full Cgame build.
"""

from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
MATH = ROOT / "servers/physics_xpbd_edge_ccd.h"
EDGE = ROOT / "servers/physics_xpbd_edge_collision.h"
BODY_CPP = ROOT / "modules/godot_physics_3d/godot_soft_body_3d.cpp"
BODY_H = ROOT / "modules/godot_physics_3d/godot_soft_body_3d.h"
SPACE_H = ROOT / "modules/godot_physics_3d/godot_space_3d.h"
NATIVE = ROOT / "tests/servers/test_physics_xpbd_edge_ccd.cpp"
STANDALONE = ROOT / "tests/stress/physics_xpbd_edge_ccd_standalone.cpp"


class EdgeCCDSourceContracts(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.math = MATH.read_text(encoding="utf-8")
        cls.edge = EDGE.read_text(encoding="utf-8")
        cls.body = BODY_CPP.read_text(encoding="utf-8")
        cls.header = BODY_H.read_text(encoding="utf-8")
        cls.space = SPACE_H.read_text(encoding="utf-8")
        cls.native = NATIVE.read_text(encoding="utf-8")
        cls.standalone = STANDALONE.read_text(encoding="utf-8")

    def test_reuses_existing_opt_in_ccd_and_discrete_edge_modes(self):
        self.assertIn("is_soft_body_self_collision_ccd_enabled()", self.space)
        self.assertIn("is_soft_body_self_collision_edge_edge_enabled()", self.body)
        self.assertIn("const bool swept_ccd = get_space()->is_soft_body_self_collision_ccd_enabled();", self.body)
        self.assertIn("if (swept_ccd)", self.body)
        self.assertIn("physics_xpbd_closest_edges(a.x, b.x, c.x, d.x", self.body)
        self.assertIn("physics_xpbd_solve_edge_collision(a.x, b.x, c.x, d.x", self.body)
        self.assertIn('#include "servers/physics_xpbd_edge_ccd.h"', self.body)
        self.assertNotIn("GLOBAL_GET(", self.body)

    def test_swept_bvh_contains_old_and_new_positions(self):
        self.assertIn("edge_bounds.expand_to(nodes[edge.a].q);", self.body)
        self.assertIn("edge_bounds.expand_to(nodes[edge.b].q);", self.body)
        self.assertIn("query.expand_to(a.q);", self.body)
        self.assertIn("query.expand_to(b.q);", self.body)
        self.assertIn("xpbd_self_edge_tree.aabb_query(query, visit_edge);", self.body)
        self.assertIn("MAX_SWEPT_EDGE_TESTS_PER_STEP = 8192", self.body)
        self.assertIn("remaining_swept_tests > 0", self.body)
        self.assertIn("other.index <= edge.index", self.body)
        self.assertIn("_soft_body_edge_key(edge.a, other.a)", self.body)

    def test_cubic_root_is_monotone_bracketed_with_fixed_iteration_count(self):
        self.assertIn("const double raw[4]", self.math)
        self.assertIn("const Vector3 cross1 = du.cross(v0) + u0.cross(dv);", self.math)
        self.assertIn("const double discriminant = c2 * c2 - 3.0 * c3 * c1;", self.math)
        self.assertIn("cut[count++] = 1.0;", self.math)
        self.assertIn("for (int j = 0; j < 28; ++j)", self.math)
        self.assertIn("physics_xpbd_closest_edges(a, b, c, d", self.math)
        self.assertIn("s <= 0.001", self.edge)
        self.assertIn("distance > MAX(real_t(1e-5)", self.math)
        self.assertIn("return true; // Earliest valid interior root", self.math)
        self.assertIn("raw[0] >= 0.0 ? normal : -normal", self.math)

    def test_ccd_rewinds_only_unpinned_vertices_and_reuses_memory(self):
        self.assertIn("LocalVector<SelfEdgeCCDContact> xpbd_self_edge_ccd_contacts;", self.header)
        self.assertIn("LocalVector<real_t> xpbd_self_edge_ccd_min_time;", self.header)
        self.assertIn("contact.time = hit.time;", self.body)
        self.assertIn("safe_time = MAX(real_t(0.0), contact.time - real_t(0.0001))", self.body)
        self.assertIn("xpbd_self_edge_ccd_min_time[id] = MIN(", self.body)
        self.assertIn("if (node.im > 0.0 && xpbd_self_edge_ccd_min_time[i] < 1.0)", self.body)
        self.assertIn("node.x = node.q.lerp(node.x, xpbd_self_edge_ccd_min_time[i]);", self.body)
        self.assertIn("physics_xpbd_solve_swept_edge_edge(a.x, b.x, c.x, d.x", self.body)
        self.assertGreaterEqual(self.body.count("xpbd_self_edge_ccd_contacts.reset();"), 2)
        self.assertGreaterEqual(self.body.count("xpbd_self_edge_ccd_min_time.reset();"), 2)

    def test_mass_weighted_unilateral_correction_is_finite_and_atomic(self):
        self.assertIn("double(p_inv_a) * wa * wa", self.math)
        self.assertIn("double(p_inv_d) * wd * wd", self.math)
        self.assertIn("const double next_lambda_double = MAX(0.0", self.math)
        self.assertIn("!next_a.is_finite() || !next_b.is_finite()", self.math)
        self.assertIn("r_lambda = next_lambda;", self.math)
        self.assertIn("p_inv_a < 0.0 || p_inv_b < 0.0", self.math)

    def test_numerical_and_standalone_regression_coverage(self):
        for phrase in (
            "fast crossing with distant final endpoints",
            "non-crossing, parallel and infinite-line contacts",
            "translation and common-velocity invariant",
            "pin-safe and rejects invalid witnesses",
        ):
            with self.subTest(phrase=phrase):
                self.assertIn(phrase, self.native)
        self.assertIn('#include "servers/physics_xpbd_edge_ccd.h"', self.standalone)
        self.assertIn("physics_xpbd_swept_edge_edge(", self.standalone)
        self.assertIn("physics_xpbd_solve_swept_edge_edge(", self.standalone)


if __name__ == "__main__":
    unittest.main()
