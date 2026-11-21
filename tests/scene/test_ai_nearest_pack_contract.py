"""Contracts and independent spatial parity model for limited infected pack alerts.

This verifies source wiring and Python reference behavior. Native C++ compilation,
Godot GDScript execution and measured CPU speedups are separate CI checks.
"""
from pathlib import Path
import math
import random
import unittest

ROOT = Path(__file__).resolve().parents[2]
CPP = ROOT / "modules/behavior_tree/ai_proximity_grid_2d.cpp"
HDR = ROOT / "modules/behavior_tree/ai_proximity_grid_2d.h"
SERVER = ROOT / "game/scripts/server/game_server.gd"
SELECTOR = ROOT / "game/scripts/shared/pack_neighbor_selection.gd"
GAMETEST = ROOT / "game/tests/test_zombie_pack.gd"


def exhaustive(points, source, radius, limit):
    x, y = points[source]
    found = [
        (math.dist((x, y), (px, py)) ** 2, i)
        for i, (px, py) in enumerate(points)
        if i != source and (px - x) ** 2 + (py - y) ** 2 <= radius ** 2
    ]
    return sorted(i for _, i in sorted(found)[:limit])


def bucketed(points, source, radius, limit):
    cellsize = max(1.0, radius)
    buckets = {}
    for index, (x, y) in enumerate(points):
        buckets.setdefault((math.floor(x / cellsize), math.floor(y / cellsize)), []).append(index)
    x, y = points[source]
    cx, cy = math.floor(x / cellsize), math.floor(y / cellsize)
    hits = []
    for dx in range(-1, 2):
        for dy in range(-1, 2):
            for index in buckets.get((cx + dx, cy + dy), []):
                px, py = points[index]
                squared = (px - x) ** 2 + (py - y) ** 2
                if index != source and squared <= radius ** 2:
                    hits.append((squared, index))
    return sorted(i for _, i in sorted(hits)[:limit])


class TestNativeNearestPackContract(unittest.TestCase):
    def test_native_and_game_are_connected(self):
        cpp = CPP.read_text(encoding="utf-8")
        hdr = HDR.read_text(encoding="utf-8")
        game = SERVER.read_text(encoding="utf-8")
        script = SELECTOR.read_text(encoding="utf-8")
        tests = GAMETEST.read_text(encoding="utf-8")
        for token in (
            "query_nearest_batch", "_query_impl", "nearest.write[worst] = candidate",
            "candidate.squared_distance == old.squared_distance",
            "hit_indices.sort()", "p_max_neighbors > 64",
        ):
            self.assertIn(token, cpp)
        self.assertIn("query_nearest_batch", hdr)
        self.assertIn("ZOMBIE_PACK_MAX_ALERTS := 12", game)
        self.assertIn('has_method("query_nearest_batch")', game)
        self.assertIn("_pack_spatial_grid.query_nearest_batch(", game)
        self.assertIn("PackNeighborSelection.choose(", game)
        self.assertIn("nearby.receive_pack_alert(source.target_id, player_info)", game)
        self.assertIn('last_pack_query_stats["alerts_sent"]', game)
        self.assertIn("ranked.sort_custom", script)
        self.assertIn("selected.sort()", script)
        self.assertIn("old binary retains identical dense-pack targeting", tests)
        self.assertIn("only closest allies awaken", tests)

    def test_dense_reverse_order_and_equal_distance(self):
        points = [(0.0, 0.0)] + [(float(i), 0.0) for i in range(18, 0, -1)]
        self.assertEqual(bucketed(points, 0, 18.0, 12), list(range(7, 19)))
        self.assertEqual(bucketed(points, 0, 18.0, 12), exhaustive(points, 0, 18.0, 12))
        tied = [(0, 0), (1, 0), (-1, 0), (1, 0), (2, 0)]
        self.assertEqual(bucketed(tied, 0, 1, 2), [1, 2])
        self.assertEqual(bucketed(tied, 0, 1, 2), exhaustive(tied, 0, 1, 2))

    def test_random_crowds_match_exhaustive_nearest_selection(self):
        rng = random.Random(20261121)
        tested = 0
        for n in (2, 7, 25, 80, 160):
            points = [
                ((rng.random() - 0.5) * 250, (rng.random() - 0.5) * 250)
                for _ in range(n)
            ]
            points[0] = (-18.0, -18.0)
            points[-1] = points[0]
            for radius in (0.0, 2.0, 18.0, 42.0):
                for cap in (1, 3, 12, 64):
                    for source in range(min(n, 10)):
                        self.assertEqual(
                            bucketed(points, source, radius, cap),
                            exhaustive(points, source, radius, cap),
                        )
                        tested += 1
        self.assertGreaterEqual(tested, 500)


if __name__ == "__main__":
    unittest.main()
