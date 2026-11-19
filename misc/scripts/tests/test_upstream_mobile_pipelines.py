"""Static source-contract tests for upstream Godot mobile pipeline prewarm PR #125568.

Native engine compilation and GPU frame-time tests remain necessary.
"""
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
SOURCE = ROOT / "servers/rendering/renderer_rd/forward_mobile/render_forward_mobile.cpp"
HEADER = ROOT / "servers/rendering/renderer_rd/forward_mobile/render_forward_mobile.h"


class TestMobilePipelinePrewarm(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.source = SOURCE.read_text(encoding="utf-8")
        cls.update = cls.source.split("void RenderForwardMobile::update() {", 1)[1].split(
            "/* Render functions */", 1
        )[0]
        cls.ctor = cls.source.split("RenderForwardMobile::RenderForwardMobile() {", 1)[1].split(
            "RenderForwardMobile::~RenderForwardMobile()", 1
        )[0]

    def test_base_update_preserved(self):
        self.assertIn("RendererSceneRenderRD::update();", self.update)

    def test_project_requirements_preserved(self):
        self.assertIn("_update_global_pipeline_data_requirements_from_project();", self.update)

    def test_lighting_requirements_preserved(self):
        self.assertIn("_update_global_pipeline_data_requirements_from_light_storage();", self.update)

    def test_project_data_precedes_warmup(self):
        self.assertLess(self.update.index("_update_global_pipeline_data_requirements_from_project();"),
                        self.update.index("geometry_instance_dirty_list.first()"))

    def test_lighting_data_precedes_warmup(self):
        self.assertLess(self.update.index("_update_global_pipeline_data_requirements_from_light_storage();"),
                        self.update.index("geometry_instance_dirty_list.first()"))

    def test_mobile_geometry_list_traversed(self):
        self.assertIn("SelfList<GeometryInstanceForwardMobile> *E = geometry_instance_dirty_list.first();", self.update)

    def test_iterative_traversal(self):
        self.assertIn("while (E) {", self.update)

    def test_save_next_before_modifying_list(self):
        self.assertLess(self.update.index("SelfList<GeometryInstanceForwardMobile> *next = E->next();"),
                        self.update.index("_geometry_instance_update(E->self());"))

    def test_do_not_update_particles_before_cull(self):
        self.assertIn("E->self()->data->base_type != RSE::INSTANCE_PARTICLES", self.update)

    def test_update_only_nonparticle_nodes(self):
        self.assertRegex(self.update,
                         r"if\s*\(E->self\(\)->data->base_type\s*!=\s*RSE::INSTANCE_PARTICLES\)\s*\{\s*_geometry_instance_update\(E->self\(\)\)")

    def test_iterates_saved_next(self):
        self.assertIn("E = next;", self.update)

    def test_compile_dirty_pipelines_from_update(self):
        self.assertIn("_update_dirty_geometry_pipelines();", self.update)

    def test_compile_after_geometry_updates(self):
        self.assertLess(self.update.index("_geometry_instance_update(E->self());"),
                        self.update.index("_update_dirty_geometry_pipelines();"))

    def test_update_before_render_functions(self):
        self.assertIn("/* Render functions */", self.source)

    def test_mobile_header_declares_update_override(self):
        self.assertIn("void update() override;", HEADER.read_text(encoding="utf-8"))

    def test_shader_group_seeded_after_initialization(self):
        self.assertLess(self.ctor.index("scene_shader.init(defines);"),
                        self.ctor.index("use_multiview = scene_shader.is_multiview_shader_group_enabled()"))

    def test_multiview_state_seeded(self):
        self.assertIn("global_pipeline_data_required.use_multiview = scene_shader.is_multiview_shader_group_enabled();", self.ctor)

    def test_vrs_config_seeded(self):
        self.assertIn("global_pipeline_data_required.use_vrs = is_vrs_supported()", self.ctor)

    def test_vrs_disabled_configuration_excluded(self):
        self.assertIn("vrs_mode != RSE::VIEWPORT_VRS_DISABLED", self.ctor)

    def test_missing_vrs_setting_handled(self):
        self.assertIn('has_setting("rendering/vrs/mode")', self.ctor)

    def test_missing_vrs_setting_defaults_off(self):
        self.assertRegex(self.ctor, r'has_setting\("rendering/vrs/mode"\)\s*\?\s*int\(GLOBAL_GET\("rendering/vrs/mode"\)\)\s*:\s*0')

    def test_original_hdr_configuration_preserved(self):
        self.assertIn("global_pipeline_data_required.use_hdr_render_target = root_hdr_render_target;", self.ctor)

    def test_original_ldr_configuration_preserved(self):
        self.assertIn("global_pipeline_data_required.use_ldr_render_target = !root_hdr_render_target;", self.ctor)

    def test_new_flags_follow_hdr_configuration(self):
        self.assertLess(self.ctor.index("use_ldr_render_target = !root_hdr_render_target;"),
                        self.ctor.index("use_multiview = scene_shader"))

    def test_project_settings_include_present(self):
        self.assertIn('#include "core/config/project_settings.h"', self.source)

    def test_hotpath_does_not_query_vrs_project_setting(self):
        self.assertNotIn('GLOBAL_GET("rendering/vrs/mode")', self.update)


if __name__ == "__main__":
    unittest.main()
