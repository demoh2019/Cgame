"""Verify source contracts for source-oriented camera feedback.

Static checks are useful before compiling but do not replace headless Godot,
native doctests or on-device render testing.
"""
from pathlib import Path
import unittest
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[2]
CAMERA = ROOT / "scene/3d"
GAME = ROOT / "game/scripts/client"
TESTS = ROOT / "game/tests"
WORKFLOW = ROOT / ".github/workflows/native-camera-directional-impulses.yml"


class TestDirectionalCameraImpulseContract(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.header = (CAMERA / "camera_3d.h").read_text()
        cls.native = (CAMERA / "camera_3d.cpp").read_text()
        cls.feedback = (GAME / "combat_camera_feedback.gd").read_text()
        cls.game_tests = (TESTS / "test_combat_camera_feedback.gd").read_text()

    def test_classdb_api_and_state(self):
        self.assertIn("void add_directional_spatial_trauma(", self.header)
        self.assertIn("Vector3 get_shake_direction_impulse() const", self.header)
        self.assertIn("Vector3 shake_direction_impulse;", self.header)
        self.assertIn("void Camera3D::add_directional_spatial_trauma(", self.native)
        self.assertIn('D_METHOD("add_directional_spatial_trauma",', self.native)
        self.assertIn('D_METHOD("get_shake_direction_impulse")', self.native)

    def test_safe_source_orientation_and_authority_isolation(self):
        fn = self.native.split(
            "void Camera3D::add_directional_spatial_trauma(", 1
        )[1].split("void Camera3D::set_trauma(", 1)[0]
        for fragment in (
            "Math::is_finite(p_amount)",
            "CameraShake::spatial_falloff(p_listener, p_source, p_inner_radius, p_outer_radius)",
            "MIN(p_amount, real_t(1.0)) * falloff",
            "p_source - p_listener",
            "delta.is_finite()",
            "get_global_transform().basis.orthonormalized().xform_inv(delta.normalized())",
            "local_direction.is_finite()",
            ".limit_length(real_t(1.0))",
            "add_trauma(amount);",
        ):
            self.assertIn(fragment, fn)
        for forbidden in ("set_position(", "set_global_position(", "set_transform(",
                          "set_global_transform(", "RenderingServer", "PhysicsServer"):
            self.assertNotIn(forbidden, fn)

    def test_impulse_decay_limit_reset_and_processing(self):
        advance = self.native.split("void Camera3D::_advance_shake(", 1)[1].split(
            "void Camera3D::add_trauma(", 1
        )[0]
        self.assertIn("shake_direction_impulse.move_toward(Vector3(), step)", advance)
        self.assertIn("const Vector3 local = shake.get_translation_unit() * intensity + shake_direction_impulse", advance)
        self.assertIn("CLAMP(local.x", advance)
        self.assertIn("CLAMP(local.y", advance)
        self.assertIn("CLAMP(local.z", advance)
        self.assertIn("* shake_max_offset", advance)
        reset = self.native.split("void Camera3D::set_trauma(", 1)[1].split(
            "real_t Camera3D::get_trauma(", 1
        )[0]
        self.assertIn("shake_direction_impulse = Vector3();", reset)
        process = self.native.split("void Camera3D::_update_process_mode(", 1)[1].split(
            "void Camera3D::_notification(", 1
        )[0]
        self.assertIn("shake_direction_impulse != Vector3()", process)

    def test_real_albion_impact_types_and_fallback(self):
        for kind in ("hit_zombie", "knockback", "barricade_broken"):
            line = next(line for line in self.feedback.splitlines()
                        if line.strip().startswith(f'"{kind}":'))
            self.assertIn('"directional": true', line)
        for kind in ("flash_thrown", "zombie_died"):
            line = next(line for line in self.feedback.splitlines()
                        if line.strip().startswith(f'"{kind}":'))
            self.assertNotIn('"directional": true', line)
        self.assertIn('camera.has_method("add_directional_spatial_trauma")', self.feedback)
        self.assertIn('camera.call("add_directional_spatial_trauma", source, listener, amount, inner, outer)', self.feedback)
        self.assertIn('elif camera.has_method("add_spatial_trauma")', self.feedback)
        self.assertIn('camera.call("add_spatial_trauma", source, listener, amount, inner, outer)', self.feedback)
        self.assertIn('shake_scale <= 0.0', self.feedback)
        self.assertIn("UiSettings.shake_scale()", (GAME / "online_main.gd").read_text())

    def test_real_game_and_native_regression(self):
        for marker in (
            "directional hit preserves the original spatial trauma strength",
            "the camera kick points toward the world impact",
            "nondirectional flash keeps existing trauma semantics",
            "barricade break points the camera toward the destruction",
            "reduce-screen-shake setting disables directional and radial impulses",
        ):
            self.assertIn(marker, self.game_tests)
        tests = (ROOT / "tests/scene/test_camera_shake.cpp").read_text()
        self.assertIn("Directional spatial impacts are bounded and leave scene transforms unchanged", tests)
        self.assertIn("Opposite impact cancels", tests)
        self.assertIn("camera->get_global_transform().is_equal_approx(base)", tests)
        self.assertIn("camera->get_shake_direction_impulse() == Vector3()", tests)

    def test_reference_xml_and_ci(self):
        doc = ET.parse(ROOT / "doc/classes/Camera3D.xml").getroot()
        names = {m.get("name") for m in doc.findall("./methods/method")}
        self.assertIn("add_directional_spatial_trauma", names)
        self.assertIn("get_shake_direction_impulse", names)
        workflow = WORKFLOW.read_text()
        self.assertIn("test_directional_camera_impulse_contract.py", workflow)
        self.assertIn("--test-case=\"*[CameraShake]*\"", workflow)
        self.assertIn("run_one.gd -- test_combat_camera_feedback", workflow)


if __name__ == "__main__":
    unittest.main()
