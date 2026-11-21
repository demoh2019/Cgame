"""Source integration contracts for bounded indexed SmartObject slot claims.

These checks are not a substitute for running the native C++ doctests or the
headless Albion After game under a compiled Cgame editor.
"""
from pathlib import Path
import unittest
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[2]
NATIVE = ROOT / "modules/smart_object_slots"
GAME = ROOT / "game/scripts/shared"
TEST = ROOT / "game/tests/test_flank_slot_reservations.gd"


class TestSmartObjectIndexedClaims(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.header = (NATIVE / "smart_object_slot_reservations.h").read_text()
        cls.native = (NATIVE / "smart_object_slot_reservations.cpp").read_text()
        cls.fallback = (GAME / "flank_slot_reservations.gd").read_text()
        cls.zombie = (GAME / "zombie.gd").read_text()
        cls.tests = TEST.read_text()

    def test_native_maintains_both_bounded_indices(self):
        h, c = self.header, self.native
        for snippet in (
            "HashMap<int64_t, int> slot_indices",
            "HashMap<int64_t, int> actor_indices",
            "MAX_ACTIVE_CLAIMS = 2048",
            "MAX_CANDIDATES = 16",
            "int64_t get_actor_slot(int64_t p_actor_id) const;",
        ):
            self.assertIn(snippet, h)
        for snippet in (
            "slot_indices.getptr(p_slot_id)",
            "actor_indices.getptr(p_actor_id)",
            "slot_indices[slot] = index;",
            "actor_indices[p_actor_id] = index;",
            "slot_indices[slot] = owned;",
            "get_actor_slot",
        ):
            self.assertIn(snippet, c)
        self.assertIn('D_METHOD("get_actor_slot", "actor_id")', c)

    def test_swap_erase_keeps_both_maps_consistent(self):
        c = self.native
        self.assertIn("void SmartObjectSlotReservations::_erase_claim(int p_index)", c)
        self.assertIn("slot_indices.erase(removed.slot_id);", c)
        self.assertIn("actor_indices.erase(removed.actor_id);", c)
        self.assertIn("claims.write[p_index] = moved;", c)
        self.assertIn("slot_indices[moved.slot_id] = p_index;", c)
        self.assertIn("actor_indices[moved.actor_id] = p_index;", c)
        self.assertIn("claims.resize(last);", c)
        self.assertNotIn("claims.remove_at(", c)
        self.assertIn("slot_indices.clear();", c)
        self.assertIn("actor_indices.clear();", c)
        self.assertIn("_erase_claim(index);", c)
        self.assertIn("_erase_claim(i);", c)

    def test_api_and_albion_fallback_have_identical_queries(self):
        doc = ET.parse(NATIVE / "doc_classes/SmartObjectSlotReservations.xml").getroot()
        self.assertIn("get_actor_slot", {m.get("name") for m in doc.findall("./methods/method")})
        self.assertIn("func get_actor_slot(actor_id: int) -> int:", self.fallback)
        self.assertIn("_actor_slots.get(actor_id, 0)", self.fallback)
        self.assertIn('flank_reservations.has_method("get_actor_slot")', self.zombie)
        self.assertIn("flank_reservations.get_actor_slot(id)", self.zombie)
        self.assertIn("_flank_slot_id_cached = claimed_slot", self.zombie)
        self.assertIn("invalid cached flank goal is replanned", self.tests)

    def test_game_has_live_server_wiring_and_native_regression(self):
        server = (ROOT / "game/scripts/server/game_server.gd").read_text()
        native_tests = (NATIVE / "tests/test_smart_object_slot_reservations.h").read_text()
        self.assertIn('ClassDB.instantiate("SmartObjectSlotReservations")', server)
        self.assertIn("_flank_slot_reservations.advance_time(delta)", server)
        self.assertIn('TEST_CASE("[SmartObjects] hashed claim indices survive', native_tests)
        self.assertIn("pool->get_actor_slot(actor)", native_tests)
        self.assertIn("pool->advance_time(1.0)", native_tests)
        self.assertIn("pool->release_actor(actor)", native_tests)


if __name__ == "__main__":
    unittest.main()
