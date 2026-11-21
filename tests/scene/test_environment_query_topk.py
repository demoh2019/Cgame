"""Source and numerical parity checks for bounded native EQS top-K."""
import math
from pathlib import Path
import random
import unittest

ROOT = Path(__file__).resolve().parents[2]
CPP = ROOT / "modules/environment_query/environment_query_3d.cpp"
HDR = ROOT / "modules/environment_query/environment_query_3d.h"
ZOMBIE = ROOT / "game/scripts/shared/zombie.gd"


def full_rank(points, k):
    ranked = []
    for i, (x, z) in enumerate(points):
        if not math.isfinite(x) or not math.isfinite(z):
            continue
        score = 1 - min(1, math.hypot(x, z) / 100)
        ranked.append((score, i, (x, z)))
    return [p for _, _, p in sorted(ranked, key=lambda hit: (-hit[0], hit[1]))[:k]]


def bounded_rank(points, k):
    best = []
    for i, (x, z) in enumerate(points):
        if not math.isfinite(x) or not math.isfinite(z):
            continue
        hit = (1 - min(1, math.hypot(x, z) / 100), i, (x, z))
        if len(best) == k and (-hit[0], hit[1]) >= (-best[-1][0], best[-1][1]):
            continue
        pos = 0
        while pos < len(best) and (-hit[0], hit[1]) >= (-best[pos][0], best[pos][1]):
            pos += 1
        best.insert(pos, hit)
        del best[k:]
    return [v[2] for v in best]


class NativeEqsTopK(unittest.TestCase):
    def test_native_avoids_full_sort_and_dictionary_allocations(self):
        cpp = CPP.read_text(encoding="utf-8")
        section = cpp.split("PackedVector3Array EnvironmentQuery3D::query_top_positions")[1].split(
            "PackedVector3Array EnvironmentQuery3D::query_spread_positions")[0]
        self.assertIn("Vector<QueryHit> best;", section)
        self.assertIn("best.insert(at, hit);", section)
        self.assertIn("best.resize(limit);", section)
        self.assertNotIn("query();", section)
        self.assertNotIn("SortArray", section)
        self.assertIn("score_candidate(", section)
        self.assertIn("query_top_positions(int p_count) const", HDR.read_text(encoding="utf-8"))

    def test_exact_order_for_tied_candidates(self):
        items = [(1, 0), (0, 1), (-1, 0), (0, -1)]
        self.assertEqual(bounded_rank(items, 3), items[:3])

    def test_random_hordes_and_invalid_points(self):
        rng = random.Random(4121)
        for n in (0, 1, 3, 8, 64, 512):
            points = [(rng.uniform(-50, 50), rng.uniform(-50, 50))
                      for _ in range(n)]
            points += [(float("nan"), 2), (3, float("inf"))]
            for k in (1, 3, 8, 16):
                self.assertEqual(bounded_rank(points, k), full_rank(points, k))

    def test_cached_game_ai_and_stock_fallback(self):
        source = ZOMBIE.read_text(encoding="utf-8")
        for contract in (
            "var _flank_query: Resource",
            "if _flank_query == null:",
            '_flank_query.call("query_top_positions", 3)',
            "const FLANK_REPLAN_SECONDS := 0.30",
            "_flank_replan_remaining = maxf(0.0",
            "here.distance_squared_to(_flank_here_cached) <= 3.24",
            "target.distance_squared_to(_flank_target_cached) <= 1.0",
            'not ClassDB.class_exists("EnvironmentQuery3D")',
        ):
            self.assertIn(contract, source)


if __name__ == "__main__":
    unittest.main()
