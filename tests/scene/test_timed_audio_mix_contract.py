"""Cgame timed Control Bus Mix and live Albion combat audio source contracts.

These source checks are not a substitute for compiling/running native Godot.
"""
from pathlib import Path
import unittest
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[2]
MOD = ROOT / "modules/gameplay_fx"
GAME = ROOT / "game/scripts/client"
TESTS = ROOT / "game/tests"


class TestTimedAudioMixContract(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.header = (MOD / "audio_mix_snapshot_controller.h").read_text()
        cls.cpp = (MOD / "audio_mix_snapshot_controller.cpp").read_text()
        cls.portable = (GAME / "audio_mix_snapshots.gd").read_text()
        cls.audio = (GAME / "audio.gd").read_text()
        cls.native_tests = (MOD / "tests/test_audio_mix_snapshot_controller.h").read_text()
        cls.game_tests = (TESTS / "test_audio_timed_mix.gd").read_text()

    def test_native_public_contract(self):
        self.assertIn("static constexpr double MAX_HOLD_SECONDS = 120.0", self.header)
        self.assertIn("bool activate_timed_mix(", self.header)
        self.assertIn("double get_mix_remaining_seconds(", self.header)
        self.assertIn("double remaining_seconds = -1.0", self.header)
        self.assertIn("double release_seconds = 1.0", self.header)
        self.assertIn("bool AudioMixSnapshotController::activate_timed_mix(", self.cpp)
        self.assertIn('D_METHOD("activate_timed_mix",', self.cpp)
        self.assertIn('D_METHOD("get_mix_remaining_seconds",', self.cpp)

    def test_atomic_input_validation_and_rearm(self):
        fn = self.cpp.split(
            "bool AudioMixSnapshotController::activate_timed_mix(", 1
        )[1].split("bool AudioMixSnapshotController::deactivate_mix(", 1)[0]
        for part in (
            "Math::is_finite(p_hold_seconds)",
            "p_hold_seconds > MAX_HOLD_SECONDS",
            "Math::is_finite(p_release_seconds)",
            "p_release_seconds > MAX_FADE_SECONDS",
            "activate_mix(p_source, p_bus_offsets_db, p_attack_seconds)",
            "mix.remaining_seconds = p_hold_seconds",
            "mix.release_seconds = p_release_seconds",
        ):
            self.assertIn(part, fn)
        self.assertLess(fn.index("p_release_seconds > MAX_FADE_SECONDS"),
                        fn.index("activate_mix(p_source"))
        self.assertIn("mix.remaining_seconds = -1.0", self.cpp)
        self.assertNotIn("AudioServer", fn)
        self.assertNotIn("RenderingServer", fn)

    def test_precise_expiry_and_release(self):
        tick = self.cpp.split(
            "void AudioMixSnapshotController::tick(", 1
        )[1].split("double AudioMixSnapshotController::get_bus_offset_db(", 1)[0]
        for part in (
            "!Math::is_finite(p_delta)",
            "if (step_seconds >= mix.remaining_seconds)",
            "advance(mix, mix.remaining_seconds)",
            "step_seconds -= mix.remaining_seconds",
            "mix.remaining_seconds = -1.0",
            "mix.target = 0.0",
            "mix.fade_seconds = mix.release_seconds",
            "advance(mix, step_seconds)",
            "mixes.remove_at(i)",
        ):
            self.assertIn(part, tick)
        self.assertLess(tick.index("advance(mix, mix.remaining_seconds)"),
                        tick.index("advance(mix, step_seconds)"))

    def test_portable_parity_and_old_binary_mix_composition(self):
        for part in (
            "static func activate_timed_mix(",
            "static func mix_remaining_seconds(",
            "MAX_HOLD_SECONDS := 120.0",
            "if not activate_mix(mixes, source, offsets, attack_seconds):",
            'state["remaining"] = hold_seconds',
            'state["release"] = release_seconds',
            "static func _advance_weight(",
            "_advance_weight(profile, remaining)",
            "step_seconds -= remaining",
            'profile["target"] = 0.0',
            '_advance_weight(profile, step_seconds)',
        ):
            self.assertIn(part, self.portable)
        self.assertIn('_native_mix_snapshots.has_method("activate_timed_mix")', self.audio)
        self.assertIn('AudioMixSnapshots.activate_timed_mix(_script_mix_snapshots, source,', self.audio)
        self.assertIn("native_offset + AudioMixSnapshots.bus_offset_db(_script_mix_snapshots, bus)", self.audio)
        self.assertIn('AudioMixSnapshots.tick(_script_mix_snapshots, delta)', self.audio)

    def test_real_combat_and_regression_coverage(self):
        self.assertIn('func mark_combat() -> void:', self.audio)
        self.assertIn('_activate_timed_mix_snapshot("Combat.Focus",', self.audio)
        self.assertIn('{"Ambience": -3.0, "Music": -1.0}, 0.15, COMBAT_SECONDS, 1.5', self.audio)
        self.assertIn('"Combat.Focus"', self.game_tests)
        for part in (
            "expiry within a large frame uses only its post-hold release time",
            "retrigger preserves current mix strength",
            "the actual game sound node activates the combat bus profile",
            "timed combat mix automatically releases without extra events",
            "native/portable mix offsets remain identical after retrigger",
        ):
            self.assertIn(part, self.game_tests)
        for test in (
            "timed bus mix respects attack hold release and exact frame boundary",
            "timed retrigger preserves active level and independent mixes",
            "timed invalid durations leave live profiles untouched",
        ):
            self.assertIn(test, self.native_tests)
        self.assertIn('"res://tests/test_audio_timed_mix.gd"', (TESTS / "run_all.gd").read_text())

    def test_documentation_and_ci(self):
        doc = ET.parse(MOD / "doc_classes/AudioMixSnapshotController.xml").getroot()
        methods = {m.get("name") for m in doc.findall("./methods/method")}
        self.assertIn("activate_timed_mix", methods)
        self.assertIn("get_mix_remaining_seconds", methods)
        self.assertIn("Timed Control Bus Mixes", (MOD / "AUDIO_MIX_SNAPSHOTS.md").read_text())
        ci = (ROOT / ".github/workflows/native-timed-audio-mixes.yml").read_text()
        self.assertIn("test_timed_audio_mix_contract.py", ci)
        self.assertIn("*AudioMixSnapshot*", ci)
        self.assertIn("run_one.gd -- test_audio_timed_mix", ci)


if __name__ == "__main__":
    unittest.main()
