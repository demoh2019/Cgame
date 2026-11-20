extends RefCounted
## Runtime glue the game loop calls every frame: rebindable movement polling with hold/toggle latching, UI scale and
## the high-contrast interface theme. Static so online_main only needs one-line calls.

const UiSettings = preload("res://scripts/client/ui_settings.gd")
const UiInputRebind = preload("res://scripts/client/ui_input_rebind.gd")
const UiTheme = preload("res://scripts/client/ui_theme.gd")

static var _sprint_prev := false
static var _sprint_state := false
static var _crouch_prev := false
static var _crouch_state := false
static var _contrast_saved: Dictionary = {}


## Movement, sprint and crouch from the (rebindable) actions. Call once per physics frame.
static func read_move() -> Dictionary:
	var move := Vector2(
		Input.get_axis("ui_left", "ui_right") + Input.get_axis("access_left", "access_right"),
		Input.get_axis("ui_up", "ui_down") + Input.get_axis("access_up", "access_down"))
	var sprint_raw := Input.is_action_pressed("access_sprint")
	var crouch_raw := Input.is_action_pressed("access_crouch")
	var sprint := UiSettings.resolve_hold(bool(UiSettings.get_value("toggle_sprint")), sprint_raw, _sprint_prev, _sprint_state)
	var crouch := UiSettings.resolve_hold(bool(UiSettings.get_value("toggle_crouch")), crouch_raw, _crouch_prev, _crouch_state)
	_sprint_prev = sprint_raw
	_crouch_prev = crouch_raw
	_sprint_state = sprint[1]
	_crouch_state = crouch[1]
	# Crouch and sprint exclude each other so a latched toggle cannot fight a held key.
	if crouch[0] and sprint[0]:
		if crouch_raw:
			_sprint_state = false
			sprint[0] = false
		else:
			_crouch_state = false
			crouch[0] = false
	return {"move": move, "sprint": sprint[0], "crouch": crouch[0]}


static func clear_latches() -> void:
	_sprint_prev = false
	_sprint_state = false
	_crouch_prev = false
	_crouch_state = false


static func apply_ui_scale(window: Window) -> void:
	if window != null:
		window.content_scale_factor = float(UiSettings.get_value("ui_scale"))


## Pure-white outlined text on the over-world theme and black ink on parchment, thicker outlines.
## Edits the shared Theme resources in place so every live Label updates immediately; `false` restores them.
static func apply_high_contrast(enabled: bool) -> void:
	var themes := [UiTheme.get_theme(), UiTheme.paper_theme()]
	if enabled and _contrast_saved.is_empty():
		for i in themes.size():
			var theme: Theme = themes[i]
			_contrast_saved[i] = {
				"font": theme.get_color("font_color", "Label"),
				"outline": theme.get_constant("outline_size", "Label"),
				"outline_color": theme.get_color("font_outline_color", "Label"),
			}
		var over: Theme = themes[0]
		over.set_color("font_color", "Label", Color.WHITE)
		over.set_color("font_outline_color", "Label", Color.BLACK)
		over.set_constant("outline_size", "Label", 8)
		var paper: Theme = themes[1]
		paper.set_color("font_color", "Label", Color.BLACK)
		paper.set_color("font_outline_color", "Label", Color.WHITE)
		paper.set_constant("outline_size", "Label", 1)
	elif not enabled and not _contrast_saved.is_empty():
		for i in themes.size():
			var theme: Theme = themes[i]
			var saved: Dictionary = _contrast_saved[i]
			theme.set_color("font_color", "Label", saved["font"])
			theme.set_color("font_outline_color", "Label", saved["outline_color"])
			theme.set_constant("outline_size", "Label", saved["outline"])
		_contrast_saved.clear()


static func high_contrast_active() -> bool:
	return not _contrast_saved.is_empty()
