"""Source regressions for upstream Godot #125551 (XR lazy color buffers).

These checks cover the production paths that must preserve non-XR rendering
while skipping unnecessary XR allocations; GPU behavior needs device tests.
"""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[3]
RD_DIR = ROOT / "servers" / "rendering" / "renderer_rd" / "storage_rd"
SOURCE = (RD_DIR / "texture_storage.cpp").read_text(encoding="utf-8")
HEADER = (RD_DIR / "texture_storage.h").read_text(encoding="utf-8")
BASE = (ROOT / "servers" / "rendering" / "storage" / "texture_storage.h").read_text(encoding="utf-8")
VIEWPORT = (ROOT / "servers" / "rendering" / "renderer_viewport.cpp").read_text(encoding="utf-8")


def method(source: str, signature: str) -> str:
    start = source.index(signature)
    end = source.index("\n}", start)
    return source[start:end + 2]


class XRRenderTargetLazyColorTests(unittest.TestCase):
    def test_backend_agnostic_hint_has_safe_noop_default(self):
        self.assertIn(
            "virtual void render_target_set_expect_override(RID p_render_target, bool p_expect) {}",
            BASE)

    def test_rd_backend_tracks_expected_override(self):
        self.assertIn("bool expect_override = false;", HEADER)
        self.assertIn("void _ensure_render_target_color(RenderTarget *rt);", HEADER)
        self.assertIn("virtual void render_target_set_expect_override(", HEADER)

    def test_viewport_forwards_enable_and_disable_state(self):
        body = method(VIEWPORT, "void RendererViewport::viewport_set_use_xr(")
        self.assertIn("viewport->use_xr = p_use_xr;", body)
        self.assertIn("render_target_set_expect_override(viewport->render_target, p_use_xr);", body)
        self.assertLess(body.index("render_target_set_expect_override("),
                        body.index("_configure_3d_render_buffers("))

    def test_non_xr_render_target_allocates_eagerly(self):
        body = method(SOURCE, "void TextureStorage::_update_render_target(")
        self.assertIn("if (!rt->expect_override) {", body)
        self.assertIn("_ensure_render_target_color(rt);", body)

    def test_already_overridden_or_allocated_buffers_are_not_recreated(self):
        body = method(SOURCE, "void TextureStorage::_ensure_render_target_color(")
        self.assertIn("rt->color.is_valid() || rt->overridden.color.is_valid()", body)
        self.assertIn("rt->size.width == 0 || rt->size.height == 0", body)
        self.assertIn("RD::get_singleton()->texture_create(", body)

    def test_override_hint_sets_state_without_eager_color_allocation(self):
        body = method(SOURCE, "void TextureStorage::render_target_set_expect_override(")
        self.assertIn("rt->expect_override = p_expect;", body)
        self.assertNotIn("texture_create(", body)

    def test_color_consumers_allocate_on_demand(self):
        functions = (
            "void TextureStorage::render_target_do_msaa_resolve(",
            "RID TextureStorage::render_target_get_rd_framebuffer(",
            "RID TextureStorage::render_target_get_rd_texture(",
            "RID TextureStorage::render_target_get_rd_texture_slice(",
            "void TextureStorage::render_target_do_clear_request(",
            "void TextureStorage::render_target_copy_to_back_buffer(",
        )
        for signature in functions:
            with self.subTest(signature=signature):
                self.assertIn("_ensure_render_target_color(rt);", method(SOURCE, signature))

    def test_get_rd_texture_preserves_override_precedence(self):
        body = method(SOURCE, "RID TextureStorage::render_target_get_rd_texture(")
        self.assertIn("if (rt->overridden.color.is_valid())", body)
        self.assertIn("return rt->overridden.color;", body)
        self.assertIn("return rt->color;", body)
        self.assertGreater(body.index("_ensure_render_target_color(rt);"),
                           body.index("return rt->overridden.color;"))

    def test_skip_eager_allocation_does_not_remove_error_check(self):
        body = method(SOURCE, "void TextureStorage::_ensure_render_target_color(")
        self.assertIn("ERR_FAIL_COND(rt->color.is_null());", body)

    def test_no_old_eager_allocation_todo_remains(self):
        self.assertNotIn("TODO see if we can lazy create this once", SOURCE)


if __name__ == "__main__":
    unittest.main()
