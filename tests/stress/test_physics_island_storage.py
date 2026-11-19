"""Source-contract regressions for bounded idle island memory reclamation.

These checks are supplemental: the native C++ test exercises actual
LocalVector destructor behavior and physics-island scratch reuse.
"""

from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
HELPER = ROOT / "servers/physics_island_storage.h"
NATIVE = ROOT / "tests/servers/test_physics_island_storage.cpp"


class IslandStorageSourceContracts(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.helper = HELPER.read_text(encoding="utf-8")
        cls.native = NATIVE.read_text(encoding="utf-8")

    def test_reclaim_is_deferred_and_incremental(self):
        self.assertIn("MIN_RETAINED_ISLANDS = 128", self.helper)
        self.assertIn("MAX_RELEASE_PER_STEP = 1024", self.helper)
        self.assertIn("QUIET_STEPS_BEFORE_RECLAIM = 16", self.helper)
        self.assertIn("p_live_islands >= stored / 4", self.helper)
        self.assertIn("const uint32_t release = MIN(stored - retain, MAX_RELEASE_PER_STEP)", self.helper)
        self.assertIn("r_islands.resize(stored - release);", self.helper)
        self.assertIn("r_islands.shrink_to(r_islands.size());", self.helper)

    def test_both_solvers_cleanup_only_after_all_solver_and_sleep_passes(self):
        for dimension in ("2d", "3d"):
            source = (
                ROOT / f"modules/godot_physics_{dimension}/godot_step_{dimension}.cpp"
            ).read_text(encoding="utf-8")
            header = (
                ROOT / f"modules/godot_physics_{dimension}/godot_step_{dimension}.h"
            ).read_text(encoding="utf-8")
            self.assertIn('#include "servers/physics_island_storage.h"', source)
            self.assertIn("uint8_t body_island_idle_steps = 0;", header)
            self.assertIn("uint8_t constraint_island_idle_steps = 0;", header)
            body_call = (
                "godot_physics_reclaim_idle_island_storage("
                "body_islands, body_island_count, body_island_idle_steps);"
            )
            constraint_call = (
                "godot_physics_reclaim_idle_island_storage("
                "constraint_islands, island_count, constraint_island_idle_steps);"
            )
            self.assertEqual(source.count(body_call), 1)
            self.assertEqual(source.count(constraint_call), 1)
            self.assertLess(source.rindex("all_constraints.clear();"), source.index(body_call))
            self.assertLess(source.index(body_call), source.index(constraint_call))
            self.assertLess(source.index(constraint_call), source.rindex("p_space->unlock();"))
            self.assertLess(source.index("/* SLEEP / WAKE UP ISLANDS */"), source.index(body_call))

    def test_native_destructor_and_burst_regressions_are_present(self):
        self.assertIn("TEST_FORCE_LINK(test_physics_island_storage)", self.native)
        self.assertIn("Tracked::destructed == PEAK - MIN_RETAINED", self.native)
        self.assertIn("islands.get_capacity() <= MIN_RETAINED", self.native)
        self.assertIn("Island scratch reclamation cancels when activity returns", self.native)


if __name__ == "__main__":
    unittest.main()
