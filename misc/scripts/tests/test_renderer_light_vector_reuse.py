#!/usr/bin/env python3
"""Source-backed render-cull lifetime and light-list reuse contracts."""
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]


def read(path):
    return (ROOT / path).read_text(encoding="utf-8")


class RenderCullMemoryTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.header = read("servers/rendering/renderer_scene_cull.h")
        text = read("servers/rendering/renderer_scene_cull.cpp")
        cls.method = text.split("void RendererSceneCull::_render_scene(", 1)[1].split(
            "\nvoid RendererSceneCull::", 1)[0]

    def test_vectors_retain_capacity_between_frames(self):
        self.assertIn("Vector<RID> directional_light_instances;", self.header)
        self.assertIn("Vector<Instance *> lights_with_shadow;", self.header)
        self.assertIn("directional_light_instances.clear();", self.method)
        self.assertIn("lights_with_shadow.clear();", self.method)
        self.assertNotIn("Vector<RID> directional_lights;", self.method)
        self.assertNotIn("Vector<Instance *> lights_with_shadow;", self.method)

    def test_both_lists_reset_before_enumerating_lights(self):
        loop = self.method.index("for (Instance *E : scenario->directional_lights)")
        self.assertLess(self.method.index("directional_light_instances.clear();"), loop)
        self.assertLess(self.method.index("lights_with_shadow.clear();"), loop)
        self.assertLess(self.method.index("cull.shadow_count = 0;"), loop)

    def test_render_light_limit_is_preserved(self):
        self.assertIn(
            "directional_light_instances.size() >= RendererSceneRender::MAX_DIRECTIONAL_LIGHTS",
            self.method)
        self.assertIn("directional_light_instances.push_back(light->instance);", self.method)
        self.assertIn("lights_with_shadow.push_back(E);", self.method)

    def test_shadow_count_is_based_on_current_frame(self):
        self.assertIn("set_directional_shadow_count(lights_with_shadow.size());", self.method)
        self.assertIn("for (int i = 0; i < lights_with_shadow.size(); i++)", self.method)

    def test_sdfgi_uses_member_vector_with_stable_lifetime(self):
        self.assertIn("sdfgi_update_data.directional_lights = &directional_light_instances;", self.method)
        self.assertNotIn("sdfgi_update_data.directional_lights = &directional_lights;", self.method)

    def test_culling_appends_every_selected_light(self):
        self.assertIn(
            "scene_cull_result.light_instances.push_back(directional_light_instances[i]);",
            self.method)
        self.assertIn("for (int i = 0; i < directional_light_instances.size(); i++)", self.method)

    def test_no_reserve_or_shrink_per_render(self):
        self.assertNotIn("directional_light_instances.reserve(", self.method)
        self.assertNotIn("lights_with_shadow.reserve(", self.method)
        self.assertNotIn("directional_light_instances.shrink_to_fit(", self.method)
        self.assertNotIn("lights_with_shadow.shrink_to_fit(", self.method)


if __name__ == "__main__":
    unittest.main()
