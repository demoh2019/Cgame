#!/usr/bin/env python3
"""Source-backed Apple-only single-pass directional shadow regressions."""
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
CPP = (ROOT / "servers/rendering/renderer_rd/forward_mobile/render_forward_mobile.cpp").read_text()
HEADER = (ROOT / "servers/rendering/renderer_rd/forward_mobile/render_forward_mobile.h").read_text()


def function(signature):
    start = CPP.index(signature)
    opening = CPP.index("{", start)
    depth = 0
    for offset in range(opening, len(CPP)):
        if CPP[offset] == "{":
            depth += 1
        elif CPP[offset] == "}":
            depth -= 1
            if depth == 0:
                return CPP[start:offset + 1]
    raise AssertionError("Unclosed renderer method")


class AppleShadowPassTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.setup = function("void RenderForwardMobile::_pre_opaque_render(")
        cls.end = function("void RenderForwardMobile::_render_shadow_end()")
        cls.constructor = function("RenderForwardMobile::RenderForwardMobile()")

    def test_platform_gate_defaults_disabled(self):
        self.assertIn("bool single_pass_directional_shadows = false;", HEADER)
        self.assertIn('single_pass_directional_shadows = RD::get_singleton()->get_device_vendor_name() == "Apple";', self.constructor)

    def test_directional_atlas_is_updated_regardless_of_vendor(self):
        self.assertIn("light_storage->update_directional_shadow_atlas();", self.setup)

    def test_non_apple_clears_atlas_before_splits(self):
        self.assertIn("if (!single_pass_directional_shadows)", self.setup)
        self.assertIn("draw_list_begin(light_storage->direction_shadow_get_fb(), RD::DRAW_CLEAR_DEPTH", self.setup)
        self.assertIn("RD::get_singleton()->draw_list_end();", self.setup)

    def test_single_pass_only_uses_directional_framebuffer(self):
        self.assertIn("single_pass_directional_shadows ? RendererRD::LightStorage::get_singleton()->direction_shadow_get_fb() : RID()", self.end)
        self.assertIn("shadow_pass.framebuffer == directional_fb", self.end)

    def test_single_draw_list_created_only_once_for_contiguous_splits(self):
        self.assertIn("RD::DrawListID directional_draw_list = RD::INVALID_ID;", self.end)
        self.assertIn("if (directional_draw_list == RD::INVALID_ID)", self.end)
        self.assertIn("draw_list_begin(directional_fb, RD::DRAW_CLEAR_DEPTH", self.end)

    def test_each_split_selects_own_viewport_and_resets_scissor(self):
        self.assertIn("draw_list_set_viewport(directional_draw_list, shadow_pass.rect);", self.end)
        self.assertIn("draw_list_disable_scissor(directional_draw_list);", self.end)
        self.assertIn("_render_list(directional_draw_list, fb_format, &render_list_parameters", self.end)

    def test_other_shadows_keep_existing_render_path(self):
        self.assertIn("_render_list_with_draw_list(&render_list_parameters, shadow_pass.framebuffer", self.end)
        self.assertIn("if (directional_draw_list != RD::INVALID_ID)", self.end)
        self.assertIn("directional_draw_list = RD::INVALID_ID;", self.end)

    def test_open_directional_list_is_closed_after_last_split(self):
        last_if = self.end.rindex("if (directional_draw_list != RD::INVALID_ID)")
        self.assertGreater(last_if, self.end.index("_render_list_with_draw_list"))
        self.assertIn("RD::get_singleton()->draw_list_end();", self.end[last_if:])

    def test_source_does_not_unconditionally_force_apple_path(self):
        self.assertNotIn("single_pass_directional_shadows = true;", self.constructor)
        self.assertIn("if (!single_pass_directional_shadows)", self.setup)


if __name__ == "__main__":
    unittest.main()
