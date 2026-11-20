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
TRACE_SHADER = (
    Path(__file__).resolve().parents[3]
    / "servers/rendering/renderer_rd/shaders/effects/screen_space_reflection.glsl"
)

REC709 = (0.2126, 0.7152, 0.0722)


def encode_hit(rgb, confidence):
    """Mirror native tone compression then alpha premultiplication."""
    luma = sum(c * w for c, w in zip(rgb, REC709))
    return tuple(c / (1.0 + max(luma, 0.0)) * confidence for c in rgb)


def decode_hit(encoded, confidence):
    """Unpremultiply tone domain before inverse HDR mapping."""
    if confidence <= 0.0001:
        return (0.0, 0.0, 0.0)
    straight = tuple(c / confidence for c in encoded)
    denom = max(1.0 - sum(c * w for c, w in zip(straight, REC709)), 0.01)
    return tuple(c / denom * confidence for c in straight)


def confidence_weight(alpha):
    """Smoothstep weighting of valid SSR hits inside a bilateral footprint."""
    x = max(0.0, min((alpha - 0.02) / (0.45 - 0.02), 1.0))
    return x * x * (3.0 - 2.0 * x)


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
            "max(1.0 - dot(straight_tonemapped, rec709_luminance_weights), 0.01)",
            self.source,
        )
        for luma in (0.0, 0.25, 0.8, 0.99, 1.0, 1.01):
            self.assertTrue(math.isfinite(1.0 / max(1.0 - luma, 0.01)))

    def test_trace_premultiplies_after_hdr_compression(self):
        source = TRACE_SHADER.read_text(encoding="utf-8")
        self.assertIn("vec3 toned_radiance = hit_radiance / (1.0 + hit_luminance);", source)
        self.assertIn("color = vec4(toned_radiance * validity, validity);", source)
        self.assertNotIn("color.rgb /= 1.0 + dot(color.rgb", source)

    def test_resolve_uses_hit_confidence_not_black_pixels(self):
        self.assertIn("float confidence = clamp(color.a, 0.0, 1.0);", self.source)
        self.assertIn("if (confidence <= 0.0001)", self.source)
        self.assertIn("vec3 straight_tonemapped = color.rgb / confidence;", self.source)
        self.assertIn("color.rgb = (straight_tonemapped / tone_denom) * confidence;", self.source)
        self.assertIn("float confidence_weight = smoothstep(0.02, 0.45, confidence);", self.source)
        self.assertIn("weight_depth * weight_normal * weight_roughness * confidence_weight", self.source)

    def test_partial_alpha_hdr_roundtrip(self):
        for rgb in ((0.0, 0.0, 0.0), (0.7, 0.2, 0.1),
                    (2.0, 6.0, 1.0), (16.0, 4.0, 2.0)):
            for a in (0.005, 0.05, 0.15, 0.4, 0.75, 1.0):
                encoded = encode_hit(rgb, a)
                result = decode_hit(encoded, a)
                for value, original in zip(result, rgb):
                    self.assertAlmostEqual(value, original * a, delta=1e-6)

    def test_zero_hit_is_never_a_black_reflection(self):
        for a in (0.0, 0.00001, 0.0001):
            self.assertEqual(decode_hit((0.0, 0.0, 0.0), a), (0.0, 0.0, 0.0))
        self.assertEqual(confidence_weight(0.0), 0.0)
        self.assertEqual(confidence_weight(1.0), 1.0)
        previous = -1.0
        for i in range(101):
            value = confidence_weight(i / 100.0)
            self.assertTrue(0.0 <= value <= 1.0)
            self.assertGreaterEqual(value, previous)
            previous = value

    def test_sunset_highlight_hue_remains_stable_at_ray_edges(self):
        rgb = (9.0, 2.0, 0.4)
        for a in (0.01, 0.12, 0.34, 1.0):
            result = decode_hit(encode_hit(rgb, a), a)
            self.assertAlmostEqual(result[0] / result[1], rgb[0] / rgb[1], places=6)
            self.assertAlmostEqual(result[1] / result[2], rgb[1] / rgb[2], places=6)
            self.assertTrue(all(math.isfinite(v) for v in result))


if __name__ == "__main__":
    unittest.main()
