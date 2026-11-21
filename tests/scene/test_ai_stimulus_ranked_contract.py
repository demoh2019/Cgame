"""Source and deterministic reference model for ranked confirmed AI stimuli.

Static contracts / pure Python model are not a substitute for compiling Cgame
or running native Godot integration tests.
"""
import math
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
MODULE = ROOT / "modules/behavior_tree"
SHARED = ROOT / "game/scripts/shared"
TESTS = ROOT / "game/tests"


def rank(events, sense, limit):
    if sense not in (0, 1, 2) or not 0 <= limit <= 64:
        return []
    accepted = [
        event for event in events
        if event["sense"] == sense and event["remaining"] > 0
    ]
    return sorted(accepted, key=lambda e: (
        -(e["strength"] * e["remaining"] / e["ttl"]),
        e["source_id"], e["x"], e["z"]
    ))[:limit]


class RankedStimulusContract(unittest.TestCase):
    def test_native_api_and_detached_results(self):
        h = (MODULE / "ai_stimulus_history_2d.h").read_text()
        cpp = (MODULE / "ai_stimulus_history_2d.cpp").read_text()
        xml = (MODULE / "doc_classes/AIStimulusHistory2D.xml").read_text()
        self.assertIn("Array get_ranked(int p_sense, int p_limit = 8) const;", h)
        self.assertIn('D_METHOD("get_ranked", "sense", "limit")', cpp)
        self.assertIn("make_snapshot(events[best[i]])", cpp)
        self.assertIn("candidate_score == previous_score", cpp)
        self.assertIn("candidate.source_id < previous.source_id", cpp)
        self.assertIn("p_limit < 0 || p_limit > 64", cpp)
        self.assertIn('<method name="get_ranked"', xml)
        self.assertNotIn("SceneTree::", cpp)

    def test_game_integration_is_server_only_and_legacy_safe(self):
        adapter = (SHARED / "native_infected_senses.gd").read_text()
        zombie = (SHARED / "zombie.gd").read_text()
        runner = (TESTS / "run_ranked_infected_perception.gd").read_text()
        self.assertIn('func get_ranked_confirmed_stimuli(sense: int, limit: int = 8)', adapter)
        self.assertIn('_history.has_method("get_ranked")', adapter)
        self.assertIn('for event in _native_senses.get_ranked_confirmed_stimuli(1, 8)', zombie)
        self.assertIn("_investigated_sound_sites.is_empty()", zombie)
        self.assertIn('here.distance_to(candidate) > float(data["lose"])', zombie)
        self.assertIn("world.is_safe(candidate.x, candidate.y)", zombie)
        self.assertIn("world.is_water(candidate.x, candidate.y)", zombie)
        self.assertIn('_investigated_sound_sites.clear()', zombie)
        self.assertIn('t.current = "Ranked history can guide one bounded follow-up investigation"', (TESTS / "test_native_infected_senses.gd").read_text())
        self.assertIn("RANKED PERCEPTION TOTAL:", runner)
        self.assertNotIn("get_ranked_confirmed_stimuli", (SHARED / "net.gd").read_text())

    def test_score_order_and_stable_ties(self):
        events = [
            dict(sense=1, strength=.95, remaining=1., ttl=2., source_id=9, x=9., z=0.),
            dict(sense=1, strength=.6, remaining=3., ttl=3., source_id=3, x=7., z=0.),
            dict(sense=1, strength=.6, remaining=3., ttl=3., source_id=2, x=1., z=0.),
            dict(sense=0, strength=1., remaining=6., ttl=6., source_id=20, x=3., z=0.),
        ]
        for permutation in [events, list(reversed(events))]:
            self.assertEqual([x["source_id"] for x in rank(permutation, 1, 3)], [2, 3, 9])
            self.assertEqual([x["source_id"] for x in rank(permutation, 1, 1)], [2])
            self.assertEqual(rank(permutation, 1, 0), [])
            self.assertEqual(rank(permutation, 3, 8), [])
            self.assertEqual(rank(permutation, 1, 65), [])
        events[0]["remaining"] = 0
        self.assertEqual([x["source_id"] for x in rank(events, 1, 8)], [2, 3])


if __name__ == "__main__":
    unittest.main()
