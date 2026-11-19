"""Numeric and source contracts for squared-distance render light ranking."""

import math
import random
import unittest
from pathlib import Path

import run


ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "servers/rendering/renderer_scene_cull.cpp"
SCRIPT = ROOT / "tests/stress/stress.gd"


class RenderLightScoreTests(unittest.TestCase):
    def test_light_selection_uses_squared_scores_without_sqrt(self):
        source = SOURCE.read_text(encoding="utf-8")
        start = source.index("// Only the relative order of light scores is used")
        end = source.index("// Of the N lights", start)
        scoring = source[start:end]
        self.assertIn("mesh_center.distance_squared_to(light_center)", scoring)
        self.assertIn("score_scale * score_scale", scoring)
        self.assertNotIn("distance_to(", scoring)
        self.assertNotIn("sqrt(", scoring)
        self.assertIn("MAX(0.01f, light_range_energy)", scoring)

    def test_squared_score_preserves_ranking_for_random_light_candidates(self):
        rng = random.Random(20261119)
        for trial in range(16):
            candidates = []
            for _ in range(256):
                xyz = tuple(rng.uniform(-250.0, 250.0) for _ in range(3))
                # Exercise positive, zero, and negative effective range*energy.
                range_energy = rng.uniform(-8.0, 400.0)
                scale = max(0.01, range_energy)
                distance_squared = sum(v * v for v in xyz)
                old_score = math.sqrt(distance_squared) / scale
                new_score = distance_squared / (scale * scale)
                candidates.append((old_score, new_score))

            # Heap priority ordering only needs the best N relative scores,
            # not their original physical distance values.
            old_order = sorted(range(len(candidates)), key=lambda i: candidates[i][0])
            new_order = sorted(range(len(candidates)), key=lambda i: candidates[i][1])
            with self.subTest(trial=trial):
                self.assertEqual(new_order, old_order)
                self.assertEqual(new_order[:8], old_order[:8])

    def test_many_lights_workload_requires_display_renderer(self):
        script = SCRIPT.read_text(encoding="utf-8")
        name = "render_light_culling_3d"
        self.assertIn(name, run.CASES)
        self.assertIn(name, run.RENDER_CASES)
        self.assertIn(f"func _{name}(scale: int, frames: int)", script)
        self.assertIn("OmniLight3D.new()", script)
        self.assertIn("light.position.x +=", script)
        self.assertIn("frame_p95_ms", script)
        self.assertIn("peak_draw_calls", script)
        self.assertEqual(run.choose_cases([name], "display"), [name])
        with self.assertRaisesRegex(ValueError, "requires --render-mode display"):
            run.choose_cases([name], "headless")


if __name__ == "__main__":
    unittest.main()
