"""Source-level contract for combined native AI passive scan LOD planning.

These tests inspect both the native engine and Albion After integration.
They do not replace C++ compilation, headless Godot tests or benchmarking.
"""
from pathlib import Path
import unittest
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[2]
ENGINE = ROOT / "modules/behavior_tree"
GAME = ROOT / "game/scripts/shared/zombie.gd"
GAME_TEST = ROOT / "game/tests/test_zombie_ai.gd"


class TestAIPassiveScanPlanContract(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.header = (ENGINE / "ai_simulation_lod_2d.h").read_text()
        cls.native = (ENGINE / "ai_simulation_lod_2d.cpp").read_text()
        cls.zombie = GAME.read_text()
        cls.game_test = GAME_TEST.read_text()

    def test_reusable_native_method_and_single_classdb_boundary(self):
        self.assertIn("Vector2 plan_passive_scan(", self.header)
        self.assertIn("#include \"core/math/vector2.h\"", self.header)
        self.assertIn("Vector2 AISimulationLOD2D::plan_passive_scan(", self.native)
        self.assertIn('D_METHOD("plan_passive_scan",', self.native)
        self.assertIn("DEFVAL(false)", self.native)
        self.assertIn("bool p_already_staggered, bool p_urgent", self.header)
        self.assertIn("bool p_already_staggered, bool p_urgent", self.native)

    def test_plan_reuses_scalar_scheduling_without_authority_or_rng(self):
        fn = self.native.split("Vector2 AISimulationLOD2D::plan_passive_scan(", 1)[1].split(
            "real_t AISimulationLOD2D::get_staggered_interval(", 1
        )[0]
        for statement in (
            "get_interval(p_distance, p_near_distance, p_far_distance, p_urgent)",
            "!p_already_staggered && p_distance > p_near_distance && !p_urgent",
            "get_staggered_interval(p_agent_id,",
            "get_hysteretic_interval(p_distance, p_near_distance,",
            "return Vector2(base, phased);",
            "return Vector2(nominal, nominal);",
        ):
            self.assertIn(statement, fn)
        for prohibited in ("SceneTree", "RandomNumberGenerator", "RenderingServer",
                           "MultiplayerAPI", "PhysicsServer"):
            self.assertNotIn(prohibited, fn)

    def test_game_uses_one_call_and_retains_exact_legacy_branch(self):
        code = self.zombie.split('if lod.has_method("plan_passive_scan"):', 1)[1].split(
            "elif target_id != -1:", 1
        )[0]
        self.assertIn("var plan: Vector2 = lod.plan_passive_scan(", code)
        self.assertIn("_ai_lod_previous_interval = plan.x", code)
        self.assertIn("think_timer = plan.y", code)
        self.assertIn("if not _ai_lod_staggered and nearest_viewer > near_range:", code)
        self.assertIn("_ai_lod_staggered = true", code)
        self.assertIn("else:", code)
        self.assertIn("lod.get_interval(", code)
        self.assertIn("lod.get_staggered_interval(", code)
        self.assertIn("lod.get_hysteretic_interval(", code)
        self.assertIn("target_id == -1 and (state == State.IDLE or state == State.WANDER)", self.zombie)
        self.assertIn("elif target_id != -1:", self.zombie)
        self.assertIn("_ai_lod_previous_interval = 0.0", self.zombie)

    def test_real_zombie_and_native_regressions_are_wired(self):
        for needle in (
            "real infected uses one-call scheduled startup scan delay",
            "real infected remembers nominal tier, not staggered delay",
            "server flags one-shot stagger after first remote scan",
            "subsequent remote scans use full LOD period",
            "survivor reaching pursuit range immediately restores fast scanning",
            "urgent work bypasses even the one-time startup stagger",
        ):
            self.assertIn(needle, self.game_test)
        tests = (ENGINE / "tests/test_ai_simulation_lod_2d.h").read_text()
        self.assertIn("combined passive scan plan matches scalar LOD at all tiers", tests)
        self.assertIn("combined planning honors urgent scans and configured intervals", tests)

    def test_xml_api_and_workflow_are_updated(self):
        doc = ET.parse(ENGINE / "doc_classes/AISimulationLOD2D.xml").getroot()
        methods = {m.get("name") for m in doc.findall("./methods/method")}
        self.assertIn("plan_passive_scan", methods)
        ci = (ROOT / ".github/workflows/native-ai-simulation-lod.yml").read_text()
        self.assertIn("test_ai_passive_scan_plan_contract.py", ci)
        self.assertIn("--test-case=\"*[AISimulationLOD2D]*\"", ci)
        self.assertIn("res://tests/run_all.gd", ci)


if __name__ == "__main__":
    unittest.main()
