"""Source contracts for Cgame's TileMap missing-tile overlay optimization.

These tests verify the optimized source structure. Native TileMapLayer tests and
interactive editor acceptance are separate and remain necessary.
"""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[3]

def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")

def body(text: str, start: str, next_start: str) -> str:
    if text.count(start) != 1 or next_start not in text.split(start, 1)[1]:
        raise AssertionError(f"Expected unique function delimiters: {start}")
    return text.split(start, 1)[1].split(next_start, 1)[0]

class TileOverlayCacheContracts(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.editor = read("modules/tilemap/editor/tile_map_layer_editor.cpp")
        cls.editor_h = read("modules/tilemap/editor/tile_map_layer_editor.h")
        cls.layer = read("modules/tilemap/tile_map_layer.cpp")
        cls.layer_h = read("modules/tilemap/tile_map_layer.h")
        cls.rebuild = body(cls.editor,
                           "void TileMapLayerEditor::_update_invalid_cells_cache(",
                           "void TileMapLayerEditor::_draw_overlay(")
        cls.draw = body(cls.editor,
                        "void TileMapLayerEditor::_draw_overlay(",
                        "void TileMapLayerEditor::edit(")
        cls.edit = body(cls.editor,
                        "void TileMapLayerEditor::edit(Object *p_edited)",
                        "void TileMapLayerEditor::set_show_layer_selector(")
        cls.change = body(cls.editor,
                          "void TileMapLayerEditor::_tile_map_layer_changed()",
                          "void TileMapLayerEditor::_tab_changed(")
        cls.set_cell = body(cls.layer,
                            "void TileMapLayer::set_cell(",
                            "void TileMapLayer::erase_cell(")

    def test_editor_header_tracks_cell_cache(self):
        self.assertIn("struct InvalidCell", self.editor_h)
        self.assertIn("LocalVector<InvalidCell> invalid_cells;", self.editor_h)

    def test_editor_header_tracks_revision(self):
        self.assertIn("uint64_t invalid_cells_revision = 0;", self.editor_h)

    def test_editor_header_starts_dirty(self):
        self.assertIn("bool invalid_cells_cache_dirty = true;", self.editor_h)

    def test_editor_header_declares_rebuild(self):
        self.assertIn("void _update_invalid_cells_cache(const TileMapLayer *p_layer);", self.editor_h)

    def test_layer_header_revision_is_tools_only(self):
        self.assertRegex(self.layer_h, re.compile(
            r"#ifdef TOOLS_ENABLED\s+uint64_t cell_data_revision = 0;\s+#endif"))

    def test_layer_header_exposes_revision_tools_only(self):
        self.assertRegex(self.layer_h, re.compile(
            r"#ifdef TOOLS_ENABLED\s+virtual bool _edit_is_selected_on_click\([^\n]+\n"
            r"\s+uint64_t get_cell_data_revision\(\) const \{ return cell_data_revision; \}"))

    def test_set_cell_revision_is_tools_only(self):
        self.assertRegex(self.set_cell, re.compile(
            r"#ifdef TOOLS_ENABLED\s+cell_data_revision\+\+;\s+#endif"))

    def test_revision_changed_after_real_cell_update(self):
        self.assertLess(self.set_cell.index("c.alternative_tile = alternative_tile;"),
                        self.set_cell.index("cell_data_revision++;"))

    def test_revision_not_bumped_for_noop_changes(self):
        self.assertLess(self.set_cell.index("return; // Nothing changed."),
                        self.set_cell.index("cell_data_revision++;"))

    def test_cache_uses_direct_stored_hash_map(self):
        self.assertIn("const HashMap<Vector2i, CellData> &used_cells = p_layer->get_tile_map_layer_data();",
                      self.rebuild)

    def test_cache_does_not_allocate_typed_cell_array(self):
        self.assertNotIn("get_used_cells()", self.rebuild)
        self.assertNotIn("TypedArray<Vector2i>", self.rebuild)

    def test_cache_iterates_by_const_reference(self):
        self.assertIn("for (const KeyValue<Vector2i, CellData> &entry : used_cells)", self.rebuild)

    def test_cache_reuses_cell_fields(self):
        self.assertIn("const TileMapCell &cell = entry.value.cell;", self.rebuild)
        self.assertIn("const int tile_source_id = cell.source_id;", self.rebuild)
        self.assertIn("cell.get_atlas_coords()", self.rebuild)
        self.assertIn("cell.alternative_tile", self.rebuild)

    def test_cache_skips_erased_cells(self):
        self.assertRegex(self.rebuild, re.compile(
            r"if \(tile_source_id < 0\) \{\s+continue;\s+\}"))

    def test_cache_avoids_per_cell_hash_lookups(self):
        for member in ("get_cell_source_id(", "get_cell_atlas_coords(",
                       "get_cell_alternative_tile("):
            with self.subTest(member=member):
                self.assertNotIn(member, self.rebuild)

    def test_cache_checks_source_exists(self):
        self.assertIn("tile_set->has_source(tile_source_id)", self.rebuild)

    def test_cache_checks_tile_exists(self):
        self.assertIn("source->has_tile(tile_atlas_coords)", self.rebuild)

    def test_cache_checks_alternative_exists(self):
        self.assertIn("source->has_alternative_tile(tile_atlas_coords, tile_alternative_tile)", self.rebuild)

    def test_cache_keeps_original_color_hash(self):
        self.assertIn("Array to_hash = { tile_source_id, tile_atlas_coords, tile_alternative_tile };", self.rebuild)
        self.assertIn("uint32_t hash = RandomPCG(to_hash.hash()).rand();", self.rebuild)

    def test_cache_stores_original_map_coordinates(self):
        self.assertIn("invalid_cells.push_back({ entry.key, color });", self.rebuild)

    def test_cache_clears_before_rebuild(self):
        self.assertIn("invalid_cells.clear();", self.rebuild)
        self.assertLess(self.rebuild.index("invalid_cells.clear();"),
                        self.rebuild.index("for (const KeyValue"))

    def test_rebuild_records_revision(self):
        self.assertIn("invalid_cells_revision = p_layer->get_cell_data_revision();", self.rebuild)

    def test_rebuild_marks_clean_after_scanning(self):
        self.assertIn("invalid_cells_cache_dirty = false;", self.rebuild)
        self.assertLess(self.rebuild.index("invalid_cells_revision ="),
                        self.rebuild.index("invalid_cells_cache_dirty = false;"))

    def test_layer_change_marks_cache_dirty(self):
        self.assertIn("invalid_cells_cache_dirty = true;", self.change)

    def test_layer_switch_clears_previous_cache(self):
        self.assertIn("invalid_cells.clear();", self.edit)

    def test_layer_switch_marks_cache_dirty_even_same_revision(self):
        self.assertIn("invalid_cells_cache_dirty = true;", self.edit)

    def test_layer_switch_cache_invalidation_before_new_selection(self):
        self.assertLess(self.edit.index("invalid_cells_cache_dirty = true;"),
                        self.edit.index("TileMapLayer *new_layer ="))

    def test_draw_rebuilds_only_when_dirty_or_revision_changes(self):
        self.assertRegex(self.draw, re.compile(
            r"if \(invalid_cells_cache_dirty \|\| invalid_cells_revision != edited_layer->get_cell_data_revision\(\)\) \{"
        ))

    def test_draw_only_rebuilds_inside_conditional(self):
        self.assertRegex(self.draw, re.compile(
            r"if \(invalid_cells_cache_dirty \|\| invalid_cells_revision != edited_layer->get_cell_data_revision\(\)\) \{\s*"
            r"_update_invalid_cells_cache\(edited_layer\);\s*\}"
        ))

    def test_draw_uses_cached_invalid_cells(self):
        self.assertIn("for (const InvalidCell &cell : invalid_cells)", self.draw)

    def test_draw_culls_outside_viewport(self):
        self.assertIn("if (!visible_rect.has_point(tile_center))", self.draw)

    def test_draw_uses_inverse_canvas_transform(self):
        self.assertIn("xform_inv.xform(Rect2(Vector2(), custom_overlay->get_size()))", self.draw)

    def test_draw_extends_rect_for_partially_visible_tiles(self):
        self.assertIn("visible_rect.position -= Vector2(tile_shape_size) / 2;", self.draw)
        self.assertIn("visible_rect.size += Vector2(tile_shape_size);", self.draw)

    def test_draw_preserves_alpha_fade(self):
        self.assertIn("color.a *= scale_fading;", self.draw)

    def test_draw_preserves_missing_tile_pattern(self):
        self.assertIn("tile_set->draw_tile_shape", self.draw)
        self.assertIn("warning_pattern_texture", self.draw)

    def test_draw_preserves_missing_tile_icon(self):
        self.assertIn("custom_overlay->draw_texture_rect(missing_tile_texture", self.draw)

    def test_unchanged_layers_do_not_rescan_cells_during_draw(self):
        self.assertNotIn("get_used_cells()", self.draw)
        self.assertNotIn("get_cell_source_id(", self.draw)

    def test_overlay_returns_for_invisible_layer(self):
        self.assertIn("!edited_layer->is_visible_in_tree()", self.draw)

    def test_overlay_returns_if_tile_set_missing(self):
        self.assertIn("if (tile_set.is_null())", self.draw)


if __name__ == "__main__":
    unittest.main()
