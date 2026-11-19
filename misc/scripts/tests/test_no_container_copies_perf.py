"""Regressions for copy-free read-only container hot paths from Godot #110912.

Every covered producer returns a reference (or holds the resolver lock). These
source contracts prevent reintroducing O(N) container copies in frequent calls.
"""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[3]


def read(path):
    return (ROOT / path).read_text(encoding="utf-8")


class NoContainerCopiesTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.ip = read("core/io/ip.cpp")
        cls.audio = read("scene/2d/audio_stream_player_2d.cpp")
        cls.nav2 = read("modules/navigation_2d/2d/godot_navigation_server_2d.cpp")
        cls.nav3 = read("modules/navigation_3d/3d/godot_navigation_server_3d.cpp")
        cls.tile = read("modules/tilemap/tile_map.cpp")
        cls.graph = read("scene/gui/graph_edit.cpp")
        cls.node = read("scene/main/node.cpp")
        cls.tree = read("scene/main/scene_tree.cpp")

    def test_audio_panning_borrows_viewports(self):
        self.assertIn("const HashSet<Viewport *> &viewports = world_2d->get_viewports();", self.audio)
        self.assertNotIn("HashSet<Viewport *> viewports(world_2d->get_viewports());", self.audio)

    def test_audio_world_viewport_accessor_returns_ref(self):
        self.assertIn("const HashSet<Viewport *> &get_viewports()", read("scene/resources/world_2d.h"))

    def test_navigation_2d_borrows_obstacles(self):
        self.assertIn("const LocalVector<NavObstacle2D *> &obstacles = map->get_obstacles();", self.nav2)

    def test_navigation_3d_borrows_obstacles(self):
        self.assertIn("const LocalVector<NavObstacle3D *> &obstacles = map->get_obstacles();", self.nav3)

    def test_nav_2d_obstacle_source_is_reference(self):
        self.assertIn("const LocalVector<NavObstacle2D *> &get_obstacles() const", read("modules/navigation_2d/nav_map_2d.h"))

    def test_nav_3d_obstacle_source_is_reference(self):
        self.assertIn("const LocalVector<NavObstacle3D *> &get_obstacles() const", read("modules/navigation_3d/nav_map_3d.h"))

    def test_tilemap_export_borrows_cell_map(self):
        self.assertIn("const HashMap<Vector2i, CellData> &tile_map_layer_data = layers[p_layer]->get_tile_map_layer_data();", self.tile)

    def test_tilemap_source_is_reference(self):
        self.assertIn("const HashMap<Vector2i, CellData> &get_tile_map_layer_data() const", read("modules/tilemap/tile_map_layer.h"))

    def test_graphedit_connection_query_borrows_list(self):
        self.assertIn("const List<Ref<GraphEdit::Connection>> &connections_from_node = connection_map.get(p_node);", self.graph)

    def test_graphedit_query_does_not_copy_connections(self):
        self.assertNotIn("List<Ref<GraphEdit::Connection>> connections_from_node(connection_map.get(p_node))", self.graph)

    def test_ip_single_address_avoids_list_copy(self):
        self.assertIn("const List<IPAddress> &res = resolver->queue[p_id].response;", self.ip)
        self.assertEqual(self.ip.count("const List<IPAddress> &res = resolver->queue[p_id].response;"), 2)

    def test_ip_read_holds_resolver_mutex(self):
        for signature in ("IPAddress IP::get_resolve_item_address(", "Array IP::get_resolve_item_addresses("):
            start = self.ip.index(signature)
            body = self.ip[start:start + 850]
            self.assertIn("MutexLock lock(resolver->mutex);", body)
            self.assertLess(body.index("MutexLock lock(resolver->mutex);"),
                            body.index("const List<IPAddress> &res"))

    def test_node_argument_completion_borrows_global_groups(self):
        self.assertIn("const HashMap<StringName, String> &global_groups = ProjectSettings::get_singleton()->get_global_groups_list();", self.node)

    def test_scene_tree_argument_completion_borrows_global_groups(self):
        self.assertIn("const HashMap<StringName, String> &global_groups = ProjectSettings::get_singleton()->get_global_groups_list();", self.tree)

    def test_project_settings_group_source_is_reference(self):
        self.assertIn("const HashMap<StringName, String> &get_global_groups_list() const", read("core/config/project_settings.h"))

    def test_mutating_node_owner_iteration_keeps_snapshot(self):
        self.assertIn("List<Node *> owned(data.owned);", self.node)


if __name__ == "__main__":
    unittest.main()
