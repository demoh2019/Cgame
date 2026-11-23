"""Source contracts for Albion After UI (native runtime tests still required)."""

import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CLIENT = ROOT / "game" / "scripts" / "client"


class AlbionSettingsMenuContract(unittest.TestCase):
    def test_five_scrollable_categories_and_real_mixer(self):
        pause = (CLIENT / "ui_pause_menu.gd").read_text()
        for code in (
            "_build_gameplay()",
            "_build_graphics()",
            "_build_audio()",
            "_build_controls()",
            "_build_accessibility()",
        ):
            self.assertIn(code, pause)
        self.assertIn("var scroll := ScrollContainer.new()", pause)
        self.assertIn("signal graphics_selected(index: int)", pause)
        self.assertIn("graphics_selected.emit(_graphics_picker.get_item_id(index))", pause)
        self.assertIn("func set_graphics_choice(level: int, auto_enabled: bool)", pause)
        self.assertIn("AudioMix.SLIDERS", pause)
        self.assertIn("AudioMix.set_volume(bus, percent / 100.0, false)", pause)
        self.assertIn("slider.value_changed.connect(_set_audio_volume.bind(bus))", pause)
        self.assertIn("slider.drag_ended.connect(", pause)
        self.assertIn("AudioMix.reset_volumes()", pause)
        self.assertIn("slider.set_value_no_signal(", pause)
        self.assertIn("var _audio_value_labels: Dictionary", pause)
        self.assertIn("percent_label.text =", pause)
        self.assertIn("_audio_value_labels[bus] = percent_label", pause)
        self.assertIn("Control.FOCUS_ALL", pause)
        self.assertIn("func _reset_display_settings()", pause)
        self.assertIn("DisplaySettings.reset()", pause)
        self.assertIn("_refresh_display_pickers()", pause)
        self.assertIn("UiInputRebind.rebind(", pause)
        self.assertIn("UiSettings.set_value(", pause)

    def test_real_online_scene_uses_shared_graphics_path_and_title_settings(self):
        online = (CLIENT / "online_main.gd").read_text()
        self.assertIn('_access.menu.connect("graphics_selected", Callable(self, "_apply_graphics_selection"))', online)
        self.assertIn("func _apply_graphics_selection(index: int) -> void:", online)
        shared = online.split("func _apply_graphics_selection(", 1)[1].split("func _set_auto_graphics(", 1)[0]
        self.assertIn("GraphicsQuality.set_level(", shared)
        self.assertIn("_adaptive_resolution.configure(", shared)
        self.assertIn("GraphicsQuality.apply(get_viewport(), atmosphere, _grade_material, water,", shared)
        self.assertIn("_quality_picker.select(selected)", shared)
        self.assertIn('_access.menu.call("set_graphics_choice", GraphicsQuality.level(), _auto_graphics)', shared)
        self.assertIn('settings_button.text = "Settings"', online)
        self.assertIn("_access.menu.open()", online)
        self.assertIn("_apply_graphics_selection(quality_picker.get_item_id(index))", online)
        self.assertIn("_apply_graphics_selection((GraphicsQuality.level() + 1)", online)

    def test_persisted_fps_vsync_fullscreen_real_display_api(self):
        display = (CLIENT / "ui_display_settings.gd").read_text()
        pause = (CLIENT / "ui_pause_menu.gd").read_text()
        layer = (CLIENT / "ui_accessibility_layer.gd").read_text()
        tests = (ROOT / "game/tests/test_ui_parity.gd").read_text()
        for needle in (
            '"window_mode": 0',
            '"vsync": 1',
            '"fps_limit": 0',
            'Engine.max_fps = get_value("fps_limit")',
            'window.mode = mode',
            'DisplayServer.window_set_vsync_mode(vsync)',
            'DisplayServer.get_name() == "headless"',
            'config.load(path) # Keep quality, Auto',
            'config.save(path)',
        ):
            self.assertIn(needle, display)
        self.assertIn('DisplaySettings.load_all()', pause)
        self.assertIn('DisplaySettings.apply(get_window() if is_inside_tree() else null)', pause)
        self.assertIn('DisplaySettings.apply(get_window())', layer)
        for label in ('"Window mode"', '"Vertical sync"', '"FPS limit"'):
            self.assertIn(label, pause)
        self.assertIn('frame cap survives restart', tests)
        self.assertIn('static func reset(persist: bool = true)', display)
        self.assertIn('display reset never clears interface preferences', tests)
        self.assertIn('V-Sync survives restart', tests)

    def test_audio_persistence_and_translation_have_regressions(self):
        mix = (CLIENT / "audio_mix.gd").read_text()
        locale = (CLIENT / "ui_localization.gd").read_text()
        tests = (ROOT / "game/tests/test_ui_parity.gd").read_text()
        self.assertIn("static var path := PATH", mix)
        self.assertIn("config.load(path)", mix)
        self.assertIn("config.save(path)", mix)
        self.assertIn("if not SLIDERS.has(bus):", mix)
        self.assertIn("linear if is_finite(linear) else 1.0", mix)
        self.assertIn("static func reset_volumes(", mix)
        self.assertIn("var loaded: bool = config.load(path) == OK", mix)
        self.assertIn("if loaded else 1.0", mix)
        self.assertIn('"Graphics": "Графика"', locale)
        self.assertIn('"Audio": "Звук"', locale)
        self.assertIn("five working Settings tabs", tests)
        self.assertIn("SFX persisted", tests)
        self.assertIn("graphics tab sends auto mode", tests)


if __name__ == "__main__":
    unittest.main()
