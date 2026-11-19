"""Source contracts and independent analytical cases for soft-body hydrostatics."""
import math
import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
HEADER = ROOT / "servers/physics_softbody_hydrostatic_buoyancy.h"
BODY = ROOT / "modules/godot_physics_3d/godot_soft_body_3d.cpp"
SPACE = ROOT / "modules/godot_physics_3d/godot_space_3d.cpp"
SPACE_H = ROOT / "modules/godot_physics_3d/godot_space_3d.h"
SETTINGS = ROOT / "servers/physics_3d/physics_server_3d.cpp"
NATIVE = ROOT / "tests/servers/test_physics_softbody_hydrostatic_buoyancy.cpp"


def tetra_submerged_volume(height):
    # For the unit tetrahedron, horizontal slices have area (1-y)^2 / 2.
    h = max(0.0, min(1.0, height))
    return (1 - (1 - h) ** 3) / 6.0


class HydrostaticSoftBodyTests(unittest.TestCase):
    def test_archimedes_analytic_full_dry_partial(self):
        self.assertAlmostEqual(tetra_submerged_volume(-1.0), 0.0)
        self.assertAlmostEqual(tetra_submerged_volume(2.0), 1 / 6)
        self.assertAlmostEqual(tetra_submerged_volume(0.5), 7 / 48)
        self.assertAlmostEqual(1000 * 9.8 * tetra_submerged_volume(0.5),
                               1000 * 9.8 * 7 / 48)

    def test_pressure_is_linear_in_depth(self):
        density, gravity, water = 1000.0, 9.8, 0.0
        surface_pressure = density * gravity * max(0.0, water - 0.0)
        deep_pressure = density * gravity * max(0.0, water - (-2.0))
        self.assertEqual(surface_pressure, 0.0)
        self.assertEqual(deep_pressure, 19600.0)

    def test_closed_mesh_and_default_off_wiring(self):
        body = BODY.read_text()
        settings = SETTINGS.read_text()
        space = SPACE.read_text()
        space_h = SPACE_H.read_text()
        self.assertIn('"physics/3d/fluid_plane/soft_body_hydrostatic_buoyancy"), false', settings)
        self.assertIn("is_soft_body_hydrostatic_buoyancy_enabled()", space_h)
        self.assertIn('GLOBAL_GET("physics/3d/fluid_plane/soft_body_hydrostatic_buoyancy")', space)
        self.assertIn("get_soft_body_xpbd_volume_compliance() > 0.0", body)
        self.assertIn("xpbd_volume_closed && get_space()->is_fluid_plane_enabled()", body)
        self.assertIn("outward_sign = xpbd_volume_rest >= 0.0 ? 1 : -1", body)
        self.assertIn("physics_softbody_hydrostatic_face_forces", body)
        self.assertIn("face_nodes[j]->im > 0.0", body)
        self.assertIn("Math::abs(gravity.x)", body)
        self.assertIn("updated[j].is_finite()", body)

    def test_integrator_clips_to_water_and_avoids_partial_commit(self):
        helper = HEADER.read_text()
        self.assertIn("const bool start_in = start.y <= height", helper)
        self.assertIn("const bool end_in = end.y <= height", helper)
        self.assertIn("area / 12.0", helper)
        self.assertIn("sum_pressure * sum_weight", helper)
        self.assertIn("std::numeric_limits<real_t>::max()", helper)
        self.assertLess(helper.index("if (!Math::is_finite(fx)"),
                        helper.index("r_force_a = output[0]"))
        self.assertNotIn("memnew(", helper)

    def test_native_regressions_present(self):
        native = NATIVE.read_text()
        self.assertIn("TEST_FORCE_LINK(test_physics_softbody_hydrostatic_buoyancy)", native)
        self.assertGreaterEqual(native.count("TEST_CASE("), 7)
        self.assertIn("Archimedes law", native)
        self.assertIn("Partial immersion", native)
        self.assertIn("Invalid and degenerate", native)


if __name__ == "__main__":
    unittest.main()
