"""Source contracts for reusable native Cull Distance profiles.

This checks API wiring and application to Albion After. It is not a
substitute for compiling the custom engine or running headless Godot tests.
"""
from pathlib import Path
import math
import unittest
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[2]
NATIVE = ROOT / "modules/cull_distance_policy"
SCENERY = ROOT / "game/scripts/client/scenery_lod.gd"
GAME_TEST = ROOT / "game/tests/test_scenery_lod.gd"
WORKFLOW = ROOT / ".github/workflows/native-cull-distance-policy.yml"


class TestCullDistanceCachedContract(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.cpp = (NATIVE / "cull_distance_profile_3d.cpp").read_text()
        cls.header = (NATIVE / "cull_distance_profile_3d.h").read_text()
        cls.game = SCENERY.read_text()
        cls.tests = GAME_TEST.read_text()

    def test_native_profile_validation_and_atomicity(self):
        for signature in (
            "bool configure(const PackedFloat32Array &p_sizes, const PackedFloat32Array &p_ranges)",
            "double get_cached_cull_distance(const AABB &p_bounds,",
            "PackedFloat32Array configured_sizes",
            "PackedFloat32Array configured_ranges",
        ):
            self.assertIn(signature, self.header)
        for statement in (
            "_valid_pairs(p_sizes, p_ranges)",
            "configured_sizes = p_sizes;",
            "configured_ranges = p_ranges;",
            "configured_sizes.clear();",
            "configured_ranges.clear();",
            "_resolve_validated(p_bounds, configured_sizes, configured_ranges, p_authored_distance)",
            "_resolve_validated(p_bounds, p_sizes, p_ranges, p_authored_distance)",
            "p_sizes.size() > MAX_PAIRS",
            "Math::is_finite(p_authored_distance)",
            "p_bounds.position.is_finite()",
        ):
            self.assertIn(statement, self.cpp)
        self.assertLess(self.cpp.index("if (!_valid_pairs(p_sizes, p_ranges))"),
                        self.cpp.index("configured_sizes = p_sizes;"))
        # Shared selection implementation must preserve old tie and cap semantics.
        self.assertIn("candidate_range > 0.0", self.cpp)
        self.assertIn("MIN(selected_range, p_authored_distance)", self.cpp)
        self.assertNotIn("SceneTree", self.cpp)
        self.assertNotIn("RenderingServer", self.cpp)

    def test_native_binding_and_reference_documentation(self):
        for name in ("configure", "get_pair_count", "clear_profile", "get_cached_cull_distance"):
            self.assertIn('D_METHOD("' + name + '"', self.cpp)
        doc = ET.parse(NATIVE / "doc_classes/CullDistanceProfile3D.xml").getroot()
        methods = {m.get("name") for m in doc.findall("./methods/method")}
        self.assertTrue({"configure", "get_pair_count", "clear_profile",
                         "get_cached_cull_distance", "get_cull_distance"} <= methods)

    def test_albion_caches_presets_and_retains_old_engine_fallback(self):
        for section in (
            "_decor_profile_sizes:",
            "_decor_profile_ranges_by_quality:",
            "_decor_cached_profiles:",
            "_decor_cached_api_state",
            'probe.has_method("configure")',
            'probe.has_method("get_cached_cull_distance")',
            '"get_cached_cull_distance", bounds, authored_distance',
            'cull_range_for_bounds(bounds, _decor_profile_sizes,',
            'if authored_distance <= 0.0',
            'category(kind) == "decor"',
        ):
            self.assertIn(section, self.game)
        hot_path = self.game.split("static func decor_range_for_bounds(", 1)[1].split(
            "static func apply(", 1)[0]
        self.assertNotIn("PackedFloat32Array([", hot_path)
        self.assertIn("_decor_ranges_for_quality(safe_level)", hot_path)
        self.assertIn("_decor_native_profile(safe_level", hot_path)
        self.assertIn("return cached_result if cached_result >= 0.0 else authored_distance", hot_path)
        self.assertIn("if prefer_native:", hot_path)
        self.assertIn("for quality in 4:", self.tests)
        self.assertIn("invalid reconfiguration is rejected atomically", self.tests)
        native_test = (NATIVE / "tests/test_cull_distance_profile_3d.h").read_text()
        self.assertIn("configured profiles match one-off queries across bounds", native_test)
        self.assertIn("independent configured quality presets", native_test)

    def test_profile_quality_order_and_authored_caps_reference(self):
        sizes = [1., 4., 10., 24., 64.]
        for scale in (0.55, 0.80, 1.0, 1.2):
            ranges = [45. * scale, 75. * scale, 105. * scale,
                      160. * scale, 0.]
            for side in (1., 3., 5., 12., 24., 80.):
                pair = min(range(len(sizes)), key=lambda i: abs(sizes[i] - side))
                for cap in (12., 60., 120.):
                    calculated = min(cap, ranges[pair]) if ranges[pair] > 0 else cap
                    self.assertTrue(math.isfinite(calculated))
                    self.assertGreaterEqual(calculated, 0)
                    self.assertLessEqual(calculated, cap)
            self.assertEqual(ranges[-1], 0.)

    def test_workflow_runs_native_and_game(self):
        ci = WORKFLOW.read_text()
        self.assertIn("test_cull_distance_cached_contract.py", ci)
        self.assertIn("CullDistanceProfile3D doctests", ci)
        self.assertIn("run_cull_distance_policy.gd", ci)


if __name__ == "__main__":
    unittest.main()
