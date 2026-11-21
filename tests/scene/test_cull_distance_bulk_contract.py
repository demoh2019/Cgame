"""Native bulk CullDistanceProfile3D + real Albion quality-switch source contracts.

Inspectability only: compile Cgame and run headless Godot to verify execution.
"""
from pathlib import Path
import unittest
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[2]
ENGINE = ROOT / "modules/cull_distance_policy"
GAME = ROOT / "game/scripts/client"
TEST = ROOT / "game/tests/test_scenery_lod.gd"


class TestCullDistanceBulkContract(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.h = (ENGINE / "cull_distance_profile_3d.h").read_text()
        cls.cpp = (ENGINE / "cull_distance_profile_3d.cpp").read_text()
        cls.scenery = (GAME / "scenery_lod.gd").read_text()
        cls.quality = (GAME / "graphics_quality.gd").read_text()
        cls.tests = TEST.read_text()

    def test_native_bulk_api_is_bounded_and_pure(self):
        self.assertIn("static constexpr int MAX_BATCH = 4096;", self.h)
        self.assertIn("PackedFloat64Array get_cached_cull_distances(", self.h)
        self.assertIn("const PackedVector3Array &p_positions", self.h)
        self.assertIn("const PackedVector3Array &p_sizes", self.h)
        self.assertIn("const PackedFloat64Array &p_authored_distances", self.h)
        self.assertIn('D_METHOD("get_cached_cull_distances", "positions", "sizes", "authored_distances")', self.cpp)
        body = self.cpp.split(
            "PackedFloat64Array CullDistanceProfile3D::get_cached_cull_distances(", 1
        )[1].split("double CullDistanceProfile3D::get_cull_distance(", 1)[0]
        self.assertIn("configured_sizes.is_empty()", body)
        self.assertIn("count != p_sizes.size()", body)
        self.assertIn("count != p_authored_distances.size()", body)
        self.assertIn("count > MAX_BATCH", body)
        self.assertIn("_valid_bounds(AABB(p_positions[i], p_sizes[i]), p_authored_distances[i])", body)
        self.assertLess(body.index("if (!_valid_bounds("), body.index("result.resize(count);"))
        self.assertIn("_resolve_validated(AABB(p_positions[i], p_sizes[i]),", body)
        self.assertIn("configured_sizes, configured_ranges, p_authored_distances[i]", body)
        for forbidden in ("SceneTree", "RenderingServer", "Thread", "emit_signal"):
            self.assertNotIn(forbidden, body)

    def test_albion_quality_updates_use_bulk_not_one_native_call_per_node(self):
        self.assertIn("SceneryLod.apply_many(", self.quality)
        live = self.quality.split("ChunkView.configure_scenery(_level)", 1)[1].split(
            "# The graphics profiles also control water", 1
        )[0]
        self.assertIn("get_nodes_in_group(ChunkView.SCENERY_GROUP)", live)
        self.assertIn("SceneryLod.apply_many(", live)
        self.assertNotIn("ChunkView.apply_scenery_detail(batch)", live)
        self.assertIn("const MAX_CULL_BATCH := 4096", self.scenery)
        bulk = self.scenery.split("static func apply_many(", 1)[1]
        self.assertIn('node.has_meta("aa_scenery_kind")', bulk)
        self.assertIn('instance.get_meta("aa_scenery_distance", 0.0)', bulk)
        self.assertIn('if group != "decor" or base_distance <= 0.0', bulk)
        self.assertIn("positions.append(bounds.position)", bulk)
        self.assertIn("sizes.append(bounds.size)", bulk)
        self.assertIn("authored.append(end_distance)", bulk)
        self.assertIn("if pending.size() == MAX_CULL_BATCH:", bulk)
        self.assertIn("_apply_decor_cull_batch(pending, positions, sizes, authored, safe_quality)", bulk)
        self.assertIn("pending.clear()", bulk)
        self.assertIn("static func apply(instance: MultiMeshInstance3D", self.scenery)

    def test_native_failures_and_older_engines_remain_safe(self):
        section = self.scenery.split("static func _apply_decor_cull_batch(", 1)[1].split(
            "static func apply_many(", 1
        )[0]
        self.assertIn('native.has_method("get_cached_cull_distances")', section)
        self.assertIn('"get_cached_cull_distances", positions, sizes, authored', section)
        self.assertIn("result.size() == instances.size()", section)
        self.assertIn("decor_range_for_bounds(AABB(positions[i], sizes[i]), quality,", section)
        self.assertIn("instances[i].visibility_range_end_margin = 12.0 if end_distance > 0.0 else 0.0", section)
        self.assertIn("if end_distance < 0.0 or not is_finite(end_distance):", section)
        bulk = self.scenery.split("static func apply_many(", 1)[1]
        self.assertIn("bounds.size == Vector3.ZERO", bulk)
        self.assertIn('var group: String = category(kind)', bulk)
        self.assertIn('instance.lod_bias = float(limits["lod_bias"])', bulk)

    def test_cxx_and_game_reproduction_cover_native_batch_limit_and_parity(self):
        native_tests = (ENGINE / "tests/test_cull_distance_profile_3d.h").read_text()
        self.assertIn("bulk cached profile equals scalar selection with stable ordering", native_tests)
        self.assertIn("bulk malformed request fails atomically and is bounded", native_tests)
        self.assertIn("CullDistanceProfile3D::MAX_BATCH", native_tests)
        self.assertIn("i < CullDistanceProfile3D::MAX_BATCH", native_tests)
        self.assertIn("get_cached_cull_distance(AABB(positions[i], sizes[i])", native_tests)
        self.assertIn("native bulk returns ordered values", self.tests)
        self.assertIn("bad final entry rejects entire native batch", self.tests)
        self.assertIn("bulk and per-instance draw ranges agree", self.tests)
        self.assertIn("last entry in full 4096-instance native batch", self.tests)
        self.assertIn("first entry after the batch boundary is handled", self.tests)
        self.assertIn("unregistered scene nodes cannot be altered", self.tests)

    def test_documentation_workflow(self):
        xml = ET.parse(ENGINE / "doc_classes/CullDistanceProfile3D.xml").getroot()
        self.assertIn("get_cached_cull_distances",
                      {m.get("name") for m in xml.findall("./methods/method")})
        self.assertIn("4096", (ENGINE / "README.md").read_text())
        workflow = (ROOT / ".github/workflows/native-cull-distance-policy.yml").read_text()
        self.assertIn("test_cull_distance_bulk_contract.py", workflow)
        self.assertIn("game/scripts/client/graphics_quality.gd", workflow)
        self.assertIn("run_cull_distance_policy.gd", workflow)


if __name__ == "__main__":
    unittest.main()
