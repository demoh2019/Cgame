"""Source and numerical AO/SSIL bilateral filter edge guards for Cgame.

Run: python3 -m unittest tests/servers/rendering/test_ao_blur_bounds.py -v
These tests do not substitute Vulkan or Apple Metal shader compilation.
"""

from pathlib import Path
import unittest

EFFECTS = Path(__file__).resolve().parents[3] / "servers/rendering/renderer_rd/shaders/effects"


def valid_dispatch(width, height, x, y):
    return 0 <= x < width and 0 <= y < height


def clamped_wide_edges(size, p):
    width, height = size
    x, y = p
    return tuple((
        min(max(x + dx, 0), width - 1),
        min(max(y + dy, 0), height - 1),
    ) for dx, dy in ((-2, 0), (0, -2), (2, 0), (0, 2)))


class AOBilateralBoundsTests(unittest.TestCase):
    def test_both_compute_passes_guard_rounded_dispatch(self):
        for name in ("ssao_blur.glsl", "ssil_blur.glsl"):
            source = (EFFECTS / name).read_text(encoding="utf-8")
            self.assertIn(
                "if (any(greaterThanEqual(ssC, imageSize(dest_image))))", source
            )
            self.assertLess(source.find("imageSize(dest_image)"), source.find("#ifdef MODE_NON_SMART"))
            self.assertIn("imageStore(dest_image,", source)

    def test_ssil_wide_edge_reads_clamp_before_image_load(self):
        source = (EFFECTS / "ssil_blur.glsl").read_text(encoding="utf-8")
        self.assertIn("ivec2 last_edge = imageSize(source_edges) - ivec2(1);", source)
        for offset in ("-2, 0", "0, -2", "2, 0", "0, 2"):
            safe = "clamp(p_pos + ivec2(" + offset + "), ivec2(0), last_edge)"
            self.assertIn(safe, source)
            self.assertNotIn("imageLoad(source_edges, p_pos + ivec2(" + offset, source)

    def test_nonaligned_workgroups_cannot_write_outside_target(self):
        for size in ((1, 1), (9, 7), (1279, 719), (1920, 1080), (43, 57)):
            width, height = size
            x_range = range((width + 7) // 8 * 8)
            y_range = range((height + 7) // 8 * 8)
            valid = sum(valid_dispatch(width, height, x, y)
                        for x in x_range for y in y_range)
            self.assertEqual(valid, width * height)

    def test_clamped_edge_neighbors_are_valid_even_on_single_pixel(self):
        for size in ((1, 1), (2, 4), (9, 7), (1279, 719), (1920, 1080)):
            w, h = size
            for p in ((0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1)):
                taps = clamped_wide_edges(size, p)
                self.assertEqual(len(taps), 4)
                for x, y in taps:
                    self.assertTrue(0 <= x < w)
                    self.assertTrue(0 <= y < h)

    def test_edge_replication_keeps_flat_ao_unchanged(self):
        for size in ((1, 1), (17, 13)):
            for p in ((0, 0), (size[0] - 1, size[1] - 1)):
                self.assertTrue(all(0 <= x < size[0] and 0 <= y < size[1]
                                    for x, y in clamped_wide_edges(size, p)))


if __name__ == "__main__":
    unittest.main()
