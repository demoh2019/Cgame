extends RefCounted
## Adaptive visual detail reacts to sustained frame time, not isolated stalls or loading spikes.
## The controller is deterministic and does not require a GPU to test.

const GraphicsDynamicResolution = preload("res://scripts/client/graphics_dynamic_resolution.gd")
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


## The first tier of adaptive quality changes the actual 3D pixel budget.
## Change expensive world detail only at a resolution limit AND only if the
## GPU (not a CPU scripting/physics stall) has the corresponding demand.
static func at_resolution_limit(rd: bool, at_floor: bool, at_ceiling: bool,
		delta: float, measured_gpu_ms: float = 0.0) -> bool:
	if not rd:
		return true
	var demand: float = GraphicsDynamicResolution.render_frame_seconds(
		delta, measured_gpu_ms)
	return (at_floor and demand >= SLOW_FRAME) or (
		at_ceiling and demand <= FAST_FRAME and delta <= FAST_FRAME)


## GPU timestamps are optional; Compatibility/headless falls back to frame
## delta. Accumulate wall-clock delta to avoid unstable quality on slow GPUs.
## Frames above 200 ms are normally loading stalls, never adjust on them.
func sample_frame(delta: float, measured_gpu_ms: float = 0.0) -> bool:
	if mode != "auto" or not is_finite(delta) or delta <= 0.0 or delta > 0.2:
		return false
	var demand: float = GraphicsDynamicResolution.render_frame_seconds(
		delta, measured_gpu_ms)
	if demand >= SLOW_FRAME:
		_slow_seconds += delta
		_fast_seconds = 0.0
		if _slow_seconds >= DOWNGRADE_AFTER:
			_slow_seconds = 0.0
			if level > 0:
				level -= 1
				return true
	elif demand <= FAST_FRAME and delta <= FAST_FRAME:
		# A fast GPU does not justify loading more CPU-heavy scenery while
		# simulation, navigation or network serialization is the bottleneck.
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
