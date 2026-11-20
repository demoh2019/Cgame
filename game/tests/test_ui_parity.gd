extends RefCounted
## UI, input, accessibility and localization parity features (see docs/ENGINE_PARITY_FX.md).

const UiSettings = preload("res://scripts/client/ui_settings.gd")
const UiLocalization = preload("res://scripts/client/ui_localization.gd")
const UiInputRebind = preload("res://scripts/client/ui_input_rebind.gd")
const UiColorblind = preload("res://scripts/client/ui_colorblind.gd")
const UiCaptions = preload("res://scripts/client/ui_captions.gd")
const UiGamepad = preload("res://scripts/client/ui_gamepad.gd")
const UiAccess = preload("res://scripts/client/ui_access.gd")
const UiTheme = preload("res://scripts/client/ui_theme.gd")
const PauseMenu = preload("res://scripts/client/ui_pause_menu.gd")

const TMP := "user://test_ui_parity.cfg"


func run(t) -> void:
	DirAccess.remove_absolute(TMP)
	UiSettings.path = TMP
	UiSettings.reset_defaults()
	UiSettings.load_all()

	t.current = "settings sanitize and persistence"
	t.eq(UiSettings.sanitize("ui_scale", 9.0), UiSettings.UI_SCALE_MAX, "scale clamped high")
	t.eq(UiSettings.sanitize("ui_scale", "abc"), 1.0, "bad scale falls back")
	t.eq(UiSettings.sanitize("colorblind", 99), 3, "filter index clamped")
	t.eq(UiSettings.sanitize("locale", "de"), "", "unsupported locale rejected")
	t.eq(UiSettings.sanitize("show_fps", 1), true, "bool coerced")
	UiSettings.set_value("colorblind", 2)
	UiSettings.set_value("reduce_shake", true)
	UiSettings.set_value("ui_scale", 1.25)
	var config := ConfigFile.new()
	t.eq(config.load(TMP), OK, "settings file written next to graphics prefs")
	t.eq(int(config.get_value("interface", "colorblind")), 2, "colorblind persisted")
	t.near(float(config.get_value("interface", "ui_scale")), 1.25, 0.001, "scale persisted")
	t.eq(UiSettings.get_value("colorblind"), 2, "colorblind readable")
	t.eq(UiSettings.shake_scale(), 0.0, "reduce shake zeroes trauma")
	UiSettings.set_value("reduce_shake", false)
	t.eq(UiSettings.shake_scale(), 1.0, "shake back to normal")
	UiSettings.set_value("reduce_flashes", true)
	t.eq(UiSettings.flash_scale(), 0.0, "reduce flashes zeroes flash scale")
	UiSettings.set_value("reduce_flashes", false)
	t.near(UiSettings.cycle_scale(1.0, 0.25), 1.25, 0.001, "scale step")
	t.near(UiSettings.cycle_scale(1.7, 0.25), UiSettings.UI_SCALE_MAX, 0.001, "scale step clamps")

	t.current = "hold or toggle latch"
	t.eq(UiSettings.resolve_hold(false, true, false, false), [true, false], "hold mode follows key")
	t.eq(UiSettings.resolve_hold(false, false, true, true), [false, false], "hold mode releases")
	var s := UiSettings.resolve_hold(true, true, false, false)
	t.eq(s, [true, true], "toggle latches on press edge")
	s = UiSettings.resolve_hold(true, true, true, s[1])
	t.eq(s[0], true, "held key does not re-toggle")
	s = UiSettings.resolve_hold(true, false, true, s[1])
	t.eq(s[0], true, "release keeps latch")
	s = UiSettings.resolve_hold(true, true, false, s[1])
	t.eq(s[0], false, "second press unlatches")

	t.current = "localization"
	t.eq(UiLocalization.missing_entries().size(), 0, "no blank translations")
	t.eq(UiLocalization.t("PLAY SOLO", "ru"), "ИГРАТЬ ОДНОМУ", "Russian lookup")
	t.eq(UiLocalization.t("PLAY SOLO", "en"), "PLAY SOLO", "English is the key")
	t.eq(UiLocalization.t("never seen string", "ru"), "never seen string", "unknown key falls back")
	UiLocalization.install()
	TranslationServer.set_locale("ru")
	t.eq(TranslationServer.translate("Join server"), "Подключиться к серверу", "TranslationServer serves Russian")
	TranslationServer.set_locale("en")
	t.eq(TranslationServer.translate("Join server"), "Join server", "English passes through")

	t.current = "key rebinding"
	UiInputRebind.install(TMP)
	t.eq(UiInputRebind.key_of("access_up"), KEY_W, "default up is W")
	t.eq(UiInputRebind.rebind("access_up", KEY_I, true, TMP), "", "free key rebinds without swap")
	t.eq(UiInputRebind.key_of("access_up"), KEY_I, "up is now I")
	t.eq(UiInputRebind.rebind("access_down", KEY_I, true, TMP), "access_up", "conflict swaps")
	t.eq(UiInputRebind.key_of("access_up"), KEY_S, "swapped action takes the old key")
	t.eq(UiInputRebind.conflict("access_left", KEY_D), "access_right", "conflict detection")
	UiInputRebind.rebind("access_sprint", KEY_Z, true, TMP)
	for action in ["access_up", "access_down", "access_sprint"]:
		InputMap.action_erase_events(action) # Simulate a fresh launch, then reload from disk.
	UiInputRebind.load_bindings(TMP)
	t.eq(UiInputRebind.key_of("access_sprint"), KEY_Z, "binding survives restart")
	t.eq(UiInputRebind.key_of("access_down"), KEY_I, "swapped binding survives restart")
	t.check(InputMap.action_get_events("access_pause").any(func(e): return e is InputEventJoypadButton), "pause has a pad button")
	UiInputRebind.reset(true, TMP)
	t.eq(UiInputRebind.key_of("access_down"), KEY_S, "reset restores defaults")
	var cfg2 := ConfigFile.new()
	cfg2.load(TMP)
	t.check(not cfg2.has_section_key("bindings", "access_down"), "defaults are not stored")
	t.eq(UiInputRebind.rebind("nope", KEY_Q, false), "", "unknown action ignored")

	t.current = "colorblind filters"
	t.eq(UiColorblind.rows(0)[0], Vector3(1, 0, 0), "mode 0 is identity")
	var prot := UiColorblind.transform(Color(1, 0, 0), 1)
	t.check(prot.r < 0.3 and prot.g < 0.2, "protanopia darkens pure red")
	var green := UiColorblind.transform(Color(0, 1, 0), 3)
	t.check(green.r < 0.05 and green.b > 0.5, "tritanopia moves green toward blue")
	for mode in [1, 2, 3]:
		var white := UiColorblind.transform(Color.WHITE, mode)
		t.near(white.r, 1.0, 0.03, "greys stay grey r mode %d" % mode)
		t.near(white.g, 1.0, 0.03, "greys stay grey g mode %d" % mode)
		t.near(white.b, 1.0, 0.03, "greys stay grey b mode %d" % mode)
	var mat := UiColorblind.make_material(2)
	t.eq(mat.get_shader_parameter("row0"), UiColorblind.MATRICES[2][0], "material carries the matrix")
	t.check(mat.shader.code.contains("hint_screen_texture"), "shader reads the screen")

	t.current = "closed captions"
	var fwd := Vector2(0, -1)
	var right := Vector2(1, 0)
	t.eq(UiCaptions.direction_word(Vector2(0, -10), fwd, right), "ahead", "ahead")
	t.eq(UiCaptions.direction_word(Vector2(0, 10), fwd, right), "behind", "behind")
	t.eq(UiCaptions.direction_word(Vector2(-10, 0), fwd, right), "left", "left")
	t.eq(UiCaptions.direction_word(Vector2(10, 0), fwd, right), "right", "right")
	t.eq(UiCaptions.direction_word(Vector2(7, -7), fwd, right), "ahead-right", "diagonal")
	t.eq(UiCaptions.direction_word(Vector2(1, 1), fwd, right), "nearby", "close sound")
	var shot := UiCaptions.caption_for({"type": "attack", "ranged": true, "x": -24.0, "z": 0.0}, 1, Vector2.ZERO, fwd, right, "en")
	t.eq(shot, "[Gunshot, left, 24 m]", "gunshot caption with side and distance")
	var shot_ru := UiCaptions.caption_for({"type": "attack", "ranged": true, "x": -24.0, "z": 0.0}, 1, Vector2.ZERO, fwd, right, "ru")
	t.eq(shot_ru, "[Выстрел, слева, 24 m]", "Russian caption")
	t.eq(UiCaptions.caption_for({"type": "attack", "x": 500.0, "z": 0.0}, 1, Vector2.ZERO, fwd, right, "en"), "", "out of earshot")
	t.eq(UiCaptions.caption_for({"type": "gathered"}, 1, Vector2.ZERO, fwd, right, "en"), "", "silent events skipped")
	t.eq(UiCaptions.caption_for({"type": "death", "peer": 2}, 1, Vector2.ZERO, fwd, right, "en"), "", "other deaths skipped")
	t.eq(UiCaptions.caption_for({"type": "lightning_struck", "x": 0.0, "z": -30.0}, 1, Vector2.ZERO, fwd, right, "en"), "[Thunder crack, ahead, 30 m]", "thunder")
	var rows := UiCaptions.push_line([], "[A]", 0.0)
	rows = UiCaptions.push_line(rows, "[A]", 0.3)
	t.eq(rows.size(), 1, "duplicate within window merges")
	for i in 6:
		rows = UiCaptions.push_line(rows, "[B%d]" % i, 5.0 + i)
	t.eq(rows.size(), 4, "row limit")
	var view := UiCaptions.CaptionView.new()
	view.add_caption("[Test]")
	t.eq(view.lines.size(), 1, "caption view stores a line")
	view.free()

	t.current = "gamepad prompts"
	var key_ev := InputEventKey.new()
	var pad_ev := InputEventJoypadButton.new()
	UiGamepad.last_device = UiGamepad.Device.KEYBOARD
	t.eq(UiGamepad.observe(key_ev), false, "key while on keyboard is no change")
	t.eq(UiGamepad.observe(pad_ev), true, "pad press switches device")
	t.eq(UiGamepad.last_device, UiGamepad.Device.GAMEPAD, "device is gamepad")
	var drift := InputEventJoypadMotion.new()
	drift.axis_value = 0.1
	t.eq(UiGamepad.device_of(drift), -1, "stick drift ignored")
	t.eq(UiGamepad.observe(key_ev), true, "key press switches back")
	t.eq(UiGamepad.glyph(JOY_BUTTON_A, false), "A", "xbox glyph")
	t.eq(UiGamepad.glyph(JOY_BUTTON_A, true), "Cross", "playstation glyph")
	t.check(UiGamepad.is_playstation("PS5 Controller"), "PS name detected")
	t.check(not UiGamepad.is_playstation("Xbox Series Controller"), "xbox name not PS")
	t.check(UiGamepad.prompt_line(UiGamepad.Device.GAMEPAD, false, "en").contains("(A) Interact"), "pad prompt line")
	t.check(UiGamepad.prompt_line(UiGamepad.Device.KEYBOARD, false, "en").contains("[E] Interact"), "keyboard prompt line")
	var emulated := UiGamepad.key_event_for(JOY_BUTTON_Y, true)
	t.eq(emulated.keycode, KEY_I, "Y opens the inventory via I")
	t.check(UiGamepad.key_event_for(JOY_BUTTON_MISC1, true) == null, "unmapped button ignored")

	t.current = "high contrast theme"
	var over: Theme = UiTheme.get_theme()
	var before_outline := over.get_constant("outline_size", "Label")
	UiAccess.apply_high_contrast(true)
	t.eq(over.get_color("font_color", "Label"), Color.WHITE, "text is pure white")
	t.eq(over.get_constant("outline_size", "Label"), 8, "outline thickened")
	t.eq(UiTheme.paper_theme().get_color("font_color", "Label"), Color.BLACK, "parchment ink is black")
	UiAccess.apply_high_contrast(false)
	t.eq(over.get_constant("outline_size", "Label"), before_outline, "high contrast restores outline")
	t.check(not UiAccess.high_contrast_active(), "restored")

	t.current = "settings menu builds"
	UiSettings.set_value("show_fps", false)
	var menu := PauseMenu.new()
	t.eq(menu.visible, false, "menu starts hidden")
	t.eq(menu._tabs.get_tab_count(), 3, "three tabs")
	t.eq(menu._bind_buttons.size(), UiInputRebind.ACTIONS.size(), "a button per rebindable action")
	menu._capturing = "access_fps"
	var press := InputEventKey.new()
	press.physical_keycode = KEY_F6
	press.pressed = true
	t.check(menu.handle_capture(press), "capture consumes the key")
	t.eq(UiInputRebind.key_of("access_fps"), KEY_F6, "captured key bound")
	UiInputRebind.reset(false)
	menu.free()

	DirAccess.remove_absolute(TMP)
	UiSettings.path = UiSettings.DEFAULT_PATH
	UiSettings.reset_defaults()
