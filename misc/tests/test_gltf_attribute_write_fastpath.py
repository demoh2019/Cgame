"""GLTF mesh attribute packing must use one writable buffer per attribute."""
from pathlib import Path
import unittest

SRC = (Path(__file__).resolve().parents[2] / "modules/gltf/gltf_document.cpp").read_text(encoding="utf-8")
BLOCK = SRC.split('attributes["POSITION"] = GLTFAccessor::encode_new_accessor_from_vector3s', 1)[1].split(
    'attributes["INDICES"]', 1)[0] if 'attributes["INDICES"]' in SRC else SRC.split(
    'attributes["POSITION"] = GLTFAccessor::encode_new_accessor_from_vector3s', 1)[1].split(
    'Vector<int32_t> mesh_indices = array[Mesh::ARRAY_INDEX]', 1)[0]


class GLTFAttributeWriteContracts(unittest.TestCase):
    def test_tangent_and_normal_buffers_acquired_once(self):
        self.assertIn("Color *attribs_write = attribs.ptrw();", BLOCK)
        self.assertIn("Vector3 *attribs_write = attribs.ptrw();", BLOCK)
        self.assertNotIn("attribs.write[i]", BLOCK)

    def test_joint_buffers_reuse_writable_pointers(self):
        self.assertIn("Vector4i *attribs_write = attribs.ptrw();", BLOCK)
        self.assertIn("Vector4i *joints_0_write = joints_0.ptrw();", BLOCK)
        self.assertIn("Vector4i *joints_1_write = joints_1.ptrw();", BLOCK)
        self.assertNotIn("joints_0.write[vertex_i]", BLOCK)
        self.assertNotIn("joints_1.write[vertex_i]", BLOCK)

    def test_weight_buffers_reuse_writable_pointers(self):
        self.assertIn("Vector4 *attribs_write = attribs.ptrw();", BLOCK)
        self.assertIn("Vector4 *weights_0_write = weights_0.ptrw();", BLOCK)
        self.assertIn("Vector4 *weights_1_write = weights_1.ptrw();", BLOCK)
        self.assertNotIn("weights_0.write[vertex_i]", BLOCK)
        self.assertNotIn("weights_1.write[vertex_i]", BLOCK)

    def test_normalization_and_invalid_weight_fallback_still_exist(self):
        self.assertIn("Vector3(a[i]).normalized()", BLOCK)
        self.assertIn("Math::is_zero_approx(divisor) || !Math::is_finite(divisor)", BLOCK)
        self.assertIn("weights_0_write[vertex_i] = Vector4(1, 0, 0, 0);", BLOCK)
        self.assertIn("weights_1_write[vertex_i] = Vector4(0, 0, 0, 0);", BLOCK)

    def test_attribute_serialization_is_preserved(self):
        for label in ('"TANGENT"', '"NORMAL"', '"JOINTS_0"', '"JOINTS_1"',
                      '"WEIGHTS_0"', '"WEIGHTS_1"'):
            self.assertIn(f'attributes[{label}]', BLOCK)


if __name__ == "__main__":
    unittest.main()
