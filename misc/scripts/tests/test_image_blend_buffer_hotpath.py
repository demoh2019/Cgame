"""Source-level regression guards for batched Image blend operations."""
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
CPP = (ROOT / "core/io/image.cpp").read_text(encoding="utf-8")
NATIVE = (ROOT / "tests/core/io/test_image.cpp").read_text(encoding="utf-8")

def between(start, end):
    return CPP.split(start, 1)[1].split(end, 1)[0]

class ImageBlendHotpathGuards(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.rect = between("void Image::blend_rect(", "void Image::blend_rect_mask(")
        cls.mask = between("void Image::blend_rect_mask(", "void Image::_repeat_pixel_over_subsequent_memory(")

    def test_unmasked_distinct_image_guard(self):
        self.assertIn("p_src.ptr() != this", self.rect)

    def test_unmasked_compressed_guard(self):
        self.assertIn("!is_compressed()", self.rect)

    def test_unmasked_pointers_loaded_once(self):
        self.assertEqual(self.rect.count("uint8_t *dst_pixels = data.ptrw();"), 1)
        self.assertEqual(self.rect.count("const uint8_t *src_pixels = p_src->data.ptr();"), 1)

    def test_unmasked_row_precalculation(self):
        self.assertIn("const uint32_t src_row =", self.rect)
        self.assertIn("const uint32_t dst_row =", self.rect)

    def test_unmasked_format_aware_pixel_decoding(self):
        self.assertIn("p_src->_get_color_at_ofs(src_pixels, src_row + x)", self.rect)

    def test_unmasked_skip_transparent_source(self):
        self.assertIn("if (sc.a != 0)", self.rect)

    def test_unmasked_preserve_color_blend(self):
        self.assertIn("_get_color_at_ofs(dst_pixels, dst_offset).blend(sc)", self.rect)

    def test_unmasked_fallback_for_self_blits(self):
        self.assertIn("img->get_pixel(src_x, src_y)", self.rect)
        self.assertIn("set_pixel(dst_x, dst_y, dc)", self.rect)

    def test_masked_requires_rgba8(self):
        self.assertIn("p_mask->format == FORMAT_RGBA8", self.mask)

    def test_masked_alias_guards(self):
        self.assertIn("p_src.ptr() != this && p_mask.ptr() != this", self.mask)

    def test_masked_rejects_compressed(self):
        self.assertIn("!is_compressed()", self.mask)

    def test_masked_direct_alpha_byte(self):
        self.assertIn("mask_pixels[size_t(src_offset) * 4 + 3] == 0", self.mask)

    def test_masked_reuses_dest_buffer(self):
        self.assertEqual(self.mask.count("uint8_t *dst_pixels = data.ptrw();"), 1)

    def test_masked_reuses_mask_and_src_buffers(self):
        self.assertEqual(self.mask.count("const uint8_t *mask_pixels = p_mask->data.ptr();"), 1)
        self.assertEqual(self.mask.count("const uint8_t *src_pixels = p_src->data.ptr();"), 1)

    def test_masked_skip_transparent_source(self):
        self.assertIn("if (sc.a != 0)", self.mask)

    def test_masked_preserves_blending_equation(self):
        self.assertIn("_get_color_at_ofs(dst_pixels, dst_offset).blend(sc)", self.mask)

    def test_masked_fallback_retained(self):
        self.assertIn("msk->get_pixel(src_x, src_y).a != 0", self.mask)
        self.assertIn("set_pixel(dst_x, dst_y, dc)", self.mask)

    def test_no_scratch_allocations_in_fastpaths(self):
        for body in (self.rect, self.mask):
            fast = body.split("return;", 1)[0]
            for bad in ("memalloc(", "memnew(", "LocalVector<", "Vector<"):
                self.assertNotIn(bad, fast)

    def test_full_native_blend_matrix(self):
        cases = (
            "Unmasked blend matches per-pixel reference for several formats",
            "RGBA8 mask direct-alpha blend matches scalar reference",
            "Masked blend clipping and no-op regions preserve destination",
            "Copy-on-write source sharing survives blend",
            "Self-blend and destination-mask alias use scalar fallback",
        )
        for case in cases:
            with self.subTest(case=case):
                self.assertIn(f'TEST_CASE("[Image][BlendHotpath] {case}")', NATIVE)

    def test_previous_masked_blit_native_regressions_intact(self):
        self.assertIn("[Image][MaskedBlit]", NATIVE)

if __name__ == "__main__":
    unittest.main()
