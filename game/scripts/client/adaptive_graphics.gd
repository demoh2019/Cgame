extends RefCounted
## Adaptive client-side visual quality. Decisions use only smoothed frame timing, not one-off hitches.
## Manual graphics presets always take priority; the separate opt-in setting is persistent.

const GraphicsQuality = preload("res://scripts/client/graphics_quality.gd")
const SETTINGS_PATH := "user://albion_after_graphics_auto.cfg"
const SAMPLE_SECONDS := 2.0
const WARMUP_SECONDS := 5.0
const LOW_FPS := 46.0
const HIGH_FPS := 58.0

var enabled := true
var _warmup := WARMUP_SECONDS
var _seconds := 0.0
var _frames := 0
var _slow_windows := 0
var _fast_windows := 0
var _cooldown := 0.0


func load_preference(default_enabled: bool = true) -> void:
	var config := ConfigFile.new()
	enabled = default_enabled
	if config.load(SETTINGS_PATH) == OK:
		enabled = bool(config.get_value("rendering", "auto_quality", default_enabled))
	_reset()


func set_enabled(value: bool, persist: bool = true) -> void:
	enabled = value
	_reset()
	if persist:
		var config := ConfigFile.new()
		config.set_value("rendering", "auto_quality", enabled)
		var error := config.save(SETTINGS_PATH)
		if error != OK:
			push_warning("Could not save adaptive graphics preference: %d" % error)


func _reset() -> void:
	_warmup = WARMUP_SECONDS
	_seconds = 0.0
	_frames = 0
	_slow_windows = 0
	_fast_windows = 0
	_cooldown = 0.0


## True when GraphicsQuality's rendering profile changed and should be applied to the scene.
## Skip minimized/paused frames and warm up after joining to avoid reacting to asset loading.
func sample_frame(delta: float) -> bool:
	if not enabled or delta <= 0.0 or delta > 0.25:
		return false
	_warmup = maxf(0.0, _warmup - delta)
	if _warmup > 0.0:
		return false
	_seconds += delta
	_frames += 1
	if _seconds < SAMPLE_SECONDS:
		return false
	var fps := float(_frames) / _seconds
	_cooldown = maxf(0.0, _cooldown - _seconds)
	_seconds = 0.0
	_frames = 0
	if fps < LOW_FPS:
		_slow_windows += 1
		_fast_windows = 0
	elif fps >= HIGH_FPS:
		_fast_windows += 1
		_slow_windows = 0
	else:
		_fast_windows = 0
		_slow_windows = 0
	if _cooldown > 0.0:
		return false
	var level: int = GraphicsQuality.level()
	if _slow_windows >= 2 and level > 0:
		GraphicsQuality.set_level(level - 1, false)
		_slow_windows = 0
		_fast_windows = 0
		_cooldown = 14.0
		return true
	if _fast_windows >= 8 and level < GraphicsQuality.NAMES.size() - 1:
		GraphicsQuality.set_level(level + 1, false)
		_slow_windows = 0
		_fast_windows = 0
		_cooldown = 20.0
		return true
	return false
