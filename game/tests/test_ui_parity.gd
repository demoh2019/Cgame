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
const AudioMix = preload("res://scripts/client/audio_mix.gd")
const DisplaySettings = preload("res://scripts/client/ui_display_settings.gd")
const GraphicsQuality = preload("res://scripts/client/graphics_quality.gd")

const TMP := "user://test_ui_parity.cfg"


func run(t) -> void:
	_streaming_line(t)
	DirAccess.remove_absolute(TMP)
	UiSettings.path = TMP
	UiSettings.reset_defaults()
	UiSettings.load_all()

	t.current = "settings sanitize and persistence"
	t.eq(UiSettings.sanitize("ui_scale", 9.0), UiSettings.UI_SCALE_MAX, "scale clamped high")
	t.eq(UiSettings.sanitize("ui_scale", "abc"), 1.0, "bad scale falls back")
	t.eq(UiSettings.sanitize("colorblind", 99), 3, "filter index clamped")
	t.eq(UiSettings.sanitize("colorblind", NAN), 0, "NaN colorblind index uses default")
	t.eq(UiSettings.sanitize("caption_size", INF), 1, "infinite caption size uses default")
	t.eq(UiSettings.sanitize("colorblind", 1e100), 3,
		"huge finite UI index clamps before integer conversion")
	t.eq(UiSettings.sanitize("reduce_flashes", "false"), false,
		"malformed boolean string never enables a visual effect")
	t.eq(UiSettings.sanitize("toggle_sprint", "true"), false,
		"corrupt text cannot silently switch hold/toggle input")
	t.eq(UiSettings.sanitize("captions", 1), true,
		"legacy numeric boolean remains compatible")
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
	var swapped_codes: Dictionary = UiInputRebind.resolved_saved({
		"access_up": KEY_S, "access_down": KEY_W})
	t.eq(swapped_codes["access_up"], KEY_S,
		"persisted key swap respects first action")
	t.eq(swapped_codes["access_down"], KEY_W,
		"persisted key swap respects second action")
	var single_override: Dictionary = UiInputRebind.resolved_saved({"access_up": KEY_S})
	t.eq(single_override["access_down"], KEY_W,
		"binding to another action's default swaps that action safely")
	var malformed_codes: Dictionary = UiInputRebind.resolved_saved({
		"access_up": NAN, "access_down": -5,
		"access_left": "bad", "access_right": 999999999999})
	for entry in UiInputRebind.ACTIONS:
		t.eq(malformed_codes[entry[0]], entry[2],
			"corrupt saved keys leave a valid default for " + str(entry[0]))
	var unique: Dictionary = UiInputRebind.resolved_saved({
		"access_up": KEY_T, "access_down": KEY_T, "access_left": KEY_S})
	t.eq(unique.values().size(), UiInputRebind.ACTIONS.size(),
		"all actions remain bound after conflicting overrides")
	var occupied: Dictionary = {}
	for binding in unique.values():
		t.check(not occupied.has(binding), "saved key layout has no duplicate actions")
		occupied[binding] = true
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
	t.eq(UiInputRebind.rebind("access_up", -1, false), "",
		"invalid physical key codes are ignored")
	t.eq(UiInputRebind.rebind("access_up", 999999999, false), "",
		"oversized forged key codes cannot be saved")

	t.current = "colorblind filters"
	t.eq(UiColorblind.rows(0)[0], Vector3(1, 0, 0), "mode 0 is identity")
	var prot := UiColorblind.transform(Color(1, 0, 0), 1)
	t.check(prot.r < 0.3 and prot.g < 0.2, "protanopia darkens pure red")
	var green := UiColorblind.transform(Color(0, 1, 0), 3)
	t.check(green.r < 0.05 and green.b > 0.5, "tritanopia moves green toward blue")
	for mode in [1, 2, 3]:
		var white := UiColorblind.transform(Color.WHITE, mode)
		t.near(white.r, 1.0, 0.03, "grays stay gray r mode %d" % mode)
		t.near(white.g, 1.0, 0.03, "grays stay gray g mode %d" % mode)
		t.near(white.b, 1.0, 0.03, "grays stay gray b mode %d" % mode)
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

	t.current = "settings menu builds: graphics, audio, gameplay, keys and accessibility"
	UiSettings.set_value("show_fps", false)
	var prior_display_path: String = DisplaySettings.path
	var prior_fps: int = Engine.max_fps
	DisplaySettings.path = TMP
	DisplaySettings.load_all()
	t.eq(DisplaySettings.sanitize("fps_limit", 77), 0, "unsupported frame cap rejected")
	t.eq(DisplaySettings.sanitize("fps_limit", NAN), 0, "malformed frame limit fails to default")
	t.eq(DisplaySettings.sanitize("fps_limit", 240), 240, "legal frame cap accepted")
	t.eq(DisplaySettings.sanitize("window_mode", 999), 1, "fullscreen mode index clamped")
	t.eq(DisplaySettings.sanitize("window_mode", "fullscreen"), 0, "invalid window mode ignored")
	t.eq(DisplaySettings.sanitize("vsync", 999), 1, "sync choice clamped")
	var prior_audio_path: String = AudioMix.path
	AudioMix.path = "user://test_albion_settings_audio.cfg"
	DirAccess.remove_absolute(AudioMix.path)
	AudioMix.reset_volumes(false)
	var menu := PauseMenu.new()
	t.eq(menu.visible, false, "menu starts hidden")
	t.eq(menu._tabs.get_tab_count(), 5, "five working Settings tabs")
	t.eq(menu._tabs.get_tab_bar().focus_mode, Control.FOCUS_ALL,
		"tabs allow keyboard and gamepad focus")
	t.eq(menu._audio_value_labels.size(), AudioMix.SLIDERS.size(),
		"all five sound sliders have visible numerical percentages")
	t.eq(menu._bind_buttons.size(), UiInputRebind.ACTIONS.size(), "a button per rebindable action")
	t.eq(menu._audio_sliders.size(), AudioMix.SLIDERS.size(), "one slider per real AudioMix bus")
	t.eq(menu._display_pickers.size(), 3, "graphics page exposes window, vsync and FPS")
	var fps_picker: OptionButton = menu._display_pickers["fps_limit"]
	fps_picker.item_selected.emit(3) # Unlimited, 30, 60, 120.
	t.eq(DisplaySettings.get_value("fps_limit"), 120, "FPS picker updates display preferences")
	t.eq(Engine.max_fps, 120, "FPS picker changes real engine frame cap")
	var window_picker: OptionButton = menu._display_pickers["window_mode"]
	window_picker.item_selected.emit(1)
	t.eq(DisplaySettings.get_value("window_mode"), 1, "fullscreen option saved")
	var sync_picker: OptionButton = menu._display_pickers["vsync"]
	sync_picker.item_selected.emit(0)
	t.eq(DisplaySettings.get_value("vsync"), 0, "V-Sync off option saved")
	var video_cfg := ConfigFile.new()
	t.eq(video_cfg.load(TMP), OK, "display controls persist to shared graphics config")
	t.eq(video_cfg.get_value("display", "fps_limit"), 120, "frame cap survives restart")
	t.eq(video_cfg.get_value("display", "window_mode"), 1, "window mode survives restart")
	t.eq(video_cfg.get_value("display", "vsync"), 0, "V-Sync survives restart")
	t.check(video_cfg.has_section("interface"), "display writes preserve existing interface settings")
	menu._reset_display_settings()
	t.eq(DisplaySettings.get_value("fps_limit"), 0, "reset disables FPS cap")
	t.eq(Engine.max_fps, 0, "reset updates active FPS cap immediately")
	t.eq(fps_picker.get_item_id(fps_picker.selected), 0, "FPS picker refreshes after reset")
	t.eq(window_picker.get_item_id(window_picker.selected), 0, "window picker resets")
	t.eq(sync_picker.get_item_id(sync_picker.selected), 1, "V-Sync picker resets to enabled")
	t.eq(DisplaySettings.get_value("vsync"), 1, "reset restores enabled V-Sync")
	video_cfg.load(TMP)
	t.eq(video_cfg.get_value("display", "fps_limit"), 0, "reset persists the default FPS")
	t.check(video_cfg.has_section("interface"), "display reset never clears interface preferences")
	for bus in AudioMix.SLIDERS:
		var slider: HSlider = menu._audio_sliders[bus]
		t.eq(slider.min_value, 0.0, "audio controls support silence")
		t.eq(slider.max_value, 100.0, "audio controls support full volume")
		t.eq(slider.step, 5.0, "audio controls snap to five percent")
	t.eq(PauseMenu.graphics_selection(-10, false), 0, "graphics preset bounds negative values")
	t.eq(PauseMenu.graphics_selection(999, false), 3, "graphics preset bounds oversized values")
	t.eq(PauseMenu.graphics_selection(0, true), GraphicsQuality.NAMES.size(), "auto graphics has a real menu choice")
	menu.set_graphics_choice(2, false)
	t.eq(menu._graphics_picker.selected, 2, "Settings reflects manual high quality")
	menu.set_graphics_choice(1, true)
	t.eq(menu._graphics_picker.selected, 4, "Settings reflects auto quality")
	var chosen: Array[int] = []
	menu.graphics_selected.connect(func(level: int) -> void: chosen.append(level))
	menu._graphics_picker.item_selected.emit(3)
	t.eq(chosen, [3], "graphics tab sends chosen preset to live scene controller")
	menu._graphics_picker.item_selected.emit(GraphicsQuality.NAMES.size())
	t.eq(chosen, [3, 4], "graphics tab sends auto mode to live controller")
	var sfx: HSlider = menu._audio_sliders["SFX"]
	sfx.value = 35.0
	t.near(float(AudioMix.volumes["SFX"]), 0.35, 0.001, "slider applies to real SFX bus")
	t.eq((menu._audio_value_labels["SFX"] as Label).text, "35%",
		"SFX number updates while dragging")
	menu.close()
	var sound_cfg := ConfigFile.new()
	t.eq(sound_cfg.load(AudioMix.path), OK, "closing settings persists changed sound volume")
	t.near(float(sound_cfg.get_value("volume", "SFX", 1.0)), 0.35, 0.001, "SFX persisted")
	AudioMix.set_volume("SFX", 0.7, false)
	menu._refresh_audio_sliders()
	t.near(sfx.value, 70.0, 0.01, "reopening the settings page refreshes externally changed volume")
	t.eq((menu._audio_value_labels["SFX"] as Label).text, "70%",
		"SFX number refreshes with external volume changes")
	var audio_page: VBoxContainer = menu._tabs.get_node("Audio").get_child(0) as VBoxContainer
	var audio_reset: Button = audio_page.get_child(audio_page.get_child_count() - 1) as Button
	audio_reset.pressed.emit()
	for bus in AudioMix.SLIDERS:
		t.near(float(AudioMix.volumes[bus]), 1.0, 0.001, "audio reset restores all five buses")
		t.eq((menu._audio_value_labels[bus] as Label).text, "100%",
			"sound percentage readout refreshes after reset")
	var online_source: String = FileAccess.get_file_as_string("res://scripts/client/online_main.gd")
	t.check(online_source.contains('menu.connect("graphics_selected"'),
		"game connects pause graphics picker to real world rendering")
	t.check(online_source.contains('settings_button.text = "Settings"'),
		"title screen exposes the same Settings window")
	t.check(online_source.contains("func _apply_graphics_selection(") and
		online_source.contains("GraphicsQuality.apply(get_viewport()"),
		"graphics selection uses the full renderer / streamer path")
	t.eq(UiLocalization.t("Graphics", "ru"), "Графика", "graphics tab translated")
	t.eq(UiLocalization.t("Audio", "ru"), "Звук", "audio tab translated")
	t.eq(UiLocalization.t("Reset display settings", "ru"), "Сбросить настройки экрана",
		"video reset has a Russian label")
	DisplaySettings.path = prior_display_path
	DisplaySettings.load_all()
	Engine.max_fps = prior_fps
	AudioMix.path = prior_audio_path
	AudioMix.reset_volumes(false)
	AudioMix.load_all()
	DirAccess.remove_absolute("user://test_albion_settings_audio.cfg")
	AudioMix.set_volume("SFX", 0.2, false)
	AudioMix.path = "user://test_albion_settings_audio.cfg"
	AudioMix.load_all()
	t.near(float(AudioMix.volumes["SFX"]), 1.0, 0.001,
		"missing audio configuration restores default live mixer volumes")
	AudioMix.path = prior_audio_path
	AudioMix.load_all()
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


func _streaming_line(t) -> void:
	t.current = "FPS overlay streaming line tolerates older engine builds"
	var Layer = load("res://scripts/client/ui_accessibility_layer.gd")
	t.eq(Layer.world_streaming_line(RefCounted.new()), "streaming stats unavailable", "no streamer methods: no call, no error")
	if ClassDB.class_exists("WorldStreamer"):
		var streamer = ClassDB.instantiate("WorldStreamer")
		var line: String = Layer.world_streaming_line(streamer)
		t.check(line.contains("chunks"), "real streamer reports chunks")
		t.check(line.contains("retry") == streamer.has_method("get_retry_pending_count"), "retry shown only when the build has it")
		streamer.free()
