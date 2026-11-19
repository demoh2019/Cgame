"""Regression contracts for upstream Godot PRs #125467 and #125410.

This suite validates actual Cgame C++ source structure, not running gameplay.
Editor integration and native compilation are separate CI/manual checks.
"""

from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[3]


def source(path):
    return (ROOT / path).read_text(encoding="utf-8")


def between(text, start, end):
    if text.count(start) != 1:
        raise AssertionError(f"expected one start marker: {start}")
    after = text.split(start, 1)[1]
    if end not in after:
        raise AssertionError(f"missing end marker: {end}")
    return after.split(end, 1)[0]


class SceneReimportContracts(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        code = source("editor/editor_node.cpp")
        cls.header = source("editor/editor_node.h")
        cls.before = between(code, "void EditorNode::_resources_reimporting(",
                             "void EditorNode::_resources_reimported(")
        cls.after = between(code, "void EditorNode::_resources_reimported(",
                            "void EditorNode::_sources_changed(")
        cls.preload = between(code, "void EditorNode::preload_reimporting_with_path_in_edited_scenes(",
                              "void EditorNode::reload_instances_with_path_in_edited_scenes(")
        cls.reload = between(code, "void EditorNode::reload_uninstanced_scenes() {",
                             "void EditorNode::_remove_all_not_owned_children(")

    def test_tracks_uninstanced_scenes_in_editor_node(self):
        self.assertIn("List<String> uninstanced_scenes_reimported;", self.header)

    def test_declares_reload_function(self):
        self.assertIn("void reload_uninstanced_scenes();", self.header)

    def test_reimport_start_resets_uninstanced_list(self):
        self.assertIn("uninstanced_scenes_reimported.clear();", self.before)

    def test_start_clears_list_after_other_reimport_state(self):
        self.assertLess(self.before.index("resources_reimported.clear();"),
                        self.before.index("uninstanced_scenes_reimported.clear();"))

    def test_clear_happens_before_resource_scan(self):
        self.assertLess(self.before.index("uninstanced_scenes_reimported.clear();"),
                        self.before.index("for (const String &res_path : p_resources)"))

    def test_original_scene_reload_kept(self):
        self.assertIn("reload_instances_with_path_in_edited_scenes();", self.after)

    def test_uninstanced_reload_triggered(self):
        self.assertIn("reload_uninstanced_scenes();", self.after)

    def test_uninstanced_reload_after_instance_reload(self):
        self.assertLess(self.after.index("reload_instances_with_path_in_edited_scenes();"),
                        self.after.index("reload_uninstanced_scenes();"))

    def test_reloads_before_clearing_snapshot_state(self):
        self.assertLess(self.after.index("reload_uninstanced_scenes();"),
                        self.after.index("scenes_modification_table.clear();"))

    def test_preload_records_missing_instances(self):
        self.assertIn("uninstanced_scenes_reimported.push_back(instance_path);", self.preload)

    def test_preload_only_records_when_other_branch_did_not_find_instances(self):
        self.assertRegex(
            self.preload,
            re.compile(
                r"get_preload_modifications_reference_to_nodes\("
                r"edited_scene_root, edited_scene_root, instances_to_reimport,"
                r"\s*instance_list_with_children,\s*"
                r"scene_modifications\.other_instances_modifications\);"
                r"\s*\} else \{\s*"
                r"uninstanced_scenes_reimported\.push_back\(instance_path\);",
                re.S,
            ),
        )

    def test_empty_list_bails_out_without_disk_load(self):
        self.assertRegex(self.reload, re.compile(
            r"if \(uninstanced_scenes_reimported\.is_empty\(\)\)\s*\{\s*return;\s*\}"))

    def test_uses_stored_reimport_paths(self):
        self.assertIn("for (String &scene_path : uninstanced_scenes_reimported)", self.reload)

    def test_reload_uses_cache_replacement_mode(self):
        self.assertIn("ResourceFormatLoader::CACHE_MODE_REPLACE_DEEP", self.reload)

    def test_reload_passes_original_scene_path(self):
        self.assertIn('ResourceLoader::load(scene_path, "",', self.reload)

    def test_reload_checks_error_return(self):
        self.assertIn("ERR_FAIL_COND(err != OK);", self.reload)

    def test_reload_checks_null_packed_scene(self):
        self.assertIn("ERR_FAIL_COND(instance_scene_packed_scene.is_null());", self.reload)

    def test_reload_retains_packed_scene_reference(self):
        self.assertIn("Ref<PackedScene> instance_scene_packed_scene =", self.reload)

    def test_header_preserves_original_reimport_lists(self):
        self.assertIn("List<String> scenes_reimported;", self.header)
        self.assertIn("List<String> resources_reimported;", self.header)

    def test_preload_keeps_current_scene_modification_tracking(self):
        self.assertIn("scenes_modification_table[current_scene_idx] = scene_modifications;", self.preload)

    def test_no_unconditional_project_wide_cache_flush(self):
        self.assertNotIn("ResourceCache::clear()", self.reload)

    def test_no_scene_execution_in_reload_method(self):
        self.assertNotIn("instantiate(", self.reload)
        self.assertNotIn("set_current_scene(", self.reload)


class Path3DGizmoContracts(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        code = source("editor/scene/3d/path_3d_editor_plugin.cpp")
        body = code.split("void Path3DGizmo::redraw() {", 1)
        if len(body) != 2:
            raise AssertionError("Path3DGizmo::redraw not found")
        cls.redraw = body[1].split("\n}\n", 1)[0]

    def test_redraw_clears_previous_visuals(self):
        self.assertRegex(self.redraw, re.compile(r"^\s*clear\(\);"))

    def test_handle_block_requires_actual_gizmo_selection(self):
        self.assertRegex(self.redraw, re.compile(
            r"// 2\. Draw handles when selected\.\s*if \(is_selected\(\)\) \{"))

    def test_stale_editor_path_comparison_removed(self):
        self.assertNotIn("get_edited_path() == path", self.redraw)

    def test_selection_guard_wraps_handle_geometry(self):
        pos = self.redraw.index("if (is_selected()) {")
        self.assertLess(pos, self.redraw.index("PackedVector3Array handle_lines;", pos))

    def test_tilt_handles_still_created(self):
        self.assertIn("PackedVector3Array tilt_handle_lines;", self.redraw)

    def test_primary_handles_still_created(self):
        self.assertIn("PackedVector3Array primary_handle_points;", self.redraw)

    def test_secondary_handles_still_created(self):
        self.assertIn("PackedVector3Array secondary_handle_points;", self.redraw)

    def test_handles_get_curve_point_count(self):
        self.assertIn("_secondary_handles_info.resize(c->get_point_count() * 3);", self.redraw)

    def test_path_geometry_is_drawn_before_handles(self):
        self.assertLess(self.redraw.index("add_collision_segments(_collision_segments);"),
                        self.redraw.index("if (is_selected()) {"))


if __name__ == "__main__":
    unittest.main()
