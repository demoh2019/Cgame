"""Regression contracts for Godot upstream #125497 and #125553.

These are source-level and allocation-math checks; they cannot replace a native
Cgame build, an AVX-512 Embree run or a GPU renderer integration test.
"""

from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[3]
RAYCAST_CPP = "modules/raycast/raycast_occlusion_cull.cpp"
RAYCAST_H = "modules/raycast/raycast_occlusion_cull.h"
SHADER_BACKENDS = (
    "drivers/gles3/storage/material_storage.cpp",
    "servers/rendering/renderer_rd/storage_rd/material_storage.cpp",
)


def source(relative):
    return (ROOT / relative).read_text(encoding="utf-8")


def function_body(text, start_marker, end_marker):
    assert text.count(start_marker) == 1, start_marker
    return text.split(start_marker, 1)[1].split(end_marker, 1)[0]


class EmbreeMaskAlignmentContracts(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.header = source(RAYCAST_H)
        cls.cpp = source(RAYCAST_CPP)
        cls.clear = function_body(
            cls.cpp,
            "void RaycastOcclusionCull::RaycastHZBuffer::clear() {",
            "void RaycastOcclusionCull::RaycastHZBuffer::resize(",
        )
        cls.resize = function_body(
            cls.cpp,
            "void RaycastOcclusionCull::RaycastHZBuffer::resize(",
            "void RaycastOcclusionCull::RaycastHZBuffer::update_camera_rays(",
        )

    def test_masks_have_pointer_storage_not_local_vector(self):
        self.assertIn("uint32_t *camera_ray_masks = nullptr;", self.header)
        self.assertNotIn("LocalVector<uint32_t> camera_ray_masks;", self.header)

    def test_rays_are_aligned_to_64_bytes(self):
        self.assertIn("const int alignment = 64;", self.resize)
        self.assertIn("static_assert(sizeof(CameraRayTile) % alignment == 0);", self.resize)

    def test_masks_have_an_aligned_stride(self):
        self.assertIn("static_assert((TILE_RAYS * sizeof(uint32_t)) % alignment == 0);", self.resize)

    def test_one_allocation_contains_rays_and_masks(self):
        self.assertIn("memalloc(rays_size + masks_size + alignment)", self.resize)
        self.assertEqual(self.resize.count("memalloc("), 1)

    def test_masks_begin_after_ray_region(self):
        self.assertIn("camera_rays = (CameraRayTile *)aligned_buffer;", self.resize)
        self.assertIn("camera_ray_masks = (uint32_t *)(aligned_buffer + rays_size);", self.resize)

    def test_masks_initialized_to_all_valid(self):
        self.assertIn("memset(camera_ray_masks, ~0, masks_size);", self.resize)

    def test_raycast_passes_aligned_masks_directly(self):
        self.assertIn("scenario.raycast(buffer.camera_rays, buffer.camera_ray_masks, buffer.camera_rays_tile_count);", self.cpp)
        self.assertNotIn("buffer.camera_ray_masks.ptr()", self.cpp)

    def test_clear_resets_both_pointers(self):
        self.assertIn("memfree(camera_rays_unaligned_buffer);", self.clear)
        self.assertIn("camera_rays_unaligned_buffer = nullptr;", self.clear)
        self.assertIn("camera_rays = nullptr;", self.clear)
        self.assertIn("camera_ray_masks = nullptr;", self.clear)

    def test_zero_sized_resize_clears_buffer(self):
        self.assertIn("if (p_size == Size2i()) {", self.resize)
        self.assertIn("clear();", self.resize)

    def test_resize_releases_previous_allocation(self):
        self.assertIn("if (camera_rays_unaligned_buffer) {", self.resize)
        self.assertIn("memfree(camera_rays_unaligned_buffer);", self.resize)

    def test_aligned_layout_for_all_offsets_and_tile_counts(self):
        # Mirrors the C++ offset/size algorithm, not an Embree runtime test.
        for tile_count in (1, 2, 7, 63, 128, 1024):
            rays_size = tile_count * 256  # 256 is a representative 64-byte multiple.
            masks_size = tile_count * 64
            for address in range(1, 256):
                with self.subTest(tile_count=tile_count, address=address):
                    aligned = address + 64 - address % 64
                    mask_address = aligned + rays_size
                    end = address + rays_size + masks_size + 64
                    self.assertEqual(aligned % 64, 0)
                    self.assertEqual(mask_address % 64, 0)
                    self.assertGreaterEqual(mask_address, aligned + rays_size)
                    self.assertLessEqual(mask_address + masks_size, end)


class ShaderInstanceUniformContracts(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.functions = {
            path: function_body(
                source(path),
                "int32_t MaterialStorage::global_shader_parameters_instance_allocate(",
                "void MaterialStorage::global_shader_parameters_instance_free(",
            )
            for path in SHADER_BACKENDS
        }

    def test_both_renderers_clear_allocated_uniforms(self):
        for path, body in self.functions.items():
            with self.subTest(path=path):
                self.assertIn(
                    "memset(&global_shader_uniforms.buffer_values[pos], 0, "
                    "sizeof(GlobalShaderUniforms::Value) * ShaderLanguage::MAX_INSTANCE_UNIFORM_INDICES);",
                    body,
                )

    def test_both_renderers_mark_cleared_slots_dirty(self):
        for path, body in self.functions.items():
            with self.subTest(path=path):
                self.assertIn(
                    "_global_shader_uniform_mark_buffer_dirty("
                    "pos, ShaderLanguage::MAX_INSTANCE_UNIFORM_INDICES);",
                    body,
                )

    def test_clear_happens_before_dirty_notification(self):
        for path, body in self.functions.items():
            with self.subTest(path=path):
                self.assertLess(body.index("memset("), body.index("_global_shader_uniform_mark_buffer_dirty("))

    def test_clear_happens_after_allocation_success_check(self):
        for path, body in self.functions.items():
            with self.subTest(path=path):
                self.assertLess(body.index("ERR_FAIL_COND_V_MSG(pos < 0"), body.index("memset("))

    def test_buffer_usage_is_set_before_clear(self):
        for path, body in self.functions.items():
            with self.subTest(path=path):
                self.assertLess(
                    body.index("buffer_usage[pos].elements = ShaderLanguage::MAX_INSTANCE_UNIFORM_INDICES;"),
                    body.index("memset("),
                )

    def test_allocation_returns_only_after_clearing(self):
        for path, body in self.functions.items():
            with self.subTest(path=path):
                self.assertLess(body.index("memset("), body.index("return pos;"))

    def test_same_number_of_elements_is_cleared_and_marked_dirty(self):
        for path, body in self.functions.items():
            with self.subTest(path=path):
                self.assertEqual(body.count("ShaderLanguage::MAX_INSTANCE_UNIFORM_INDICES"), 4)


if __name__ == "__main__":
    unittest.main()
