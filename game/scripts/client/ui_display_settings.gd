extends RefCounted
## Video/display settings. Only client presentation; no network/gameplay authority.
## Stored in graphics config alongside the quality preset, in its own section.

const GraphicsQuality = preload("res://scripts/client/graphics_quality.gd")
const SECTION := "display"
const WINDOW_MODES := ["Windowed", "Fullscreen"]
const VSYNC_MODES := ["Off", "On"]
const FPS_LIMITS := [0, 30, 60, 120, 144, 240]
const DEFAULTS := {"window_mode": 0, "vsync": 1, "fps_limit": 0}

static var path: String = GraphicsQuality.SETTINGS_PATH
static var values: Dictionary = DEFAULTS.duplicate()


## Reject invalid configuration before it reaches Engine or DisplayServer.
static func sanitize(key: String, value) -> int:
	if not DEFAULTS.has(key) or not (value is float or value is int):
		return int(DEFAULTS.get(key, 0))
	var v: float = float(value)
	if not is_finite(v) or v < 0.0 or v > 10000.0:
		return int(DEFAULTS[key])
	var n: int = int(v)
	match key:
		"window_mode":
			return clampi(n, 0, WINDOW_MODES.size() - 1)
		"vsync":
			return clampi(n, 0, VSYNC_MODES.size() - 1)
		"fps_limit":
			return n if n in FPS_LIMITS else int(DEFAULTS[key])
	return int(DEFAULTS[key])


## Restore only display options; preserve graphics quality, Auto, and UI.
static func reset(persist: bool = true) -> void:
	values = DEFAULTS.duplicate()
	if persist:
		save()


static func load_all() -> void:
	values = DEFAULTS.duplicate()
	var config := ConfigFile.new()
	if config.load(path) != OK:
		return
	for key in DEFAULTS:
		values[key] = sanitize(key, config.get_value(SECTION, key, DEFAULTS[key]))


static func get_value(key: String) -> int:
	return int(values.get(key, DEFAULTS.get(key, 0)))


static func set_value(key: String, value, persist: bool = true) -> void:
	if not DEFAULTS.has(key):
		return
	values[key] = sanitize(key, value)
	if persist:
		save()


static func save() -> int:
	var config := ConfigFile.new()
	config.load(path) # Keep quality, Auto, interface settings and key bindings.
	for key in DEFAULTS:
		config.set_value(SECTION, key, get_value(key))
	var error: int = config.save(path)
	if error != OK:
		push_warning("Could not save video settings: %d" % error)
	return error


static func apply(window: Window) -> void:
	# A capped render loop can reduce idle GPU power; 0 means unlimited.
	Engine.max_fps = get_value("fps_limit")
	# The headless server still tests persistence without touching a fake display.
	if window == null or DisplayServer.get_name() == "headless":
		return
	var mode: int = Window.MODE_FULLSCREEN if get_value("window_mode") == 1 else Window.MODE_WINDOWED
	if window.mode != mode:
		window.mode = mode
	# Only On/Off: non-enabled V-Sync modes require renderer support.
	var vsync: int = DisplayServer.VSYNC_ENABLED if get_value("vsync") == 1 else DisplayServer.VSYNC_DISABLED
	if DisplayServer.window_get_vsync_mode() != vsync:
		DisplayServer.window_set_vsync_mode(vsync)
