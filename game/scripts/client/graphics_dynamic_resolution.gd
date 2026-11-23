extends RefCounted
const EngineFeatures = preload("res://scripts/client/engine_features.gd")
const PanicPolicy = preload("res://scripts/client/graphics_resolution_panic.gd")
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
## Unreal-inspired GPU panic: respond to 3 consecutive bad GPU frames,
## then pause expensive viewport reallocations for half a second.
const PANIC_GPU_MS := 38.0
const PANIC_TARGET_MS := 20.0
const PANIC_FRAMES := 3
const PANIC_COOLDOWN_SECONDS := 0.55

var level: int = 1
var scale: float = 0.77
var floor_scale: float = 0.65
var _warmup := 0.0
var _slow := 0.0
var _fast := 0.0
var _panic_frames: int = 0
var _panic_cooldown: float = 0.0
var _native_panic: Object = EngineFeatures.make("DynamicResolutionPanicPolicy")


func configure(value: int, device_min_scale: float = 0.0) -> void:
	level = clampi(value, 0, FLOORS.size() - 1)
	# MetalFX on Apple GPUs can have a higher minimum temporal input
	# scale. Its hardware floor is authoritative, but quality ceilings
	# and ordinary FSR2 behavior remain unchanged.
	var native_min: float = device_min_scale if is_finite(device_min_scale) else 0.0
	# If the device's temporal floor is higher than the entire profile,
	# use FSR2 and retain the old lower floor. Clamping it to the ceiling
	# would otherwise prevent any GPU-bound resolution reduction.
	if native_min > float(CEILINGS[level]):
		native_min = 0.0
	floor_scale = clampf(maxf(float(FLOORS[level]), native_min),
		float(FLOORS[level]), float(CEILINGS[level]))
	scale = float(CEILINGS[level])
	_warmup = 0.0
	_slow = 0.0
	_fast = 0.0
	_panic_frames = 0
	_panic_cooldown = 0.0


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


## Pure policy call: native C++ if available, bit-for-bit matching script fallback.
## A rejected native request (-1) is not allowed to corrupt the render scale.
func _panic_scale(measured_gpu_ms: float, consecutive_frames: int) -> float:
	var next_scale: float
	if _native_panic != null and _native_panic.has_method("calculate_scale"):
		next_scale = float(_native_panic.call("calculate_scale",
			scale, floor_scale, measured_gpu_ms, PANIC_TARGET_MS,
			consecutive_frames, PANIC_FRAMES))
	else:
		next_scale = PanicPolicy.calculate_scale(
			scale, floor_scale, measured_gpu_ms, PANIC_TARGET_MS,
			consecutive_frames, PANIC_FRAMES)
	if not is_finite(next_scale) or next_scale < floor_scale - 0.000001 \
			or next_scale > scale + 0.000001:
		return scale
	return clampf(next_scale, floor_scale, scale)


func sample_frame(delta: float, measured_gpu_ms: float = 0.0) -> bool:
	if not is_finite(delta) or delta <= 0.0 or delta > 0.20:
		return false
	_warmup += delta
	if _warmup < WARMUP:
		return false
	_panic_cooldown = maxf(0.0, _panic_cooldown - delta)
	# Never infer GPU panic from CPU frame deltas, unavailable timers, or
	# compilation hitches discarded by MAX_VALID_GPU_MS. Three actual GPU
	# overruns are required, avoiding costly viewport resizes on one spike.
	if is_finite(measured_gpu_ms) and measured_gpu_ms >= PANIC_GPU_MS \
			and measured_gpu_ms <= MAX_VALID_GPU_MS:
		_panic_frames = mini(_panic_frames + 1, PANIC_FRAMES)
	else:
		_panic_frames = 0
	if _panic_frames >= PANIC_FRAMES and _panic_cooldown <= 0.0 and not at_floor():
		var emergency_scale: float = _panic_scale(measured_gpu_ms, _panic_frames)
		if emergency_scale < scale - 0.0001:
			scale = emergency_scale
			_panic_frames = 0
			_panic_cooldown = PANIC_COOLDOWN_SECONDS
			_slow = 0.0
			_fast = 0.0
			return true
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
	elif demand <= FAST_FRAME and delta <= FAST_FRAME:
		# A fast GPU does not justify additional viewport reallocations
		# while scripts, networking or physics are CPU-frame-bound.
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
