"""Static regression coverage for lazy linked-resource accounting, upstream #122469.

Native editor behavior and the performance benefit still need CI / smoke tests.
"""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[3]


def src(name):
    return (ROOT / name).read_text(encoding="utf-8")


CPP = src("editor/editor_node.cpp")
HEADER = src("editor/editor_node.h")
INSPECTOR = src("editor/inspector/editor_inspector.cpp")
MULTI = src("editor/inspector/multi_node_edit.cpp")
SCENE_TREE = src("editor/scene/scene_tree_editor.cpp")
SCENE_HEADER = src("editor/scene/scene_tree_editor.h")


class LazyEditorResourcesContracts(unittest.TestCase):
    def test_queries_are_lazy(self):
        self.assertIn("void EditorNode::_ensure_resource_usage_cache()", CPP)
        self.assertIn("_ensure_resource_usage_cache();", CPP)

    def test_resource_count_does_not_iterate_scene(self):
        start = CPP.index("int EditorNode::get_resource_count(")
        end = CPP.index("void EditorNode::_menu_option(", start)
        body = CPP[start:end]
        self.assertIn("resource_node_usage.getptr(p_res)", body)
        self.assertNotIn("gather_resources(", body)

    def test_forward_and_backward_snapshots_are_present(self):
        self.assertIn("HashMap<ObjectID, HashSet<Ref<Resource>>> node_resource_usage;", HEADER)
        self.assertIn("HashMap<Ref<Resource>, HashSet<ObjectID>> resource_node_usage;", HEADER)

    def test_rescans_only_dirty_nodes(self):
        self.assertIn("dirty_resource_usage_nodes.clear();", CPP)
        self.assertIn("_reconcile_node_resource_usage(node);", CPP)
        self.assertIn("void EditorNode::mark_node_resource_usage_dirty(", CPP)

    def test_snapshot_prunes_deleted_node_ids(self):
        self.assertIn("ObjectDB::get_instance<Node>(node_id)", CPP)
        self.assertIn("_remove_resource_usage_snapshot(node_id);", CPP)

    def test_nested_resources_are_collected(self):
        self.assertIn("gather_resources(p_node, resources, scanned_objects, true)", CPP)
        self.assertIn("is_resource_internal_to_scene(resource)", CPP)

    def test_resource_changes_invalidate_only_affected_nodes(self):
        self.assertIn("resource->connect_changed(callback);", CPP)
        self.assertIn("resource->disconnect_changed(callback);", CPP)
        self.assertIn("dirty_resource_usage_nodes.insert(node_id)", CPP)

    def test_undo_redo_remains_dirty_aware(self):
        self.assertIn('EditorUndoRedoManager::get_singleton()->connect("version_changed"', CPP)
        self.assertIn("_undo_redo_resource_usage_changed", CPP)
        self.assertIn('"mark_node_resource_usage_dirty", N', INSPECTOR)

    def test_inspector_untracked_resource_changes_invalidate_index(self):
        self.assertIn("invalidate_resource_usage_cache();", INSPECTOR)
        self.assertIn("mark_node_resource_usage_dirty(node);", INSPECTOR)

    def test_multiselect_updates_only_selected_nodes(self):
        self.assertIn("mark_node_resource_usage_dirty", MULTI)
        self.assertNotIn("update_node_reference", MULTI)

    def test_tree_refresh_does_not_scan_all_properties(self):
        self.assertNotIn("update_resource_count(p_node)", SCENE_TREE)
        self.assertIn("cache_entry->value.editable_instance =", SCENE_TREE)

    def test_node_removal_removes_snapshot_without_rescan(self):
        self.assertIn("remove_node_from_resource_usage_cache", SCENE_TREE)
        self.assertIn("_remove_resource_usage_snapshot(p_node->get_instance_id())", CPP)

    def test_editable_instances_mark_subtrees(self):
        self.assertIn("_mark_resource_usage_subtree_dirty(p_node)", SCENE_TREE)
        self.assertIn("bool editable_instance = false;", SCENE_HEADER)

    def test_reuses_coalesced_resource_counter_signal(self):
        self.assertIn("void EditorNode::_queue_resource_counter_changed()", CPP)
        self.assertNotIn("void EditorNode::_queue_resource_usage_changed()", CPP)

    def test_cache_invalidated_on_scene_switch(self):
        self.assertIn("resource_usage_scene_id != scene_id", CPP)
        self.assertIn("_reset_resource_usage_cache();", CPP)

    def test_no_legacy_resource_reference_scans(self):
        for text in ("get_resource_node_list(", "update_node_reference("):
            with self.subTest(legacy=text):
                self.assertNotIn(text, CPP)
                self.assertNotIn(text, INSPECTOR)


if __name__ == "__main__":
    unittest.main()
