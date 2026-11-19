"""Godot #100269: reserve known LocalVector sizes to avoid buffer growth.

Checks that the affected engine subsystems reserve enough capacity before
bulk append, retaining existing element order and allocation semantics.
"""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[3]


def source(path):
    return (ROOT / path).read_text(encoding="utf-8")


class LocalVectorReserveHotpaths(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.retarget = source("scene/3d/retarget_modifier_3d.cpp")
        cls.mesh = source("scene/resources/mesh.cpp")
        cls.surface = source("scene/resources/surface_tool.cpp")
        cls.render = source("servers/rendering/rendering_device.cpp")
        cls.shader = source("servers/rendering/shader_preprocessor.cpp")
        cls.property = source("scene/property_utils.cpp")
        cls.lightmap = source("scene/3d/lightmap_gi.cpp")
        cls.windows = source("platform/windows/display_server_windows.cpp")

    def test_retarget_global_bone_pose_reservation(self):
        self.assertEqual(self.retarget.count("source_poses.reserve(source_bone_ids.size());"), 2)

    def test_mesh_unwrap_reserves_surfaces(self):
        self.assertIn("surfaces_tools.reserve(lightmap_surfaces.size());", self.mesh)

    def test_surface_tool_reserves_index_append(self):
        self.assertIn("index_array.reserve(index_array.size() + nindices.size());", self.surface)

    def test_property_inheritance_reserves_stack(self):
        self.assertIn("r_states_stack.reserve(r_states_stack.size() + inheritance_states.size());", self.property)

    def test_render_remap_reserves_attachment_count(self):
        self.assertIn("attachment_remap.reserve(p_attachments.size());", self.render)

    def test_render_pass_reserves_three_reference_lists(self):
        for member in ("color_references", "input_references", "resolve_references"):
            self.assertIn("subpass." + member + ".reserve(pass->", self.render)

    def test_render_load_and_store_reserve(self):
        self.assertIn("load_ops.reserve(p_attachments.size());", self.render)
        self.assertIn("store_ops.reserve(p_attachments.size());", self.render)

    def test_render_tracker_reserves_textures(self):
        self.assertIn("trackers.reserve(p_texture_attachments.size());", self.render)

    def test_shader_tokens_reserve_character_count(self):
        self.assertIn("result.reserve(p_tokens.size());", self.shader)

    def test_lightmap_bounding_corners_reserve_eight(self):
        self.assertIn("new_probe_positions.reserve(8);", self.lightmap)

    def test_windows_dialog_reserves_buttons(self):
        self.assertIn("buttons.reserve(p_buttons.size());", self.windows)

    def test_windows_destructor_reserves_dialog_entries(self):
        self.assertIn("to_remove.reserve(file_dialogs.size());", self.windows)

    def test_native_capacity_test_exists(self):
        cpp = source("tests/core/templates/test_local_vector.cpp")
        self.assertIn("Reserve known size avoids relocation for bulk append", cpp)
        self.assertIn("CHECK(entries.ptr() == begin);", cpp)

    def test_native_test_covers_content_after_reserve(self):
        cpp = source("tests/core/templates/test_local_vector.cpp")
        self.assertIn("CHECK(entries[i] == i * 3);", cpp)


if __name__ == "__main__":
    unittest.main()
