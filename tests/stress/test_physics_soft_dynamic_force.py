"""SoftBody3D total central impulse/force with kinematic pins.

Run: python3 -m unittest discover -s tests/stress -p test_physics_soft_dynamic_force.py -v
Mathematical conservation checks and source contracts; native physics still
requires a compiled Cgame editor to confirm motion in representative scenes.
"""
from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[2]
CPP = ROOT / "modules/godot_physics_3d/godot_soft_body_3d.cpp"
HEADER = ROOT / "modules/godot_physics_3d/godot_soft_body_3d.h"


def sum_dynamic_impulses(total_impulse, count):
    """Vector component delivered to each dynamic particle."""
    if count == 0:
        return 0.0
    return sum(total_impulse / count for _ in range(count))


def apply_pin(current_dynamic, pinned, physical_node):
    """Reference to prevent visual aliases from double-decrementing."""
    if physical_node in pinned:
        return current_dynamic
    pinned.add(physical_node)
    return current_dynamic - 1


def apply_unpin(current_dynamic, pinned_visual, visual_to_physical, visual_index):
    """Remove only the last visual alias before releasing the physical pin."""
    physical_node = visual_to_physical[visual_index]
    pinned_visual.discard(visual_index)
    if physical_node not in (visual_to_physical[v] for v in pinned_visual):
        return current_dynamic + 1
    return current_dynamic


class SoftBodyDynamicForceContracts(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        code = CPP.read_text(encoding="utf-8")
        cls.hdr = HEADER.read_text(encoding="utf-8")
        def block(start, end):
            begin = code.index(start)
            return code[begin:code.index(end, begin)]
        cls.pin = block("void GodotSoftBody3D::pin_vertex(", "void GodotSoftBody3D::unpin_vertex(")
        cls.unpin = block("void GodotSoftBody3D::unpin_vertex(", "void GodotSoftBody3D::unpin_all_vertices(")
        cls.unpin_all = block("void GodotSoftBody3D::unpin_all_vertices(", "bool GodotSoftBody3D::is_vertex_pinned(")
        cls.impulse = block("void GodotSoftBody3D::apply_central_impulse(", "void GodotSoftBody3D::apply_central_force(")
        cls.force = block("void GodotSoftBody3D::apply_central_force(", "void GodotSoftBody3D::apply_node_bias_impulse(")
        cls.mesh = block("bool GodotSoftBody3D::create_from_trimesh(", "void GodotSoftBody3D::generate_bending_constraints(")
        cls.destroy = block("void GodotSoftBody3D::destroy()", "void GodotSoftBodyShape3D::update_bounds()")

    def test_dynamic_count_is_one_scalar_not_a_per_vertex_array(self):
        self.assertIn("uint32_t dynamic_node_count = 0;", self.hdr)
        self.assertNotIn("LocalVector<uint32_t> dynamic_node_count", self.hdr)

    def test_central_impulse_uses_dynamic_particle_count(self):
        self.assertIn("if (dynamic_node_count == 0)", self.impulse)
        self.assertIn("p_impulse / real_t(dynamic_node_count)", self.impulse)
        self.assertIn("if (node.im > 0.0)", self.impulse)
        self.assertNotIn("p_impulse / nodes.size()", self.impulse)

    def test_central_force_uses_dynamic_particle_count(self):
        self.assertIn("if (dynamic_node_count == 0)", self.force)
        self.assertIn("p_force / real_t(dynamic_node_count)", self.force)
        self.assertIn("if (node.im > 0.0)", self.force)
        self.assertNotIn("p_force / nodes.size()", self.force)

    def test_mesh_sets_count_before_pin_restoration(self):
        self.assertIn("dynamic_node_count = node_count;", self.mesh)
        self.assertIn("if (node.im > 0.0) {\n\t\t\t--dynamic_node_count;", self.mesh)
        self.assertLess(self.mesh.index("dynamic_node_count = node_count;"),
                        self.mesh.index("--dynamic_node_count;"))

    def test_pinning_aliases_cannot_decrement_twice(self):
        self.assertIn("if (node.im > 0.0)", self.pin)
        self.assertIn("--dynamic_node_count;", self.pin)
        self.assertLess(self.pin.index("if (node.im > 0.0)"),
                        self.pin.index("node.im = 0.0;"))
        self.assertIn("map_visual_to_physics[visual_index] == node_index", self.unpin)
        self.assertIn("if (node.im == 0.0) {\n\t\t\t\t\t++dynamic_node_count;", self.unpin)

    def test_unpin_all_cannot_double_count_welded_aliases(self):
        self.assertIn("if (node.im == 0.0) {", self.unpin_all)
        self.assertIn("++dynamic_node_count;", self.unpin_all)
        self.assertLess(self.unpin_all.index("++dynamic_node_count;"),
                        self.unpin_all.index("node.im = inv_node_mass;"))
        self.assertIn("dynamic_node_count = 0;", self.destroy)

    def test_total_external_impulse_preserved_for_all_pin_ratios(self):
        for total in (-7.0, -0.25, 0.0, 0.75, 15.0):
            for free_count in (1, 2, 3, 15, 4096):
                with self.subTest(impulse=total, free_count=free_count):
                    self.assertAlmostEqual(sum_dynamic_impulses(total, free_count), total, places=8)

    def test_fully_pinned_body_receives_no_force(self):
        self.assertEqual(sum_dynamic_impulses(50.0, 0), 0.0)

    def test_alias_reference_model_and_mass_conservation(self):
        visual_to_physical = (0, 1, 0, 2, 3, 2)
        pinned_physical = set()
        count = 4
        count = apply_pin(count, pinned_physical, 0)
        self.assertEqual(count, 3)
        count = apply_pin(count, pinned_physical, 0)
        self.assertEqual(count, 3)
        pinned_visual = {0, 2}
        count = apply_unpin(count, pinned_visual, visual_to_physical, 0)
        self.assertEqual(count, 3)
        count = apply_unpin(count, pinned_visual, visual_to_physical, 2)
        self.assertEqual(count, 4)
        self.assertAlmostEqual(sum_dynamic_impulses(8.0, count), 8.0)


if __name__ == "__main__":
    unittest.main()
