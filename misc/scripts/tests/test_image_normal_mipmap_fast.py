"""Source-contract checks for fast 8/16-bit normal-map mipmap quantization."""

from pathlib import Path
import unittest

CPP = (Path(__file__).resolve().parents[3] / "core/io/image.cpp").read_text(encoding="utf-8")
TESTS = (Path(__file__).resolve().parents[3] / "tests/core/io/test_image.cpp").read_text(encoding="utf-8")

def method(name: str, next_name: str) -> str:
    return CPP.split(name, 1)[1].split(next_name, 1)[0]

class NormalMapMipmapTests(unittest.TestCase):
    def test_u8_uses_fast_unorm(self):
        body = method("void Image::renormalize_uint8(", "void Image::renormalize_float(")
        for ch in ("x", "y", "z"):
            self.assertIn(f"_quantize_unorm_fast<uint8_t>(n.{ch}, 255.0f)", body)

    def test_u16_uses_fast_unorm(self):
        body = method("void Image::renormalize_uint16(", "\nImage::Image(")
        for ch in ("x", "y", "z"):
            self.assertIn(f"_quantize_unorm_fast<uint16_t>(n.{ch}, 65535.0f)", body)

    def test_no_old_rounding_or_extra_scale(self):
        for body in (
            method("void Image::renormalize_uint8(", "void Image::renormalize_float("),
            method("void Image::renormalize_uint16(", "\nImage::Image("),
        ):
            self.assertNotIn("Math::round", body)
            self.assertNotIn("n *= 255;", body)
            self.assertNotIn("n *= 65535;", body)

    def test_normalize_kept_for_u8_and_u16(self):
        for body in (
            method("void Image::renormalize_uint8(", "void Image::renormalize_float("),
            method("void Image::renormalize_uint16(", "\nImage::Image("),
        ):
            self.assertIn("n.normalize();", body)
            self.assertIn("n *= 0.5;", body)

    def test_helper_remains_clamped(self):
        self.assertIn("CLAMP(p_value * p_max + 0.5f, 0.0f, p_max)", CPP)

    def test_mipmap_dispatch_keeps_renormalize_parameter(self):
        self.assertIn("Image::average_4_uint8, Image::renormalize_uint8", CPP)
        self.assertIn("Image::average_4_uint16, Image::renormalize_uint16", CPP)

    def test_native_8_bit_and_16_bit_coverage(self):
        self.assertIn('TEST_CASE("[Image][NormalMipmap] RGB8', TESTS)
        self.assertIn('TEST_CASE("[Image][NormalMipmap] RGB16', TESTS)

    def test_native_unit_normal_and_determinism(self):
        self.assertIn('TEST_CASE("[Image][NormalMipmap] Nonaxis', TESTS)
        self.assertIn('TEST_CASE("[Image][NormalMipmap] Mipmap renormalization is deterministic', TESTS)

if __name__ == "__main__":
    unittest.main()
