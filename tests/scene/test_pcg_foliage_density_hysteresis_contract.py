"""Source-level contracts for Cgame temporal foliage density + real Albion integration.

Does not replace a native build and headless Godot tests in GitHub Actions.
"""
from pathlib import Path
import unittest
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[2]
MOD = ROOT / "modules/procedural_scatter"
GAME = ROOT / "game/scripts/client"


class TestPCGFoliageDensityHysteresisContract(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.header = (MOD / "pcg_foliage_scalability_3d.h").read_text()
        cls.native = (MOD / "pcg_foliage_scalability_3d.cpp").read_text()
        cls.script = (GAME / "scenery_density_lod.gd").read_text()
        cls.chunk = (GAME / "chunk_view.gd").read_text()
        cls.game_tests = (ROOT / "game/tests/test_pcg_foliage_scalability.gd").read_text()

    def test_native_reuses_existing_planner_and_atomic_validation(self):
        self.assertIn("PackedInt32Array plan_visible_counts_stable(", self.header)
        self.assertIn('D_METHOD("plan_visible_counts_stable",', self.native)
        impl = self.native.split(
            "PackedInt32Array PCGFoliageScalability3D::plan_visible_counts_stable(", 1
        )[1]
        self.assertIn("count != p_previous_counts.size()", impl)
        self.assertIn("count > MAX_CLUSTERS", impl)
        self.assertIn("p_deadband < 0 || p_deadband > 8", impl)
        self.assertIn("p_previous_counts[i] < -1 || p_previous_counts[i] > p_counts[i]", impl)
        self.assertIn("plan_visible_counts(", impl)
        self.assertIn("result.size() != count", impl)
        self.assertIn("Math::abs(previous - desired) <= p_deadband", impl)
        self.assertIn("result.set(i, previous)", impl)
        self.assertLess(impl.index("p_previous_counts[i] < -1"),
                        impl.index("plan_visible_counts("))
        self.assertLess(impl.index("result.size() != count"),
                        impl.index("result.set(i, previous)"))
        for unsafe in ("RenderingServer", "PhysicsServer", "get_tree()", "randf("):
            self.assertNotIn(unsafe, impl)

    def test_stable_fallback_preserves_stock_godot_and_tier_reset(self):
        self.assertIn("static func _stable_fallback(", self.script)
        self.assertIn("static func plan_visible_counts_stable(", self.script)
        self.assertIn('native.has_method("plan_visible_counts_stable")', self.script)
        self.assertIn('native.call("plan_visible_counts_stable",', self.script)
        self.assertIn("_stable_fallback(counts, distances, previous_counts", self.script)
        self.assertIn("deadband < 0 or deadband > 8", self.script)
        self.assertIn("absi(previous - desired) <= deadband", self.script)
        self.assertIn("const LAST_QUALITY_META", self.script)
        self.assertIn("int(node.get_meta(LAST_QUALITY_META, -1)) == quality", self.script)
        self.assertIn("else -1)", self.script)
        self.assertIn("node.set_meta(LAST_QUALITY_META, quality)", self.script)
        self.assertIn("current.visible_instance_count = visible", self.script)
        self.assertIn("if current.visible_instance_count != visible:", self.script)

    def test_real_albion_only_scales_cosmetic_multimesh(self):
        # Albion now uses screen-projected foliage density, with distance-based
        # update_instances() retained as a fallback for unsupported cameras.
        self.assertIn("SceneryDensityLod.update_instances_projected(_density_scenery_batches,", self.chunk)
        self.assertIn("camera, scenery_quality)", self.chunk)
        self.assertIn("static func update_instances_projected(", self.script)
        self.assertIn("static func _apply_projected_plan(", self.script)
        self.assertIn("absi(previous - desired) <= DENSITY_DEADBAND", self.script)
        self.assertIn("update_instances(instances, camera.global_position, quality, prefer_native)", self.script)
        self.assertIn("const DENSITY_LOD_INTERVAL := 0.6", self.chunk)
        self.assertIn("if density_scalable:", self.chunk)
        self.assertIn("file.begins_with(\"Flower\")", self.chunk)
        self.assertIn("file.begins_with(\"Grass\")", self.chunk)
        self.assertIn("file.begins_with(\"Fern\")", self.chunk)
        self.assertIn("file.begins_with(\"Petal\")", self.chunk)
        self.assertIn('node.get_meta("aa_density_scalable", false)', self.script)
        self.assertIn("if valid.size() == MAX_CLUSTERS:", self.script)

    def test_native_and_game_regressions(self):
        tests = (MOD / "tests/test_pcg_foliage_scalability_3d.h").read_text()
        self.assertIn("temporal count deadband prevents tiny density oscillation", tests)
        self.assertIn("stable planner validates all prior rows atomically", tests)
        self.assertIn("planned.size() == 4096", tests)
        self.assertIn("p_deadband", self.native)
        for phrase in (
            "native/fallback temporal foliage parity",
            "small camera motion cannot repeatedly pop one or two flowers",
            "switch to Ultra fully restores every original visual instance",
            "temporal density filtering never rebuilds the MultiMesh",
            "invalid late prior counts reject the entire density group",
        ):
            self.assertIn(phrase, self.game_tests)

    def test_documentation_and_ci(self):
        xml = ET.parse(MOD / "doc_classes/PCGFoliageScalability3D.xml").getroot()
        self.assertIn("plan_visible_counts_stable",
                      {m.get("name") for m in xml.findall("./methods/method")})
        self.assertIn("Temporal stability for runtime foliage density",
                      (MOD / "README.md").read_text())
        ci = (ROOT / ".github/workflows/native-scenery-geometry.yml").read_text()
        self.assertIn("test_pcg_foliage_density_hysteresis_contract.py", ci)
        self.assertIn("game/scripts/client/scenery_density_lod.gd", ci)
        self.assertIn("run_pcg_scenery_spacing.gd", ci)
        self.assertIn("*PCGFoliageScalability3D*", ci)


if __name__ == "__main__":
    unittest.main()
