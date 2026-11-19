"""Image RGBA8 mask span-copy regression contracts.

These are structural guards, not a substitute for building the native engine
or comparing the Image API's output byte-for-byte.
"""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[3]
CPP = (ROOT / "core/io/image.cpp").read_text(encoding="utf-8")
TESTS = (ROOT / "tests/core/io/test_image.cpp").read_text(encoding="utf-8")
BLIT = CPP.split("void Image::blit_rect_mask(", 1)[1].split("void Image::blend_rect(", 1)[0]


class ImageMaskHotpathTests(unittest.TestCase):
    def test_preserves_existing_null_guards(self):
        self.assertIn("p_src.is_null()", BLIT)
        self.assertIn("p_mask.is_null()", BLIT)

    def test_checks_source_mask_dimensions(self):
        self.assertIn("p_src->width != p_mask->width", BLIT)
        self.assertIn("p_src->height != p_mask->height", BLIT)

    def test_checks_destination_format(self):
        self.assertIn("format != p_src->format", BLIT)

    def test_checks_clipped_intersection(self):
        self.assertIn("_get_clipped_src_and_dest_rects", BLIT)
        self.assertIn("!src_rect.has_area() || !dest_rect.has_area()", BLIT)

    def test_fast_path_rgba8_only(self):
        self.assertIn("p_mask->format == FORMAT_RGBA8", BLIT)

    def test_fast_path_requires_uncompressed_destination(self):
        self.assertIn("!is_compressed()", BLIT)

    def test_fast_path_preserves_aliasing_fallback(self):
        self.assertIn("p_mask.ptr() != this", BLIT)
        self.assertIn("p_src.ptr() != this", BLIT)

    def test_rgba8_alpha_offset_is_fourth_byte(self):
        self.assertIn("mask_data + source_pixel * 4 + 3", BLIT)

    def test_alpha_is_checked_per_pixel(self):
        self.assertIn("mask_alpha[size_t(x) * 4] == 0", BLIT)
        self.assertIn("mask_alpha[size_t(x) * 4] != 0", BLIT)

    def test_copies_opaque_runs_as_contiguous_bytes(self):
        self.assertIn("memcpy(dst_data_ptr + (dest_pixel + run_start) * pixel_size,", BLIT)
        self.assertIn("size_t(x - run_start) * pixel_size", BLIT)

    def test_skips_empty_runs(self):
        self.assertIn("if (run_start != x)", BLIT)

    def test_offsets_use_source_and_destination_strides(self):
        self.assertIn("p_src->width + src_rect.position.x", BLIT)
        self.assertIn("* width + dest_rect.position.x", BLIT)

    def test_fast_path_returns_before_fallback(self):
        self.assertLess(BLIT.index("return;\n\t}\n\n\tRef<Image> msk"), BLIT.index("Ref<Image> msk"))

    def test_fallback_keeps_exact_mask_alpha_semantics(self):
        self.assertIn("msk->get_pixel(src_x, src_y).a != 0", BLIT)

    def test_fallback_keeps_per_byte_copy_for_aliasing(self):
        self.assertIn("for (int k = 0; k < pixel_size; k++)", BLIT)

    def test_native_api_comparison_cases_present(self):
        self.assertIn("[Image][MaskedBlit] RGBA8 runs match scalar RGBAF reference", TESTS)
        self.assertIn("[Image][MaskedBlit] Cropped spans match scalar clipping", TESTS)

    def test_native_aliasing_cases_present(self):
        self.assertIn("[Image][MaskedBlit] Self alias keeps scalar semantics", TESTS)
        self.assertIn("[Image][MaskedBlit] Destination mask alias keeps scalar semantics", TESTS)


if __name__ == "__main__":
    unittest.main()
