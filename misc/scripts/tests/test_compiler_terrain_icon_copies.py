"""Upstream Godot #110912: avoid read-only container clones in editor / compiler.

Three source contracts cover a fixed HashSet of icon exceptions, GDScript
autoload lookup, and RBSet terrain choice without copies.
"""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[3]


def read(path):
    return (ROOT / path).read_text(encoding="utf-8")


class ReadOnlyContainerRefs(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.icons = read("editor/themes/editor_icons.cpp")
        cls.compiler = read("modules/gdscript/gdscript_compiler.cpp")
        cls.tiles = read("modules/tilemap/tile_set.cpp")

    def test_icon_exceptions_borrow_hashset(self):
        self.assertIn("const HashSet<StringName> &conversion_exceptions = EditorColorMap::get_color_conversion_exceptions();", self.icons)

    def test_icon_set_not_cloned(self):
        self.assertNotIn("HashSet<StringName> conversion_exceptions(EditorColorMap::get_color_conversion_exceptions());", self.icons)

    def test_icon_source_returns_reference(self):
        self.assertIn("HashSet<StringName> &get_color_conversion_exceptions()", read("editor/themes/editor_color_map.h"))

    def test_compiler_autoloads_borrow_map(self):
        self.assertIn("const HashMap<StringName, ProjectSettings::AutoloadInfo> &autoloads = ProjectSettings::get_singleton()->get_autoload_list();", self.compiler)

    def test_compiler_no_hashmap_copy(self):
        self.assertNotIn("HashMap<StringName, ProjectSettings::AutoloadInfo> autoloads(ProjectSettings::get_singleton()->get_autoload_list());", self.compiler)

    def test_autoload_source_returns_reference(self):
        self.assertIn("const HashMap<StringName, AutoloadInfo> &get_autoload_list() const", read("core/config/project_settings.h"))

    def test_terrain_sampling_borrows_tile_set(self):
        self.assertIn("const RBSet<TileMapCell> &set = per_terrain_pattern_tiles[p_terrain_set][p_terrain_tile_pattern];", self.tiles)

    def test_terrain_sampling_does_not_clone_set(self):
        self.assertNotIn("RBSet<TileMapCell> set(per_terrain_pattern_tiles[p_terrain_set][p_terrain_tile_pattern]);", self.tiles)

    def test_tile_export_still_returns_own_value(self):
        self.assertIn("return RBSet<TileMapCell>(per_terrain_pattern_tiles[p_terrain_set][p_terrain_tile_pattern]);", self.tiles)


if __name__ == "__main__":
    unittest.main()
