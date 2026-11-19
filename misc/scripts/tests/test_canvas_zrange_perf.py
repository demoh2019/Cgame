"""Source-level regressions for Cgame's allocation-free canvas Z-range culling.

Use the native engine build and visual tests to assess rendering behavior;
these assertions verify structural invariants rather than a GPU output.
"""
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
CPP = (ROOT / "servers/rendering/renderer_canvas_cull.cpp").read_text(encoding="utf-8")
HEADER = (ROOT / "servers/rendering/renderer_canvas_cull.h").read_text(encoding="utf-8")


def section(start, end):
    assert CPP.count(start) == 1, start
    return CPP.split(start, 1)[1].split(end, 1)[0]


class CanvasZRangePerformance(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.render = section("void RendererCanvasCull::_render_canvas_item_tree(", "void RendererCanvasCull::_collect_ysort_children(")
        cls.attach = section("void RendererCanvasCull::_attach_canvas_item_for_draw(", "void RendererCanvasCull::_cull_canvas_item(")
        cls.constructor = section("RendererCanvasCull::RendererCanvasCull() {", "RendererCanvasCull::~RendererCanvasCull()")

    def test_zrange_matches_rendering_server(self):
        self.assertIn("static constexpr int z_range = RSE::CANVAS_ITEM_Z_MAX - RSE::CANVAS_ITEM_Z_MIN + 1;", HEADER)

    def test_keep_original_bucket_storage(self):
        self.assertIn("RendererCanvasRender::Item **z_list;", HEADER)
        self.assertIn("RendererCanvasRender::Item **z_last_list;", HEADER)

    def test_min_starts_outside_valid_z_bins(self):
        self.assertIn("int z_min_used = z_range;", HEADER)

    def test_max_starts_before_valid_z_bins(self):
        self.assertIn("int z_max_used = -1;", HEADER)

    def test_no_extra_dynamic_z_index_container(self):
        sub = HEADER.split("static constexpr int z_range", 1)[1].split("Transform2D _current_camera_transform", 1)[0]
        self.assertNotIn("Vector<", sub)
        self.assertNotIn("HashMap<", sub)

    def test_queues_are_zero_initialized_at_construction(self):
        self.assertIn("memset(z_list, 0, z_range * sizeof(*z_list));", self.constructor)
        self.assertIn("memset(z_last_list, 0, z_range * sizeof(*z_last_list));", self.constructor)

    def test_old_range_cleared_only_when_nonempty(self):
        self.assertIn("if (z_min_used <= z_max_used)", self.render)

    def test_old_span_count_inclusive(self):
        self.assertIn("const int count = z_max_used - z_min_used + 1;", self.render)

    def test_clears_both_lists_for_old_range(self):
        self.assertIn("memset(z_list + z_min_used, 0, count * sizeof(*z_list));", self.render)
        self.assertIn("memset(z_last_list + z_min_used, 0, count * sizeof(*z_last_list));", self.render)

    def test_reset_bounds_after_old_clear(self):
        self.assertLess(self.render.index("memset(z_last_list + z_min_used"), self.render.index("z_min_used = z_range;"))
        self.assertLess(self.render.index("z_min_used = z_range;"), self.render.index("for (int i = 0; i < p_child_item_count; i++)"))
        self.assertIn("z_max_used = -1;", self.render)

    def test_new_bins_record_minimum(self):
        self.assertIn("z_min_used = MIN(z_min_used, zidx);", self.attach)

    def test_new_bins_record_maximum(self):
        self.assertIn("z_max_used = MAX(z_max_used, zidx);", self.attach)

    def test_bounds_only_updated_when_new_bucket_is_inserted(self):
        bucket = self.attach.split("if (r_z_last_list[zidx])", 1)[1].split("ci->z_final = p_z;", 1)[0]
        self.assertIn("} else {", bucket)
        self.assertLess(bucket.index("r_z_list[zidx] = ci;"), bucket.index("z_min_used = MIN"))
        self.assertLess(bucket.index("r_z_last_list[zidx] = ci;"), bucket.index("z_max_used = MAX"))

    def test_existing_bucket_append_unchanged(self):
        self.assertIn("r_z_last_list[zidx]->next = ci;", self.attach)
        self.assertIn("r_z_last_list[zidx] = ci;", self.attach)

    def test_new_bucket_next_terminated(self):
        self.assertIn("ci->next = nullptr;", self.attach)

    def test_sorted_output_scans_used_range_only(self):
        self.assertIn("for (int i = z_min_used; i <= z_max_used; i++)", self.render)
        self.assertNotIn("for (int i = 0; i < z_range; i++)", self.render)

    def test_stable_bucket_order_retained(self):
        self.assertIn("list_end->next = z_list[i];", self.render)
        self.assertIn("list_end = z_last_list[i];", self.render)

    def test_root_culling_retained(self):
        self.assertIn("_cull_canvas_item(p_child_items[i].item", self.render)

    def test_renderer_runs_with_empty_list(self):
        self.assertIn("RendererCanvasRender::Item *list = nullptr;", self.render)
        self.assertIn("canvas_render_items(p_to_render_target, list,", self.render)

    def test_legacy_full_clears_no_longer_per_frame(self):
        self.assertNotIn("memset(z_list, 0, z_range", self.render)
        self.assertNotIn("memset(z_last_list, 0, z_range", self.render)

    def test_z_index_transformation_preserved(self):
        self.assertIn("int zidx = p_z - RSE::CANVAS_ITEM_Z_MIN;", self.attach)

    def test_sdf_status_still_reported(self):
        self.assertIn("if (sdf_flag)", self.render)


if __name__ == "__main__":
    unittest.main()
