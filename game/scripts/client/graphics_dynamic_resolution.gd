extends RefCounted
## 3D pixel-budget scaler; hysteresis and warmup avoid per-frame GPU buffer
## resizes. Valid GPU timer queries keep CPU-bound frames from unnecessarily
## lowering the 3D pixel budget. Quality presets remain the outer fallback.
const FLOORS := [0.52, 0.65, 0.82, 0.90]
const CEILINGS := [0.59, 0.77, 1.0, 1.0]
const SLOW_FRAME := 1.0 / 48.0
const FAST_FRAME := 1.0 / 56.0
const LOWER_AFTER := 2.2
const RAISE_AFTER := 6.0
const WARMUP := 1.0
const MAX_VALID_GPU_MS := 80.0

var level: int = 1
var scale: float = 0.77
var floor_scale: float = 0.65
var _warmup := 0.0
var _slow := 0.0
var _fast := 0.0


func configure(value: int, device_min_scale: float = 0.0) -> void:
	level = clampi(value, 0, FLOORS.size() - 1)
	# MetalFX on Apple GPUs can have a higher minimum temporal input
	# scale. Its hardware floor is authoritative, but quality ceilings
	# and ordinary FSR2 behavior remain unchanged.
	var native_min: float = device_min_scale if is_finite(device_min_scale) else 0.0
	floor_scale = clampf(maxf(float(FLOORS[level]), native_min),
		float(FLOORS[level]), float(CEILINGS[level]))
	scale = float(CEILINGS[level])
	_warmup = 0.0
	_slow = 0.0
	_fast = 0.0


func at_floor() -> bool:
	return scale <= floor_scale + 0.0001


func at_ceiling() -> bool:
	return scale >= float(CEILINGS[level]) - 0.0001


## GPU timer queries are in milliseconds, while process deltas are seconds.
## Zero is the Godot signal for disabled/unavailable GPU measurements.
## Fallback preserves Compatibility/headless behavior and deterministic tests.
static func render_frame_seconds(delta: float, measured_gpu_ms: float = 0.0) -> float:
	if is_finite(measured_gpu_ms) and measured_gpu_ms > 0.0 and measured_gpu_ms <= MAX_VALID_GPU_MS:
		return measured_gpu_ms * 0.001
	return delta


func sample_frame(delta: float, measured_gpu_ms: float = 0.0) -> bool:
	if not is_finite(delta) or delta <= 0.0 or delta > 0.20:
		return false
	_warmup += delta
	if _warmup < WARMUP:
		return false
	var demand: float = render_frame_seconds(delta, measured_gpu_ms)
	if demand >= SLOW_FRAME:
		_slow += delta
		_fast = 0.0
		if _slow >= LOWER_AFTER:
			_slow = 0.0
			if not at_floor():
				scale = roundf(maxf(floor_scale, scale - 0.04) * 100.0) / 100.0
				# Rounding must not step under device minimum.
				scale = maxf(scale, floor_scale)
				return true
	elif demand <= FAST_FRAME:
		_fast += delta
		_slow = 0.0
		if _fast >= RAISE_AFTER:
			_fast = 0.0
			if not at_ceiling():
				scale = roundf(minf(float(CEILINGS[level]), scale + 0.03) * 100.0) / 100.0
				return true
	else:
		_slow = 0.0
		_fast = 0.0
	return false
