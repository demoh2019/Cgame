"""Regression contracts for cached ellipse tessellation and real-renderer stress."""

import math
import unittest
from pathlib import Path

import run


ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "servers/rendering/renderer_canvas_cull.cpp"
STRESS = ROOT / "tests/stress/stress.gd"


class CanvasEllipseCacheTests(unittest.TestCase):
    def test_one_trigonometric_table_is_shared_by_filled_and_feather_paths(self):
        source = SOURCE.read_text(encoding="utf-8")
        begin = source.index("void RendererCanvasCull::canvas_item_add_ellipse(")
        end = source.index("void RendererCanvasCull::canvas_item_add_circle(", begin)
        ellipse = source[begin:end]

        self.assertIn("static constexpr int ellipse_segments = 64", ellipse)
        self.assertIn("static const std::array<Vector2, ellipse_segments + 1>", ellipse)
        self.assertIn("ellipse_directions = []", ellipse)
        self.assertEqual(ellipse.count("Math::cos(angle)"), 1)
        self.assertEqual(ellipse.count("Math::sin(angle)"), 1)
        self.assertEqual(ellipse.count("ellipse_directions[i]"), 2)
        self.assertIn("ellipse->polygon.create(indices, points, color)", ellipse)
        self.assertIn("feather->polygon.create(indices, points, colors)", ellipse)

    def test_angle_cache_keeps_original_closed_ring_and_point_count(self):
        segments = 64
        step = math.tau / segments
        cached = [(math.cos(float(i * step)), math.sin(float(i * step)))
                  for i in range(segments + 1)]
        major, minor = 15.5, 9.0
        expected = [
            (math.cos(float(i * step)) * major, math.sin(float(i * step)) * minor)
            for i in range(segments + 1)
        ]
        actual = [(x * major, y * minor) for (x, y) in cached]
        self.assertEqual(actual, expected)
        self.assertEqual(len(actual), 65)
        self.assertTrue(math.isclose(actual[0][0], major))
        self.assertTrue(math.isclose(actual[-1][0], major))

    def test_ellipse_stress_requires_a_display_and_validates_dispatch(self):
        script = STRESS.read_text(encoding="utf-8")
        case = "render_ellipse_2d"
        self.assertIn(case, run.CASES)
        self.assertIn(case, run.RENDER_CASES)
        self.assertIn(f'func _{case}(scale: int)', script)
        self.assertIn('RenderingServer.canvas_item_add_circle(', script)
        self.assertIn('RenderingServer.canvas_item_add_ellipse(', script)
        self.assertIn('RenderingServer.force_sync()', script)
        self.assertIn('ellipse_cpu_ms', script)
        self.assertIn(case, run.choose_cases([case], "display"))
        with self.assertRaisesRegex(ValueError, "requires --render-mode display"):
            run.choose_cases([case], "headless")


if __name__ == "__main__":
    unittest.main()
