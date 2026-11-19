"""Source contracts for opt-in, allocation-free soft-body shape matching.

The real mathematical implementation is C++ in
servers/physics_softbody_shape_matching.h. Full Cgame native tests and
actual scene profiling remain necessary after these structural checks.
"""

from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
MATH = ROOT / "servers/physics_softbody_shape_matching.h"
BODY = ROOT / "modules/godot_physics_3d/godot_soft_body_3d.cpp"
DEFS = ROOT / "servers/physics_3d/physics_server_3d.cpp"
SPACE = ROOT / "modules/godot_physics_3d/godot_space_3d.cpp"
SPACE_H = ROOT / "modules/godot_physics_3d/godot_space_3d.h"
NATIVE = ROOT / "tests/servers/test_physics_softbody_shape_matching.cpp"
STANDALONE = ROOT / "tests/stress/physics_softbody_shape_matching_standalone.cpp"
MOCK = ROOT / "tests/stress/mock_shape_matching/core/math/vector3.h"


class CorotationalShapeMatchingContracts(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.math = MATH.read_text(encoding="utf-8")
        cls.body = BODY.read_text(encoding="utf-8")
        cls.defs = DEFS.read_text(encoding="utf-8")
        cls.space = SPACE.read_text(encoding="utf-8")
        cls.space_h = SPACE_H.read_text(encoding="utf-8")
        cls.native = NATIVE.read_text(encoding="utf-8")
        cls.standalone = STANDALONE.read_text(encoding="utf-8")
        cls.mock = MOCK.read_text(encoding="utf-8")

    def test_default_off_configuration_and_cached_rate(self):
        self.assertIn('"physics/3d/solver/soft_body_shape_matching_rate"', self.defs)
        self.assertIn('"physics/3d/solver/soft_body_shape_matching_rate", PROPERTY_HINT_RANGE, "0,1000,0.1,or_greater,suffix:1/s"), 0.0)', self.defs)
        self.assertIn('GLOBAL_GET("physics/3d/solver/soft_body_shape_matching_rate")', self.space)
        self.assertIn("Math::is_finite(configured_shape_matching_rate)", self.space)
        self.assertIn("get_soft_body_shape_matching_rate()", self.space_h)
        self.assertNotIn("GLOBAL_GET(", self.body)
        self.assertIn("if (shape_matching_rate > real_t(0.0) && p_delta > real_t(0.0)", self.body)
        self.assertIn("1.0 - Math::exp(-double(shape_matching_rate) * double(p_delta))", self.body)

    def test_shape_projector_fits_proper_rotation_without_allocations(self):
        code = self.math
        self.assertIn("const uint32_t count = r_nodes.size();", code)
        self.assertIn("const double inverse_count = 1.0 / double(count);", code)
        self.assertIn("double h[3][3] = {};", code)
        self.assertIn("double k[4][4] = {};", code)
        self.assertIn("double eigenvectors[4][4] = {};", code)
        self.assertIn("for (int iteration = 0; iteration < 48; ++iteration)", code)
        self.assertIn("const double tangent = (tau >= 0.0 ? 1.0 : -1.0)", code)
        self.assertIn("const double rotation[3][3] = {", code)
        self.assertNotIn("memnew(", code)
        self.assertNotIn("resize(", code)
        self.assertNotIn("GLOBAL_GET(", code)

    def test_atomic_positions_and_exact_pins(self):
        self.assertIn("if (mobile_count == 0)", self.math)
        self.assertIn("!node.s.is_finite() || !node.x.is_finite()", self.math)
        self.assertIn("node.im < 0.0", self.math)
        self.assertIn("for (uint32_t i = 0; i < count; ++i) {", self.math)
        self.assertIn("if (r_nodes[i].im > 0.0 && !projected(r_nodes[i]).is_finite())", self.math)
        self.assertIn("r_nodes[i].x = projected(r_nodes[i]);", self.math)
        self.assertLess(self.math.index("!projected(r_nodes[i]).is_finite()"),
                        self.math.index("r_nodes[i].x = projected(r_nodes[i]);"))

    def test_shape_stage_runs_after_material_and_before_contacts(self):
        self.assertIn('#include "servers/physics_softbody_shape_matching.h"', self.body)
        self.assertIn("physics_softbody_project_shape_matching(nodes, real_t(MIN(1.0, rate_fraction)))", self.body)
        self.assertLess(self.body.index("solve_volume_constraint(volume_alpha, volume_lambda);"),
                        self.body.index("physics_softbody_project_shape_matching(nodes,"))
        self.assertLess(self.body.index("physics_softbody_project_shape_matching(nodes,"),
                        self.body.index("solve_self_collisions(p_delta);"))
        self.assertLess(self.body.index("physics_softbody_project_shape_matching(nodes,"),
                        self.body.index("node.v = (node.x - node.q) * vc;"))

    def test_native_and_standalone_numerical_coverage(self):
        self.assertIn("TEST_FORCE_LINK(test_physics_softbody_shape_matching)", self.native)
        for phrase in ("rigid translations and rotations unchanged",
                       "restores sheared soft solid",
                       "restores totally collapsed geometry",
                       "preserves proper orientation",
                       "respects pins and rejects invalid inputs"):
            self.assertIn(phrase, self.native)
        self.assertIn('#include "servers/physics_softbody_shape_matching.h"', self.standalone)
        self.assertIn("i < 6000 && ok", self.standalone)
        self.assertIn("collapsed geometry deterministic rest recovery", self.standalone)
        self.assertIn("struct Vector3", self.mock)


if __name__ == "__main__":
    unittest.main()
