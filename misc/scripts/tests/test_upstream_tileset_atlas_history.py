"""Regression guards for the Godot #125466 TileSet atlas/UndoRedo port.

These source-level checks do not replace native editor interaction tests. They
catch accidental removal of the crucial resource history ownership wiring.
Run: python -m unittest misc.scripts.tests.test_upstream_tileset_atlas_history
"""

from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[3]


def _source(relative_path):
    return (ROOT / relative_path).read_text(encoding="utf-8")


def _body(source, function_name):
    """Extract a C++ function's outer braced body for targeted assertions."""
    marker = source.index(function_name)
    start = source.index("{", marker)
    depth = 0
    for pos in range(start, len(source)):
        if source[pos] == "{":
            depth += 1
        elif source[pos] == "}":
            depth -= 1
            if depth == 0:
                return source[start + 1 : pos]
    raise AssertionError(f"Unclosed C++ body for {function_name}")


class TileSetAtlasHistoryPortTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.source = _body(
            _source("modules/tilemap/editor/tile_set_editor.cpp"),
            "void TileSetEditor::_load_texture_files(",
        )
        cls.atlas_source = _body(
            _source("modules/tilemap/editor/tile_set_atlas_source_editor.cpp"),
            "void TileSetAtlasSourceEditor::_end_dragging(",
        )

    def test_owner_path_is_taken_from_actual_tile_set(self):
        self.assertIn('const String owner_path = tile_set->get_path().get_slice("::", 0);', self.source)

    def test_owner_path_computed_before_iterating_textures(self):
        self.assertLess(self.source.index("const String owner_path"), self.source.index("for (const String &p_path"))

    def test_embedded_subresource_path_is_reduced_to_owning_resource(self):
        # Extract the intended expression rather than trusting a duplicated
        # string constant set elsewhere in the source.
        self.assertRegex(self.source, r'tile_set->get_path\(\)\.get_slice\("::", 0\)')

    def test_creation_of_atlas_precedes_owner_setup(self):
        self.assertLess(
            self.source.index("Ref<TileSetAtlasSource> atlas_source = memnew(TileSetAtlasSource);"),
            self.source.index("EditorNode::setup_built_in_resource(atlas_source, owner_path);"),
        )

    def test_setup_is_guarded_for_unsaved_tile_sets(self):
        self.assertRegex(
            self.source,
            r'if \(!owner_path\.is_empty\(\)\) \{\s*'
            r'EditorNode::setup_built_in_resource\(atlas_source, owner_path\);\s*\}',
        )

    def test_setup_runs_before_atlas_is_populated(self):
        self.assertLess(
            self.source.index("EditorNode::setup_built_in_resource(atlas_source, owner_path);"),
            self.source.index("atlas_source->set_texture(texture);"),
        )

    def test_setup_runs_before_atlas_is_committed_to_undo(self):
        self.assertLess(
            self.source.index("EditorNode::setup_built_in_resource(atlas_source, owner_path);"),
            self.source.index('undo_redo->create_action(TTR("Add a new atlas source"));'),
        )

    def test_undo_remains_the_inverse_of_atlas_creation(self):
        self.assertIn('undo_redo->add_do_method(*tile_set, "add_source", atlas_source, source_id);', self.source)
        self.assertIn('undo_redo->add_undo_method(*tile_set, "remove_source", source_id);', self.source)

    def test_rectangle_deletion_uses_atlas_history_context(self):
        rectangle = self.atlas_source.split("case DRAG_TYPE_REMOVE_TILES_USING_RECT: {", 1)[1]
        self.assertIn(
            'undo_redo->create_action(TTR("Remove tiles"), UndoRedo::MERGE_DISABLE, tile_set_atlas_source);',
            rectangle,
        )

    def test_rectangle_deletion_keeps_selection_undo_protocol(self):
        rectangle = self.atlas_source.split("case DRAG_TYPE_REMOVE_TILES_USING_RECT: {", 1)[1]
        self.assertIn('undo_redo->add_do_method(this, "_set_selection_from_array", Array());', rectangle)
        self.assertIn('undo_redo->add_do_method(tile_set_atlas_source, "remove_tile", coords);', rectangle)
        self.assertIn('undo_redo->add_undo_method(tile_set_atlas_source, "create_tile", coords);', rectangle)

    def test_regular_tile_removal_is_not_retargeted_by_accident(self):
        before_rect = self.atlas_source.split("case DRAG_TYPE_REMOVE_TILES_USING_RECT: {", 1)[0]
        standard_removal = before_rect.rsplit("case DRAG_TYPE_REMOVE_TILES: {", 1)[1]
        self.assertIn('undo_redo->create_action(TTR("Remove tiles"));', standard_removal)
        self.assertNotIn("UndoRedo::MERGE_DISABLE, tile_set_atlas_source", standard_removal)

    def test_existing_gdscript_translation_parser_cleanup_matches_init_level(self):
        source = _source("modules/gdscript/register_types.cpp")
        initialize = _body(source, "void initialize_gdscript_module(")
        uninitialize = _body(source, "void uninitialize_gdscript_module(")
        self.assertRegex(
            initialize,
            r'if \(p_level == MODULE_INITIALIZATION_LEVEL_SERVERS\) \{'
            r'[\s\S]*?EditorTranslationParser::get_singleton\(\)->add_parser',
        )
        self.assertRegex(
            uninitialize,
            r'#ifdef TOOLS_ENABLED\s*if \(p_level == MODULE_INITIALIZATION_LEVEL_SERVERS\) \{\s*'
            r'EditorTranslationParser::get_singleton\(\)->remove_parser',
        )
        self.assertIn("gdscript_translation_parser_plugin.unref();", uninitialize)


if __name__ == "__main__":
    unittest.main()
