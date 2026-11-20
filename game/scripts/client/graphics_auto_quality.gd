extends RefCounted
## Adaptive visual detail reacts to sustained frame time, not isolated stalls or loading spikes.
## The controller is deterministic and does not require a GPU to test.

const GRASS_FADE_END := [40.0, 60.0, 80.0]
const SLOW_FRAME := 1.0 / 45.0
const FAST_FRAME := 1.0 / 55.0
const DOWNGRADE_AFTER := 3.5
const UPGRADE_AFTER := 9.0

var mode := "auto"
var level := 1
var _slow_seconds := 0.0
var _fast_seconds := 0.0


func preset() -> Dictionary:
	return {"grass_end": GRASS_FADE_END[clampi(level, 0, 2)]}


func set_mode(value: String) -> bool:
	if value not in ["auto", "performance", "balanced", "quality"]:
		return false
	mode = value
	match value:
		"performance":
			level = 0
		"balanced":
			level = 1
		"quality":
			level = 2
	_slow_seconds = 0.0
	_fast_seconds = 0.0
	return true


## Frames above 200 ms are usually loading stalls; never react to a single one.
func sample_frame(delta: float) -> bool:
	if mode != "auto" or delta <= 0.0 or delta > 0.2:
		return false
	if delta >= SLOW_FRAME:
		_slow_seconds += delta
		_fast_seconds = 0.0
		if _slow_seconds >= DOWNGRADE_AFTER:
			_slow_seconds = 0.0
			if level > 0:
				level -= 1
				return true
	elif delta <= FAST_FRAME:
		_fast_seconds += delta
		_slow_seconds = 0.0
		if _fast_seconds >= UPGRADE_AFTER:
			_fast_seconds = 0.0
			if level < 2:
				level += 1
				return true
	else:
		_slow_seconds = 0.0
		_fast_seconds = 0.0
	return false
