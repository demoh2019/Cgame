"""Ensure networking hot paths borrow, not clone, stable replication containers.

Backports Godot upstream #110912. A snapshot would be appropriate when
mutating collections; these call sites are the upstream read-only operations.
"""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[3]


class MultiplayerContainerBorrowTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.replication = (ROOT / "modules/multiplayer/scene_replication_interface.cpp").read_text()
        cls.sync = (ROOT / "modules/multiplayer/multiplayer_synchronizer.cpp").read_text()
        cls.config_h = (ROOT / "modules/multiplayer/scene_replication_config.h").read_text()

    def test_network_process_borrows_peer_sync_set(self):
        self.assertIn("const HashSet<ObjectID> &to_sync = E.value.sync_nodes;", self.replication)

    def test_network_process_has_no_sync_set_clone(self):
        self.assertNotIn("const HashSet<ObjectID> to_sync(E.value.sync_nodes);", self.replication)

    def test_visibility_borrows_tracked_synchronizers(self):
        self.assertIn("const HashSet<ObjectID> &synchronizers = tracked_nodes[p_oid].synchronizers;", self.replication)

    def test_spawn_packet_borrows_tracked_synchronizers(self):
        self.assertIn("const HashSet<ObjectID> &synchronizers = tnode->synchronizers;", self.replication)

    def test_send_sync_borrows_property_list(self):
        self.assertEqual(self.replication.count("const List<NodePath> &props = sync->get_replication_config_ptr()->get_sync_properties();"), 2)

    def test_spawn_replication_borrows_property_list(self):
        self.assertIn("const List<NodePath> &props = sync->get_replication_config_ptr()->get_spawn_properties();", self.replication)

    def test_watch_properties_borrowed(self):
        self.assertIn("const List<NodePath> &props = replication_config->get_watch_properties();", self.sync)
        self.assertIn("const List<NodePath> &watch_props = replication_config->get_watch_properties();", self.sync)

    def test_config_property_accessors_return_references(self):
        for name in ("spawn", "sync", "watch"):
            self.assertIn("const List<NodePath> &get_" + name + "_properties();", self.config_h)

    def test_replication_liveness_guards_kept(self):
        self.assertIn("ERR_CONTINUE(!sync || !sync->get_replication_config_ptr()", self.replication)
        self.assertIn("ERR_FAIL_NULL_V(tnode, ERR_INVALID_PARAMETER);", self.replication)

    def test_network_sync_still_sends_sync_and_delta(self):
        self.assertIn("_send_sync(E.key, to_sync, sync_net_time, usec);", self.replication)
        self.assertIn("_send_delta(E.key, to_sync, usec, E.value.last_watch_usecs);", self.replication)


if __name__ == "__main__":
    unittest.main()
