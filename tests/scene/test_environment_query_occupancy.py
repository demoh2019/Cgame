"""Occupancy-aware EQS selection: source guards and mathematical oracle.

These checks complement (do not replace) the native C++ and Godot runtime suites.
"""
import math
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
CPP = ROOT / "modules/environment_query/environment_query_3d.cpp"
HEADER = ROOT / "modules/environment_query/environment_query_3d.h"
GAME = ROOT / "game/scripts/shared/raid_reinforcements.gd"
GAME_TEST = ROOT / "game/tests/test_raid_reinforcements.gd"


def spread(points, blockers, separation, clearance, count, horizontal=True):
    if not math.isfinite(clearance) or clearance < 0 or len(blockers) > 128:
        return []
    if not math.isfinite(separation) or separation < 0 or count < 1 or count > 64:
        return []
    if any(not all(math.isfinite(v) for v in p) for p in blockers):
        return []

    def distance(a, b):
        indices = (0, 2) if horizontal else (0, 1, 2)
        return math.sqrt(sum((a[i] - b[i]) ** 2 for i in indices))

    # The default EQS score prefers points closer to (0,0,0).
    ranked = sorted(enumerate(points),
                    key=lambda pair: (distance((0, 0, 0), pair[1]), pair[0]))
    selected = []
    for _index, point in ranked:
        if not all(math.isfinite(v) for v in point):
            continue
        if any(distance(point, blocker) < clearance for blocker in blockers):
            continue
        if any(distance(point, other) < separation for other in selected):
            continue
        selected.append(point)
        if len(selected) == count:
            break
    return selected


class OccupiedQueryContract(unittest.TestCase):
    def test_cpp_and_game_use_same_bounded_protocol(self):
        cpp = CPP.read_text(encoding="utf-8")
        hdr = HEADER.read_text(encoding="utf-8")
        game = GAME.read_text(encoding="utf-8")
        game_tests = GAME_TEST.read_text(encoding="utf-8")
        self.assertIn("query_spread_positions_avoiding(int p_count", hdr)
        self.assertIn('D_METHOD("query_spread_positions_avoiding"', cpp)
        self.assertIn("p_occupied_positions.size() > 128", cpp)
        self.assertIn("!p_occupied_positions[i].is_finite()", cpp)
        self.assertIn("point_distance(point, p_occupied_positions[j], horizontal_only) < p_clearance", cpp)
        self.assertIn("min_threat_distance, hit", cpp)
        self.assertIn('query.has_method("query_spread_positions_avoiding")', game)
        self.assertIn("MAX_OCCUPANCY_CONTEXTS := 128", game)
        self.assertIn("point.distance_to(occupied_point) < clearance", game)
        self.assertIn("MIN_BETWEEN_ADDS, true, occupied, MIN_INFECTED_DISTANCE", game)
        self.assertIn("blocked_native, blocked_script", game_tests)

    def test_occupied_boundary_and_no_occupancy_parity(self):
        candidates = [(2, 0, 0), (4, 0, 0), (8, 0, 0), (12, 0, 0)]
        self.assertEqual(spread(candidates, [(2, 0, 0)], 3.5, 2, 3),
                         [(4, 0, 0), (8, 0, 0), (12, 0, 0)])
        self.assertEqual(spread(candidates, [], 3.5, 0, 3),
                         spread(candidates, [(2, 0, 0)], 3.5, 0, 3))

    def test_horizontal_vs_vertical_and_invalid_inputs(self):
        points = [(2, 12, 0), (8, 0, 0)]
        self.assertEqual(spread(points, [(2, 0, 0)], 0, 3, 2, horizontal=True),
                         [(8, 0, 0)])
        self.assertEqual(len(spread(points, [(2, 0, 0)], 0, 3, 2, horizontal=False)), 2)
        self.assertEqual(spread(points, [(2, 0, 0)], 0, float("nan"), 2), [])
        self.assertEqual(spread(points, [(2, 0, 0)] * 129, 0, 3, 2), [])
        self.assertEqual(spread(points, [(float("inf"), 0, 0)], 0, 3, 2), [])

    def test_ties_keep_original_candidate_order(self):
        points = [(0, 0, 1), (1, 0, 0), (-1, 0, 0), (0, 0, -1)]
        self.assertEqual(spread(points, [], 0, 0, 4), points)
        self.assertEqual(spread(points, [(0, 0, 1)], 0, 0.1, 4), points[1:])


if __name__ == "__main__":
    unittest.main()
