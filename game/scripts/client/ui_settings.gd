extends RefCounted
## Client-only accessibility and interface preferences. They live in the same ConfigFile as the graphics
## quality (Unity PlayerPrefs / UE GameUserSettings equivalent), in their own sections, and never touch the
## authoritative simulation. All helpers are static so they can be unit-tested without a scene.

const DEFAULT_PATH := "user://albion_after_graphics.cfg"
const SECTION := "interface"
const COLORBLIND_NAMES := ["Off", "Protanopia", "Deuteranopia", "Tritanopia"]
const UI_SCALE_MIN := 0.75
const UI_SCALE_MAX := 1.75
const CAPTION_SIZES := [14, 18, 24]
const LOCALES := ["en", "ru"]

const DEFAULTS := {
	"ui_scale": 1.0,
	"colorblind": 0,
	"reduce_shake": false,
	"reduce_flashes": false,
	"high_contrast": false,
	"show_fps": false,
	"captions": false,
	"caption_size": 1,
	"toggle_sprint": false,
	"toggle_crouch": false,
	"locale": "",
	"fp_fov": 75.0,
	"mouse_sensitivity": 1.0,
	"invert_y": false,
	"fp_head_bob": true,
}

static var path := DEFAULT_PATH
static var values: Dictionary = DEFAULTS.duplicate()
static var _loaded := false


static func reset_defaults() -> void:
	values = DEFAULTS.duplicate()


static func load_all() -> void:
	if _loaded:
		return
	_loaded = true
	reset_defaults()
	var config := ConfigFile.new()
	if config.load(path) != OK:
		return
	for key in DEFAULTS:
		values[key] = sanitize(key, config.get_value(SECTION, key, DEFAULTS[key]))


static func save_all() -> int:
	var config := ConfigFile.new()
	config.load(path) # Keep rendering and binding sections written by other systems.
	for key in values:
		config.set_value(SECTION, key, values[key])
	return config.save(path)


static func get_value(key: String):
	if not _loaded:
		load_all()
	return values.get(key, DEFAULTS.get(key))


static func set_value(key: String, value, persist: bool = true) -> void:
	if not DEFAULTS.has(key):
		return
	if not _loaded:
		load_all()
	values[key] = sanitize(key, value)
	if persist:
		var error := save_all()
		if error != OK:
			push_warning("Could not save interface setting %s: %d" % [key, error])


## Coerces a stored value to the type and range of its default, so a hand-edited file cannot break the UI.
static func sanitize(key: String, value):
	var fallback = DEFAULTS.get(key)
	var numeric: bool = typeof(value) in [TYPE_FLOAT, TYPE_INT]
	var finite_numeric: bool = numeric and is_finite(float(value))
	match key:
		"ui_scale":
			var f: float = float(value) if numeric else 1.0
			return clampf(f if is_finite(f) else 1.0, UI_SCALE_MIN, UI_SCALE_MAX)
		"colorblind":
			return int(clampf(float(value), 0.0, float(COLORBLIND_NAMES.size() - 1))) if finite_numeric else 0
		"caption_size":
			return int(clampf(float(value), 0.0, float(CAPTION_SIZES.size() - 1))) if finite_numeric else 1
		"locale":
			return str(value) if str(value) in LOCALES else ""
		"fp_fov":
			var fov: float = float(value) if numeric else 75.0
			return clampf(fov if is_finite(fov) else 75.0, 60.0, 110.0)
		"mouse_sensitivity":
			var sens: float = float(value) if numeric else 1.0
			return clampf(sens if is_finite(sens) else 1.0, 0.1, 4.0)
	if typeof(fallback) == TYPE_BOOL:
		if value is bool:
			return value
		# Old versions stored 0/1 flags. Keep compatibility without making a
		# damaged "false" string or NaN enable flashing/shaking settings.
		if finite_numeric and (float(value) == 0.0 or float(value) == 1.0):
			return float(value) == 1.0
	return fallback


## Multiplier for camera shake (Unreal "Camera Shake Scale", Cinemachine impulse gain).
static func shake_scale() -> float:
	return 0.0 if bool(get_value("reduce_shake")) else 1.0


## Multiplier for full-screen flashes; reduced mode removes them rather than dimming a strobe.
static func flash_scale() -> float:
	return 0.0 if bool(get_value("reduce_flashes")) else 1.0


## Hold-to-toggle for sprint and crouch. `toggle` selects the mode; `pressed` is the raw key state this frame,
## `previous` last frame's, `state` the latched value. Returns [active, new_state].
static func resolve_hold(toggle: bool, pressed: bool, previous: bool, state: bool) -> Array:
	if not toggle:
		return [pressed, false]
	var latched := state
	if pressed and not previous:
		latched = not state
	return [latched, latched]


static func cycle_scale(current: float, step: float) -> float:
	return snappedf(clampf(current + step, UI_SCALE_MIN, UI_SCALE_MAX), 0.05)
