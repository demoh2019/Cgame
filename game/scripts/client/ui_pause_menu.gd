extends Control
## Esc / gamepad Menu settings window: gameplay toggles, key rebinding, accessibility and language. Built in code on
## the parchment theme; the game keeps running behind it (the server is authoritative, so there is no true pause).
## Every control writes straight into UiSettings / UiInputRebind and emits `changed` so the layer re-applies.

const UiTheme = preload("res://scripts/client/ui_theme.gd")
const UiSettings = preload("res://scripts/client/ui_settings.gd")
const UiInputRebind = preload("res://scripts/client/ui_input_rebind.gd")
const UiLocalization = preload("res://scripts/client/ui_localization.gd")

signal changed(key: String)
signal closed

var _capturing := ""
var _bind_buttons: Dictionary = {}
var _notice: Label
var _tabs: TabContainer


func _init() -> void:
	name = "PauseMenu"
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UiTheme.paper_theme()
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(560, 0)
	center.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	panel.add_child(column)
	var title := Label.new()
	title.text = "Paused"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	column.add_child(title)
	_tabs = TabContainer.new()
	_tabs.custom_minimum_size = Vector2(0, 360)
	column.add_child(_tabs)
	_build_gameplay()
	_build_controls()
	_build_accessibility()
	_notice = Label.new()
	_notice.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_notice.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	column.add_child(_notice)
	var resume := Button.new()
	resume.text = "Resume"
	resume.custom_minimum_size = Vector2(0, 40)
	resume.pressed.connect(close)
	column.add_child(resume)


func is_open() -> bool:
	return visible


func open() -> void:
	_capturing = ""
	_refresh_bindings()
	visible = true
	_tabs.get_tab_bar().grab_focus()


func close() -> void:
	_capturing = ""
	visible = false
	closed.emit()


func _page(tab_name: String) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.name = tab_name
	box.add_theme_constant_override("separation", 8)
	_tabs.add_child(box)
	return box


func _check(parent: Control, text: String, key: String) -> CheckBox:
	var box := CheckBox.new()
	box.text = text
	box.button_pressed = bool(UiSettings.get_value(key))
	box.toggled.connect(func(on: bool) -> void:
		UiSettings.set_value(key, on)
		changed.emit(key))
	parent.add_child(box)
	return box


func _row(parent: Control, text: String, control: Control) -> void:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	control.custom_minimum_size = Vector2(220, 0)
	row.add_child(control)
	parent.add_child(row)


func _option(items: Array, selected: int, key: String) -> OptionButton:
	var picker := OptionButton.new()
	for i in items.size():
		picker.add_item(items[i], i)
	picker.select(selected)
	picker.item_selected.connect(func(index: int) -> void:
		UiSettings.set_value(key, index)
		changed.emit(key))
	return picker


func _build_gameplay() -> void:
	var page := _page("Gameplay")
	var language := OptionButton.new()
	language.add_item("English", 0)
	language.add_item("Русский", 1)
	language.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	language.select(1 if TranslationServer.get_locale().begins_with("ru") else 0)
	language.item_selected.connect(func(index: int) -> void:
		UiLocalization.set_locale(UiSettings.LOCALES[index])
		changed.emit("locale"))
	_row(page, "Language", language)
	_check(page, "Toggle sprint", "toggle_sprint")
	_check(page, "Toggle crouch", "toggle_crouch")
	_check(page, "Show FPS overlay", "show_fps")
	# First person (middle mouse): lens, look speed and motion comfort.
	_row(page, "First-person field of view", _slider(60.0, 110.0, 1.0, "fp_fov"))
	_row(page, "Mouse sensitivity", _slider(0.1, 4.0, 0.05, "mouse_sensitivity"))
	_check(page, "Invert mouse Y", "invert_y")
	_check(page, "First-person head bob", "fp_head_bob")


func _slider(min_value: float, max_value: float, step: float, key: String) -> HSlider:
	var slider := HSlider.new()
	slider.min_value = min_value
	slider.max_value = max_value
	slider.step = step
	slider.value = float(UiSettings.get_value(key))
	slider.value_changed.connect(func(value: float) -> void:
		UiSettings.set_value(key, value, false) # Live while dragging, saved on release.
		changed.emit(key))
	slider.drag_ended.connect(func(_moved: bool) -> void:
		UiSettings.set_value(key, slider.value))
	return slider


func _build_controls() -> void:
	var page := _page("Controls")
	var hint := Label.new()
	hint.text = "Rebind keys: click an action, then press a key (Esc cancels)."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	page.add_child(hint)
	for entry in UiInputRebind.ACTIONS:
		var action: String = entry[0]
		var button := Button.new()
		button.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		button.pressed.connect(func() -> void:
			_capturing = action
			_refresh_bindings())
		_bind_buttons[action] = button
		var caption := Label.new()
		caption.text = entry[1]
		var row := HBoxContainer.new()
		caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(caption)
		button.custom_minimum_size = Vector2(220, 0)
		row.add_child(button)
		page.add_child(row)
	var reset := Button.new()
	reset.text = "Reset to defaults"
	reset.pressed.connect(func() -> void:
		UiInputRebind.reset()
		_notice.text = ""
		_refresh_bindings())
	page.add_child(reset)
	var pad := Label.new()
	pad.text = "Gamepad detected: on-screen prompts follow the last device used."
	pad.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	page.add_child(pad)


func _build_accessibility() -> void:
	var page := _page("Accessibility")
	var filter_names := []
	for n in UiSettings.COLORBLIND_NAMES:
		filter_names.append(UiLocalization.t(n))
	_row(page, "Colorblind filter", _option(filter_names, int(UiSettings.get_value("colorblind")), "colorblind"))
	var slider := HSlider.new()
	slider.min_value = UiSettings.UI_SCALE_MIN
	slider.max_value = UiSettings.UI_SCALE_MAX
	slider.step = 0.05
	slider.value = float(UiSettings.get_value("ui_scale"))
	# Apply on release so the window does not rescale under the mouse while dragging.
	slider.drag_ended.connect(func(moved: bool) -> void:
		if moved:
			UiSettings.set_value("ui_scale", slider.value)
			changed.emit("ui_scale"))
	_row(page, "Interface scale", slider)
	_check(page, "Reduce screen shake", "reduce_shake")
	_check(page, "Reduce flashes", "reduce_flashes")
	_check(page, "High-contrast interface", "high_contrast")
	_check(page, "Closed captions", "captions")
	_row(page, "Caption size", _option([UiLocalization.t("Small"), UiLocalization.t("Medium"), UiLocalization.t("Large")],
		int(UiSettings.get_value("caption_size")), "caption_size"))


func _refresh_bindings() -> void:
	for action in _bind_buttons:
		var button: Button = _bind_buttons[action]
		if _capturing == action:
			button.text = UiLocalization.t("Press a key...")
		else:
			button.text = UiInputRebind.key_text(UiInputRebind.key_of(action))


## Captures the next key press while a binding button is armed. Returns true when the event was consumed.
func handle_capture(event: InputEvent) -> bool:
	if _capturing == "" or not (event is InputEventKey):
		return false
	var key := event as InputEventKey
	if not key.pressed or key.echo:
		return true
	if key.physical_keycode != KEY_ESCAPE:
		var swapped := UiInputRebind.rebind(_capturing, key.physical_keycode)
		_notice.text = UiLocalization.t("Already used by %s: swapped.") % UiLocalization.t(UiInputRebind.label_for(swapped)) \
			if swapped != "" else ""
	_capturing = ""
	_refresh_bindings()
	return true
