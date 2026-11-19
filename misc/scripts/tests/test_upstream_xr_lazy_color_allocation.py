"""Regression guards for deferred XR render-target color allocation (#125551).

Source-level tests cover the XR hint, allocation guard, resize and lazy read paths.
These do not replace native Vulkan, XR runtime, MSAA, or GPU validation testing.
"""

from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[3]
STORAGE_CPP = (ROOT / "servers/rendering/renderer_rd/storage_rd/texture_storage.cpp").read_text(encoding="utf-8")
STORAGE_H = (ROOT / "servers/rendering/renderer_rd/storage_rd/texture_storage.h").read_text(encoding="utf-8")
BASE_H = (ROOT / "servers/rendering/storage/texture_storage.h").read_text(encoding="utf-8")
VIEWPORT_CPP = (ROOT / "servers/rendering/renderer_viewport.cpp").read_text(encoding="utf-8")


def method(source, signature):
    start = source.index(signature)
    opening = source.index("{", start)
    depth = 0
    for i in range(opening, len(source)):
        if source[i] == "{":
            depth += 1
        elif source[i] == "}":
            depth -= 1
            if depth == 0:
                return source[opening + 1 : i]
    raise AssertionError(f"Unbalanced braces in {signature}")


class XRColorAllocationRegressionTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.update = method(STORAGE_CPP, "void TextureStorage::_update_render_target(RenderTarget *rt)")
        cls.ensure = method(STORAGE_CPP, "void TextureStorage::_ensure_render_target_color(RenderTarget *rt)")
        cls.hint = method(STORAGE_CPP, "void TextureStorage::render_target_set_expect_override(")
        cls.viewport = method(VIEWPORT_CPP, "void RendererViewport::viewport_set_use_xr(")

    def test_base_storage_has_backward_compatible_default_hint(self):
        self.assertRegex(
            BASE_H,
            r"virtual void render_target_set_expect_override\(RID p_render_target, bool p_expect\) \{\}",
        )

    def test_rd_storage_overrides_hint(self):
        self.assertIn(
            "virtual void render_target_set_expect_override(RID p_render_target, bool p_expect) override;",
            STORAGE_H,
        )

    def test_render_target_tracks_override_expectation(self):
        self.assertIn("bool expect_override = false;", STORAGE_H)

    def test_ensure_helper_is_declared(self):
        self.assertIn("void _ensure_render_target_color(RenderTarget *rt);", STORAGE_H)

    def test_xr_enable_sets_hint_for_same_render_target(self):
        self.assertIn(
            "render_target_set_expect_override(viewport->render_target, p_use_xr);",
            self.viewport,
        )

    def test_viewport_sets_state_before_hint(self):
        self.assertLess(self.viewport.index("viewport->use_xr = p_use_xr;"), self.viewport.index("render_target_set_expect_override("))

    def test_hint_is_applied_before_3d_buffers_reconfigured(self):
        self.assertLess(self.viewport.index("render_target_set_expect_override("), self.viewport.index("_configure_3d_render_buffers(viewport);"))

    def test_noop_toggle_avoids_unnecessary_side_effects(self):
        self.assertLess(self.viewport.index("if (viewport->use_xr == p_use_xr)"), self.viewport.index("render_target_set_expect_override("))

    def test_hint_uses_owned_render_target_and_checks_null(self):
        self.assertIn("render_target_owner.get_or_null(p_render_target)", self.hint)
        self.assertIn("ERR_FAIL_NULL(rt);", self.hint)
        self.assertIn("rt->expect_override = p_expect;", self.hint)

    def test_normal_targets_allocate_on_update(self):
        self.assertRegex(self.update, r"if \(!rt->expect_override\) \{\s*_ensure_render_target_color\(rt\);\s*\}")

    def test_update_does_not_eagerly_allocate_color(self):
        self.assertNotIn("rt->color = RD::get_singleton()->texture_create(", self.update)

    def test_helper_prevents_duplicate_allocation(self):
        self.assertRegex(self.ensure, r"if \(rt->color\.is_valid\(\) \|\| rt->overridden\.color\.is_valid\(\)\) \{\s*return;")

    def test_helper_skips_zero_width_or_height(self):
        self.assertIn("rt->size.width == 0 || rt->size.height == 0", self.ensure)

    def test_helper_creates_color_texture(self):
        self.assertIn("rt->color = RD::get_singleton()->texture_create(", self.ensure)

    def test_helper_keeps_multiview_array_layers(self):
        self.assertIn("array_layers = rt->view_count;", self.ensure)

    def test_helper_preserves_msaa_color_resolve(self):
        self.assertIn("rt->msaa != RSE::VIEWPORT_MSAA_DISABLED", self.ensure)

    def test_framebuffer_getter_allocates_before_usage(self):
        body = method(STORAGE_CPP, "RID TextureStorage::render_target_get_rd_framebuffer(")
        self.assertLess(body.index("_ensure_render_target_color(rt);"), body.index("rt->get_framebuffer();"))

    def test_rd_texture_getter_prefers_swapchain_override(self):
        body = method(STORAGE_CPP, "RID TextureStorage::render_target_get_rd_texture(")
        self.assertIn("if (rt->overridden.color.is_valid())", body)
        self.assertLess(body.index("return rt->overridden.color;"), body.index("_ensure_render_target_color(rt);"))

    def test_get_texture_slice_has_lazy_guard(self):
        body = method(STORAGE_CPP, "RID TextureStorage::render_target_get_rd_texture_slice(")
        self.assertIn("_ensure_render_target_color(rt);", body)

    def test_all_other_raw_color_consumers_have_lazy_guard(self):
        for sig in (
            "void TextureStorage::render_target_do_msaa_resolve(",
            "void TextureStorage::render_target_do_clear_request(",
            "void TextureStorage::render_target_copy_to_back_buffer(",
        ):
            with self.subTest(method=sig):
                body = method(STORAGE_CPP, sig)
                self.assertIn("_ensure_render_target_color(rt);", body)


if __name__ == "__main__":
    unittest.main()
