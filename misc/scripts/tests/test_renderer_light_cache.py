"""Regression contracts for Godot upstream #114329: cached rendering light vectors.

The renderer must not construct Vector<RID> and Vector<Instance*> inside the
per-frame _render_scene function. Reused vectors retain capacity across frames.
"""
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]


class DirectionalLightCacheTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.cpp = (ROOT / "servers/rendering/renderer_scene_cull.cpp").read_text()
        cls.header = (ROOT / "servers/rendering/renderer_scene_cull.h").read_text()
        cls.body = cls.cpp[cls.cpp.index("cull.frustum = Frustum(planes);"):]

    def test_persistent_directional_light_storage(self):
        self.assertIn("Vector<RID> directional_light_instances;", self.header)

    def test_persistent_shadow_light_storage(self):
        self.assertIn("Vector<Instance *> lights_with_shadow;", self.header)

    def test_clear_each_render_before_visibility_scan(self):
        start = self.body[:1300]
        self.assertIn("directional_light_instances.clear();", start)
        self.assertIn("lights_with_shadow.clear();", start)
        self.assertLess(start.index("directional_light_instances.clear();"), start.index("for (Instance *E : scenario->directional_lights)"))

    def test_no_local_dynamic_allocation_for_lights(self):
        self.assertNotIn("Vector<RID> directional_lights;", self.body[:2000])
        self.assertNotIn("Vector<Instance *> lights_with_shadow;", self.body[:2000])

    def test_upper_bound_retained(self):
        self.assertIn("directional_light_instances.size() >= RendererSceneRender::MAX_DIRECTIONAL_LIGHTS", self.body)

    def test_sdfgi_uses_persistent_vector(self):
        self.assertIn("sdfgi_update_data.directional_lights = &directional_light_instances;", self.body)

    def test_final_light_list_same_buffer(self):
        self.assertIn("scene_cull_result.light_instances.push_back(directional_light_instances[i]);", self.body)

    def test_shadow_culling_still_prepends_shadow_lights(self):
        self.assertIn("lights_with_shadow.push_back(E);", self.body)

    def test_shadow_count_reset_remains(self):
        self.assertIn("cull.shadow_count = 0;", self.body)

    def test_no_old_stack_vector_name(self):
        self.assertNotIn("&directional_lights;", self.body)


if __name__ == "__main__":
    unittest.main()
