"""Regression guard for the screen-space roughness limiter's edge pixels.

Run: python3 -m unittest tests/servers/rendering/test_roughness_limiter_bounds.py
This is a source-contract and CPU-footprint check, not a GPU image test.
"""

from pathlib import Path
import unittest


SHADER = (
    Path(__file__).resolve().parents[3]
    / "servers/rendering/renderer_rd/shaders/effects/roughness_limiter.glsl"
)


def safe_texels(width: int, height: int, x: int, y: int):
    """The shader's 2x2 footprint with final-texel replication at the border."""
    last_x, last_y = width - 1, height - 1
    return [
        (min(x + i, last_x), min(y + j, last_y))
        for i in range(2)
        for j in range(2)
    ]


class RoughnessLimiterBoundsTest(unittest.TestCase):
    def test_shader_uses_inclusive_dispatch_boundary(self):
        source = SHADER.read_text(encoding="utf-8")
        self.assertIn("greaterThanEqual(pos, params.screen_size)", source)
        self.assertNotIn("greaterThan(pos, params.screen_size)", source)

    def test_shader_clamps_normal_fetch_to_valid_texels(self):
        source = SHADER.read_text(encoding="utf-8")
        self.assertIn("ivec2 last_pixel = params.screen_size - ivec2(1);", source)
        self.assertIn(
            "ivec2 sample_pos = min(pos + ivec2(i, j), last_pixel);", source
        )
        self.assertIn("texelFetch(source_normal, sample_pos, 0)", source)
        self.assertNotIn("texelFetch(source_normal, pos + ivec2(i, j), 0)", source)

    def test_corners_have_no_out_of_bounds_taps(self):
        for width, height in ((1, 1), (1, 17), (17, 1), (9, 9),
                              (1919, 1079), (1920, 1080)):
            for x, y in ((0, 0), (width - 1, 0),
                         (0, height - 1), (width - 1, height - 1)):
                footprint = safe_texels(width, height, x, y)
                self.assertEqual(4, len(footprint))
                for tx, ty in footprint:
                    self.assertGreaterEqual(tx, 0)
                    self.assertGreaterEqual(ty, 0)
                    self.assertLess(tx, width)
                    self.assertLess(ty, height)

    def test_last_pixel_repeats_on_one_by_one_texture(self):
        self.assertEqual(safe_texels(1, 1, 0, 0), [(0, 0)] * 4)


if __name__ == "__main__":
    unittest.main()
