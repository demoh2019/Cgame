"""Godot Forward+ half-resolution SSR upsampling source and numerical tests.

Run: python3 -m unittest tests/servers/rendering/test_ssr_half_resolve.py -v

This validates spatial reconstruction invariants and GPU shader contracts.
It does not replace a real Vulkan/Metal shader compilation and image capture.
"""

import math
from pathlib import Path
import unittest


SHADER = (
    Path(__file__).resolve().parents[3]
    / "servers/rendering/renderer_rd/shaders/effects/screen_space_reflection_resolve.glsl"
)


def footprint(full_size, half_size, pixel):
    """Reproduce the shader's 4-tap pixel-centred bilateral footprint."""
    full_w, full_h = full_size
    half_w, half_h = half_size
    x, y = pixel
    fx = (x + 0.5) * half_w / full_w - 0.5
    fy = (y + 0.5) * half_h / full_h - 0.5
    bx, by = math.floor(fx), math.floor(fy)
    tx, ty = fx - bx, fy - by
    taps = (
        (0, 0, (1.0 - tx) * (1.0 - ty)),
        (1, 0, tx * (1.0 - ty)),
        (0, 1, (1.0 - tx) * ty),
        (1, 1, tx * ty),
    )
    return [
        (
            (min(max(bx + dx, 0), half_w - 1), min(max(by + dy, 0), half_h - 1)),
            weight,
        )
        for dx, dy, weight in taps
    ], (fx, fy)


class HalfResolutionSSRResolveTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.source = SHADER.read_text(encoding="utf-8")

    def test_native_sampler_uses_real_allocated_texture_dimensions(self):
        self.assertIn("ivec2 half_size = textureSize(source_depth_half, 0);", self.source)
        self.assertIn("vec2(half_size) / vec2(params.screen_size)", self.source)
        self.assertIn("ivec2 base_pixel = ivec2(floor(half_tex_coord));", self.source)
        self.assertNotIn("((pixel_pos - 1) / 2)", self.source)

    def test_all_bilateral_sources_clamp_borders_before_fetch(self):
        self.assertIn(
            "ivec2 safe_pixel = clamp(pixel_pos, ivec2(0), half_size - ivec2(1));",
            self.source,
        )
        for sampler in ("source_depth_half", "source_normal_roughness_half", "source_mip_level"):
            self.assertIn(f"texelFetch({sampler}, safe_pixel, 0)", self.source)
            self.assertNotIn(f"texelFetch({sampler}, pixel_pos, 0)", self.source)
        self.assertIn("vec2(safe_pixel) + vec2(0.5)", self.source)

    def test_correct_corner_orientation(self):
        s = self.source
        self.assertIn("weight0 *= (1.0 - bilinear_weights.x) * (1.0 - bilinear_weights.y)", s)
        self.assertIn("weight1 *= bilinear_weights.x * (1.0 - bilinear_weights.y)", s)
        self.assertIn("weight2 *= (1.0 - bilinear_weights.x) * bilinear_weights.y", s)
        self.assertIn("weight3 *= bilinear_weights.x * bilinear_weights.y", s)
        self.assertNotIn("weight0 *= bilinear_weights.x * bilinear_weights.y", s)

    def test_reconstructed_centres_and_odd_resolutions(self):
        sizes = [(1, 1), (2, 2), (3, 5), (11, 7),
                 (1279, 719), (1280, 720), (1919, 1079), (1920, 1080)]
        for full in sizes:
            half = (max(1, full[0] // 2), max(1, full[1] // 2))
            xs = sorted({0, min(1, full[0] - 1), full[0] // 2, full[0] - 1})
            ys = sorted({0, min(1, full[1] - 1), full[1] // 2, full[1] - 1})
            for x in xs:
                for y in ys:
                    with self.subTest(full=full, pixel=(x, y)):
                        taps, (fx, fy) = footprint(full, half, (x, y))
                        self.assertAlmostEqual(sum(w for _, w in taps), 1.0, places=12)
                        for (tx, ty), weight in taps:
                            self.assertTrue(0 <= tx < half[0])
                            self.assertTrue(0 <= ty < half[1])
                            self.assertTrue(0.0 <= weight <= 1.0)
                        x_gradient = sum(pos[0] * weight for pos, weight in taps)
                        y_gradient = sum(pos[1] * weight for pos, weight in taps)
                        self.assertAlmostEqual(x_gradient,
                            min(max(fx, 0.0), half[0] - 1), places=9)
                        self.assertAlmostEqual(y_gradient,
                            min(max(fy, 0.0), half[1] - 1), places=9)

    def test_subpixel_direction_is_not_mirrored(self):
        taps, _ = footprint((1280, 720), (640, 360), (1, 1))
        self.assertAlmostEqual(taps[0][1], 0.5625)
        self.assertAlmostEqual(taps[1][1], 0.1875)
        self.assertAlmostEqual(taps[2][1], 0.1875)
        self.assertAlmostEqual(taps[3][1], 0.0625)

    def test_inverse_tonemap_guards_fp16_energy(self):
        self.assertIn(
            "max(1.0 - dot(color.rgb, rec709_luminance_weights), 0.01)",
            self.source,
        )
        for luma in (0.0, 0.25, 0.8, 0.99, 1.0, 1.01):
            self.assertTrue(math.isfinite(1.0 / max(1.0 - luma, 0.01)))


if __name__ == "__main__":
    unittest.main()
