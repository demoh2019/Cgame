"""Forward+ vertex shader subgroup scalar InstanceData fast path contracts."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[3] / "servers/rendering/renderer_rd/shaders"
SOURCE = (ROOT / "forward_clustered/scene_forward_clustered.glsl").read_text(encoding="utf-8")
MOBILE = (ROOT / "forward_mobile/scene_forward_mobile.glsl").read_text(encoding="utf-8")
VERTEX = SOURCE[SOURCE.index("void vertex_shader("):SOURCE.index("void main()", SOURCE.index("void vertex_shader("))]
MAIN = SOURCE[SOURCE.index("void main()", SOURCE.index("void vertex_shader(")):]

class ScalarInstanceShaderContracts(unittest.TestCase):
    def test_cached_instance_param(self):
        self.assertIn("in InstanceData instance_data", VERTEX)
        self.assertNotIn("in uint instance_index", VERTEX)

    def test_no_repeated_global_instance_data_fetch(self):
        self.assertNotIn("instances.data[instance_index]", VERTEX)

    def test_subgroup_scalar_load(self):
        self.assertIn("subgroupBroadcastFirst(instance_index)", MAIN)
        self.assertIn("instance_data = instances.data[first_instance_index];", MAIN)

    def test_subgroup_load_guard(self):
        self.assertIn("if (first_instance_index == instance_index)", MAIN)

    def test_uses_cached_instance_for_both_motion_passes(self):
        self.assertEqual(MAIN.count("instance_data, draw_call.multimesh_motion_vectors_"), 2)

    def test_current_and_previous_precision(self):
        for name in ("prev_transform", "prev_model_precision", "transform", "model_precision"):
            with self.subTest(name=name):
                self.assertIn("instance_data." + name, MAIN)

    def test_compressed_bounds_are_cached(self):
        self.assertIn("instance_data.compressed_aabb_position_pad.xyz", MAIN)
        self.assertIn("instance_data.compressed_aabb_size_pad.xyz", MAIN)

    def test_light_layers_use_same_instance(self):
        for name in ("omni_lights", "spot_lights", "directional_lights"):
            with self.subTest(name=name):
                self.assertIn(name + ".data[", VERTEX)
        self.assertIn("instance_data.layer_mask", VERTEX)

    def test_forward_fma_precision_path_preserved(self):
        self.assertIn("#define MAT4_MUL_VEC4", SOURCE)
        self.assertIn("gl_Position = MAT4_MUL_VEC4(", VERTEX)

    def test_opaque_and_depth_positions_still_invariant(self):
        self.assertIn("invariant gl_Position;", SOURCE)

    def test_mobile_shader_avoids_position_invariance(self):
        self.assertNotIn("invariant gl_Position;", MOBILE)

    def test_double_precision_transform_mode_preserved(self):
        self.assertIn("#ifdef USE_DOUBLE_PRECISION", VERTEX)
        self.assertIn("AFFINE_MAT_MUL(read_view_matrix, model_matrix)", VERTEX)

if __name__ == "__main__":
    unittest.main()
