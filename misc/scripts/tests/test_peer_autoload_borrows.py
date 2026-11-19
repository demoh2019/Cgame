"""API contracts for immutable borrowed containers in SceneMultiplayer and Main.

Corresponds to the peer-list and autoload-table sites of Godot #110912.
The C++ scene multiplayer test verifies stable reference identity.
"""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[3]


class BorrowedPeerAndAutoloadTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.peer = (ROOT / "modules/multiplayer/scene_multiplayer.h").read_text()
        cls.main = (ROOT / "main/main.cpp").read_text()
        cls.test = (ROOT / "modules/multiplayer/tests/test_scene_multiplayer.h").read_text()
        cls.settings = (ROOT / "core/config/project_settings.h").read_text()

    def test_peer_getter_borrows_storage(self):
        self.assertIn("const HashSet<int> &get_connected_peers() const { return connected_peers; }", self.peer)

    def test_peer_getter_no_hashset_clone(self):
        self.assertNotIn("return HashSet<int>(connected_peers)", self.peer)

    def test_peer_getter_cannot_mutate_through_const_reference(self):
        self.assertIn("const HashSet<int> &get_connected_peers() const", self.peer)

    def test_native_peer_pointer_identity_test(self):
        self.assertIn("Connected peers getter borrows storage", self.test)
        self.assertIn("&scene_multiplayer->get_connected_peers() == peers", self.test)

    def test_native_return_type_static_assert(self):
        self.assertIn("std::is_same_v<", self.test)
        self.assertIn("const HashSet<int> &>", self.test)

    def test_main_autoloads_borrow_hashmap(self):
        self.assertIn("const HashMap<StringName, ProjectSettings::AutoloadInfo> &autoloads = ProjectSettings::get_singleton()->get_autoload_list();", self.main)

    def test_main_no_autoload_copy(self):
        self.assertNotIn("HashMap<StringName, ProjectSettings::AutoloadInfo> autoloads(ProjectSettings::get_singleton()->get_autoload_list());", self.main)

    def test_project_settings_returns_stable_reference(self):
        self.assertIn("const HashMap<StringName, AutoloadInfo> &get_autoload_list() const;", self.settings)

    def test_both_initialization_passes_kept(self):
        self.assertIn("//first pass, add the constants", self.main)
        self.assertIn("//second pass, load into global constants", self.main)


if __name__ == "__main__":
    unittest.main()
