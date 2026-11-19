"""Soft-body pinned-vertex regression contracts.

Jolt-style inverse-mass-zero particles must be kinematic, without residual
velocity/bias and without unpinning a welded visual alias prematurely.

Run: python3 -m unittest discover -s tests/stress -p test_physics_soft_pins.py
Native behavior additionally requires physics_soft_pin_regression.gd.
"""

from pathlib import Path
import unittest

SOURCE = Path(__file__).resolve().parents[2] / "modules/godot_physics_3d/godot_soft_body_3d.cpp"
HEADER = Path(__file__).resolve().parents[2] / "modules/godot_physics_3d/godot_soft_body_3d.h"


class PinnedSoftBodyContracts(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        s = SOURCE.read_text(encoding="utf-8")
        cls.hdr = HEADER.read_text(encoding="utf-8")
        def section(a, b):
            i = s.index(a)
            return s[i:s.index(b, i + len(a))]
        cls.move = section("void GodotSoftBody3D::set_vertex_position(", "void GodotSoftBody3D::pin_vertex(")
        cls.pin = section("void GodotSoftBody3D::pin_vertex(", "void GodotSoftBody3D::unpin_vertex(")
        cls.unpin = section("void GodotSoftBody3D::unpin_vertex(", "void GodotSoftBody3D::unpin_all_vertices(")
        cls.unpin_all = section("void GodotSoftBody3D::unpin_all_vertices(", "bool GodotSoftBody3D::is_vertex_pinned(")
        cls.predict = section("void GodotSoftBody3D::predict_motion(", "void GodotSoftBody3D::solve_constraints(")
        cls.solve = section("void GodotSoftBody3D::solve_constraints(", "void GodotSoftBody3D::solve_links(")
        cls.constants = section("void GodotSoftBody3D::update_link_constants(", "void GodotSoftBody3D::apply_nodes_transform(")

    def test_pin_validates_before_recording_invalid_index(self):
        self.assertLess(self.pin.index("p_index >= (int)map_visual_to_physics.size()"),
                        self.pin.index("pinned_vertices.push_back(p_index)"))

    def test_pin_clears_stale_velocity_bias_and_force(self):
        code = self.pin
        self.assertIn("node.im = 0.0;", code)
        for field in ("v", "bv", "f"):
            self.assertIn(f"node.{field} = Vector3();", code)
        self.assertIn("node.q = node.x;", code)

    def test_explicit_pinned_motion_resets_kinematic_history(self):
        code = self.move
        self.assertIn("if (node.im == 0.0)", code)
        self.assertIn("node.q = p_position;", code)
        self.assertIn("node.x = p_position;", code)
        self.assertIn("node.v = Vector3();", code)

    def test_welded_visual_alias_stays_pinned_until_final_unpin(self):
        code = self.unpin
        self.assertIn("for (const int visual_index : pinned_vertices)", code)
        self.assertIn("map_visual_to_physics[visual_index] == node_index", code)
        self.assertLess(code.index("map_visual_to_physics[visual_index] == node_index"),
                        code.index("node.im = nodes.size() * inv_total_mass"))
        self.assertIn("link_constants_dirty = true;", code)

    def test_pinned_nodes_never_integrate_stale_velocity_or_bias(self):
        code = self.predict
        self.assertIn("if (node.im == 0.0)", code)
        self.assertLess(code.index("if (node.im == 0.0)"),
                        code.index("node.x += node.v * p_delta;"))
        self.assertIn("node.f = Vector3();", code)
        self.assertGreaterEqual(self.solve.count("if (node.im == 0.0)"), 2)
        self.assertIn("node.bv = Vector3();", self.solve)

    def test_link_masses_recalculated_once_when_pins_change(self):
        self.assertIn("bool link_constants_dirty = false;", self.hdr)
        self.assertIn("link_constants_dirty = true;", self.pin)
        self.assertIn("link_constants_dirty = true;", self.unpin_all)
        self.assertIn("if (link_constants_dirty) {\n\t\tupdate_link_constants();", self.solve)
        self.assertIn("link_constants_dirty = false;", self.constants)

    def test_alias_reference_model(self):
        # Two seam vertices can map to one physical node.
        visual_to_physical = (0, 1, 0, 2)
        pinned_visual = {0, 2}
        def physical_is_pinned(node):
            return any(visual_to_physical[index] == node for index in pinned_visual)
        self.assertTrue(physical_is_pinned(0))
        pinned_visual.remove(0)
        self.assertTrue(physical_is_pinned(0))
        pinned_visual.remove(2)
        self.assertFalse(physical_is_pinned(0))


if __name__ == "__main__":
    unittest.main()
