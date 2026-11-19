"""Regression contracts for selected upstream performance improvements.

These inspect the checked-out Cgame source.  They guard structural invariants;
a Cgame editor build and actual GPU/GUI performance profiling are separate checks.
"""

from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[3]


def read(relative):
    return (ROOT / relative).read_text(encoding="utf-8")


class DirectionalShadowCullingContracts(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.src = read("servers/rendering/renderer_scene_cull.cpp")
        cls.block = cls.src.split("// Filter per-instance and per-light conditions before the expensive per-cascade culler.", 1)[1].split(
            "#undef HIDDEN_BY_VISIBILITY_CHECKS", 1
        )[0]

    def test_culling_stays_in_scene_cull(self):
        self.assertIn("void RendererSceneCull::_scene_cull(", self.src)

    def test_shadow_work_skipped_when_no_shadows(self):
        self.assertIn("cull_data.cull->shadow_count > 0 && VIS_CHECK", self.block)

    def test_base_type_is_hoisted(self):
        self.assertIn("const uint32_t shadow_base_type = idata.flags & InstanceData::FLAG_BASE_TYPE_MASK;", self.block)
        self.assertLess(self.block.index("const uint32_t shadow_base_type ="), self.block.index("for (uint32_t j ="))

    def test_visibility_is_hoisted_before_light_loop(self):
        self.assertLess(self.block.index("&& VIS_CHECK &&"), self.block.index("for (uint32_t j ="))

    def test_non_geometry_skips_entire_shadow_loop(self):
        self.assertIn("((1 << shadow_base_type) & RSE::INSTANCE_GEOMETRY_MASK)", self.block)
        self.assertLess(self.block.index("RSE::INSTANCE_GEOMETRY_MASK"), self.block.index("for (uint32_t j ="))

    def test_non_shadow_casters_skip_entire_shadow_loop(self):
        self.assertIn("idata.flags & InstanceData::FLAG_CAST_SHADOWS", self.block)
        self.assertLess(self.block.index("FLAG_CAST_SHADOWS"), self.block.index("for (uint32_t j ="))

    def test_inactive_particles_skip_entire_shadow_loop(self):
        self.assertIn("shadow_base_type == RSE::INSTANCE_PARTICLES", self.block)
        self.assertIn("RSG::particles_storage->particles_is_inactive(idata.base_rid)", self.block)
        self.assertLess(self.block.index("particles_is_inactive"), self.block.index("for (uint32_t j ="))

    def test_particle_state_is_short_circuited_by_type(self):
        self.assertIn("shadow_base_type == RSE::INSTANCE_PARTICLES && RSG::particles_storage", self.block)

    def test_outer_light_loop_is_retained(self):
        self.assertIn("for (uint32_t j = 0; j < cull_data.cull->shadow_count; j++)", self.block)

    def test_light_layer_filter_before_cascade_loop(self):
        self.assertLess(
            self.block.index("if (!(LAYER_CHECK & cull_data.cull->shadows[j].caster_mask))"),
            self.block.index("for (uint32_t k ="),
        )

    def test_layer_mismatch_skips_cascades(self):
        self.assertRegex(self.block, re.compile(
            r"if \(!\(LAYER_CHECK & cull_data\.cull->shadows\[j\]\.caster_mask\)\)\s*\{\s*continue;\s*\}",
            re.S,
        ))

    def test_cascade_loop_is_retained(self):
        self.assertIn("k < cull_data.cull->shadows[j].cascade_count", self.block)

    def test_fast_frustum_before_expensive_culling(self):
        self.assertLess(
            self.block.index("if (!IN_FRUSTUM(cull_data.cull->shadows[j].cascades[k].frustum))"),
            self.block.index("light_culler->cull_directional_light("),
        )

    def test_frustum_mismatch_skips_expensive_culling(self):
        self.assertRegex(self.block, re.compile(
            r"if \(!IN_FRUSTUM\(cull_data\.cull->shadows\[j\]\.cascades\[k\]\.frustum\)\)\s*\{\s*continue;\s*\}",
            re.S,
        ))

    def test_expensive_culler_is_called_only_once_per_candidate(self):
        self.assertEqual(self.block.count("light_culler->cull_directional_light("), 1)

    def test_expensive_failure_still_skips_cascade(self):
        self.assertRegex(self.block, re.compile(
            r"if \(!light_culler->cull_directional_light\([^;]+\)\)\s*\{\s*continue;\s*\}",
            re.S,
        ))

    def test_shadow_geometry_is_appended_once(self):
        self.assertEqual(
            self.block.count("cull_result.directional_shadows[j].cascade_geometry_instances[k].push_back(idata.instance_geometry);"),
            1,
        )

    def test_geometry_appears_only_after_expensive_culling(self):
        self.assertLess(
            self.block.index("light_culler->cull_directional_light("),
            self.block.index("cascade_geometry_instances[k].push_back("),
        )

    def test_mesh_visibility_is_still_set(self):
        self.assertIn("mesh_visible = true;", self.block)

    def test_no_dynamic_allocation_in_shadow_loop(self):
        self.assertNotIn("memnew(", self.block)
        self.assertNotIn("new ", self.block)

    def test_visibility_macro_is_preserved(self):
        self.assertIn("#define VIS_CHECK", self.src)
        self.assertIn("#undef VIS_CHECK", self.src)


class FileSystemThumbnailContracts(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.src = read("editor/docks/filesystem_dock.cpp")
        cls.hdr = read("editor/docks/filesystem_dock.h")

    def test_collapsed_tree_previews_are_deferred(self):
        self.assertIn("const bool files_shown = _is_tree_item_expanded(subdirectory_item);", self.src)
        self.assertRegex(self.src, re.compile(r"if \(files_shown\)\s*\{\s*_queue_tree_item_preview\(file_item, file_metadata\);", re.S))

    def test_collapsed_favorites_do_not_schedule_previews(self):
        self.assertIn('!favorite.ends_with("/") && !favorites_item->is_collapsed()', self.src)

    def test_tree_update_clears_prior_preview_set(self):
        self.assertIn("tree_preview_requested.clear();", self.src)

    def test_tree_update_clears_old_pending_previews(self):
        self.assertIn("pending_tree_thumbnails.clear();", self.src)

    def test_old_generation_callback_ignored(self):
        self.assertIn("if (tree_update_id != p_update_id || p_small_preview.is_null())", self.src)

    def test_callbacks_buffer_thumbnail_instead_of_redrawing(self):
        self.assertIn("pending_tree_thumbnails.push_back({ p_item, p_path, p_small_preview });", self.src)

    def test_thumbnail_flushing_is_deferred_to_internal_process(self):
        self.assertIn("case NOTIFICATION_INTERNAL_PROCESS:", self.src)
        self.assertIn("_apply_pending_tree_thumbnails();", self.src)

    def test_internal_process_is_enabled_only_on_pending_update(self):
        self.assertIn("set_process_internal(true);", self.src)
        self.assertIn("set_process_internal(false);", self.src)

    def test_pending_thumbnail_objects_are_checked_for_liveness(self):
        self.assertIn("ObjectDB::get_instance<TreeItem>(pending.item)", self.src)
        self.assertIn("if (item) {", self.src)

    def test_preview_set_deduplicates_by_object_id(self):
        self.assertIn("if (tree_preview_requested.has(id))", self.src)
        self.assertIn("tree_preview_requested.insert(id);", self.src)

    def test_preview_queue_uses_current_tree_generation(self):
        self.assertIn("_tree_thumbnail_done).bind(tree_update_id, id)", self.src)

    def test_visibility_checks_parent_folders(self):
        self.assertIn("for (TreeItem *item = p_item; item; item = item->get_parent())", self.src)
        self.assertIn("if (item->is_collapsed())", self.src)

    def test_expanding_a_folder_schedules_descendant_previews(self):
        self.assertIn('tree->connect("item_collapsed", callable_mp(this, &FileSystemDock::_tree_item_collapsed));', self.src)
        self.assertIn("_queue_tree_children_previews(p_item);", self.src)

    def test_recursion_skips_still_collapsed_children(self):
        self.assertIn("else if (!child->is_collapsed())", self.src)

    def test_only_resource_paths_are_previewed(self):
        self.assertIn('if (!path.begins_with("res://"))', self.src)

    def test_file_previews_not_requested_for_directories(self):
        self.assertIn('if (!path.ends_with("/"))', self.src)

    def test_pending_struct_is_declared(self):
        self.assertIn("struct PendingTreeThumbnail", self.hdr)

    def test_pending_preview_has_path_and_ref(self):
        self.assertIn("String path;", self.hdr)
        self.assertIn("Ref<Texture2D> preview;", self.hdr)

    def test_dedupe_set_is_declared(self):
        self.assertIn("HashSet<ObjectID> tree_preview_requested;", self.hdr)

    def test_batch_uses_local_vector_not_heap_list_nodes(self):
        self.assertIn("LocalVector<PendingTreeThumbnail> pending_tree_thumbnails;", self.hdr)

    def test_public_search_is_unaffected(self):
        self.assertIn("_file_list_thumbnail_done(", self.src)

    def test_estimated_request_reduction_for_closed_folders(self):
        # Synthetic model of editor tree layout; does not benchmark the actual editor.
        folders, files_per_folder, opened_folders = 1000, 50, 2
        previous_requests = folders * files_per_folder
        lazy_requests = opened_folders * files_per_folder
        self.assertEqual(previous_requests, 50000)
        self.assertEqual(lazy_requests, 100)
        self.assertLess(lazy_requests, previous_requests)


class UnixDirectoryInitializationContracts(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.src = read("drivers/unix/dir_access_unix.cpp")
        cls.ctor = cls.src.split("DirAccessUnix::DirAccessUnix() {", 1)[1].split(
            "DirAccessUnix::RemoveNotificationFunc", 1
        )[0]

    def test_current_directory_is_still_read(self):
        self.assertIn("getcwd(real_current_dir_name, 2048)", self.ctor)

    def test_directory_utf8_is_preserved(self):
        self.assertIn("current_dir.append_utf8(real_current_dir_name)", self.ctor)

    def test_fallback_to_cwd_name_remains(self):
        self.assertIn("current_dir = real_current_dir_name;", self.ctor)

    def test_no_redundant_change_dir_in_constructor(self):
        self.assertNotIn("change_dir(current_dir);", self.ctor)

    def test_directory_stream_initialized_as_null(self):
        self.assertIn("dir_stream = nullptr;", self.ctor)

    def test_cleanup_still_ends_directory_list(self):
        self.assertIn("DirAccessUnix::~DirAccessUnix()", self.src)
        self.assertIn("list_dir_end();", self.src)


if __name__ == "__main__":
    unittest.main()
