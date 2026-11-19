"""Contracts for single-probe viewport visibility-mask culling."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
SOURCE = (ROOT / "servers/rendering/renderer_scene_cull.cpp").read_text(encoding="utf-8")
REMOVE = SOURCE.split("void RendererSceneCull::scenario_remove_viewport_visibility_mask(", 1)[1].split(
    "void RendererSceneCull::scenario_add_viewport_visibility_mask(", 1)[0]
RENDER = SOURCE.split("void RendererSceneCull::_render_scene(", 1)[1]


class ViewportVisibilityMaskContracts(unittest.TestCase):
    def test_removed_viewport_mask_uses_one_hash_read(self):
        self.assertIn("viewport_visibility_masks.getptr(p_viewport)", REMOVE)
        self.assertNotIn("viewport_visibility_masks.has(p_viewport)", REMOVE)
        self.assertNotIn("viewport_visibility_masks[p_viewport]", REMOVE)
        self.assertIn("scenario->used_viewport_visibility_bits &= ~mask;", REMOVE)

    def test_mask_lookup_precedes_visibility_and_geometry_culling(self):
        self.assertLess(RENDER.index("const uint64_t *mask_ptr = scenario->viewport_visibility_masks.getptr(p_viewport);"),
                        RENDER.index("if (visibility_bin_count > 0) {"))
        self.assertIn("const uint64_t visibility_viewport_mask = mask_ptr != nullptr ? *mask_ptr : 0;", RENDER)

    def test_new_mask_registration_only_if_needed(self):
        self.assertIn("if (visibility_bin_count > 0 && mask_ptr == nullptr)", RENDER)
        self.assertIn("scenario_add_viewport_visibility_mask(scenario->self, p_viewport);", RENDER)
        self.assertEqual(RENDER.count("scenario->viewport_visibility_masks.getptr(p_viewport)"), 2)

    def test_both_culling_stages_share_the_same_mask(self):
        self.assertIn("visibility_cull_data.viewport_mask = visibility_viewport_mask;", RENDER)
        self.assertIn("cull_data.visibility_viewport_mask = visibility_viewport_mask;", RENDER)
        self.assertNotIn("scenario->viewport_visibility_masks.has(p_viewport) ?", RENDER)

    def test_visibility_bin_count_is_cached(self):
        self.assertIn("const int visibility_bin_count = scenario->instance_visibility.get_bin_count();", RENDER)
        self.assertIn("for (int i = visibility_bin_count - 1; i > 0; i--)", RENDER)


if __name__ == "__main__":
    unittest.main()
