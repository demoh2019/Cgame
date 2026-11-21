extends Node
class_name AdaptiveResolution3D
## Conservative, viewport-local dynamic resolution for 3D scenes.
## Does not alter physics ticks, window size, UI scale, or global project settings.

@export_range(20.0, 240.0, 1.0) var target_fps: float = 60.0
@export_range(0.25, 2.0, 0.01) var minimum_scale: float = 0.67
@export_range(0.25, 2.0, 0.01) var maximum_scale: float = 1.0
@export_range(0.01, 0.25, 0.01) var decrease_step: float = 0.05
@export_range(0.01, 0.25, 0.005) var increase_step: float = 0.025
@export_range(0.1, 10.0, 0.1) var sampling_seconds: float = 1.0
@export_range(0.0, 20.0, 0.5) var warmup_seconds: float = 3.0
@export_range(0.0, 20.0, 0.5) var cooldown_seconds: float = 3.0
@export_range(0.5, 0.95, 0.01) var low_fps_ratio: float = 0.90
@export_range(0.95, 1.1, 0.005) var high_fps_ratio: float = 0.985
@export var enabled: bool = true
@export var restore_on_exit: bool = true
@export var use_spatial_fsr_if_bilinear: bool = true
@export var skip_cpu_bound_drops: bool = true
## Opt in: measuring the shared viewport also costs work and is not reference-counted.
@export var enable_gpu_frame_measurement: bool = false
@export_range(1.0, 1.5, 0.01) var gpu_over_budget_ratio: float = 1.03
@export_range(0.50, 0.95, 0.01) var gpu_headroom_ratio: float = 0.85
@export_range(0.50, 1.25, 0.05) var cpu_guard_budget_ratio: float = 0.90

var _viewport: Viewport
var _original_scale: float = 1.0
var _original_mode: Viewport.Scaling3DMode
var _elapsed: float = 0.0
var _warmup_elapsed: float = 0.0
var _cooldown_elapsed: float = 0.0
var _fps_sum: float = 0.0
var _samples: int = 0
var _cpu_cost_seconds_sum: float = 0.0
var _gpu_rid: RID
var _gpu_ms_sum: float = 0.0
var _gpu_samples: int = 0


func _ready() -> void:
	_viewport = get_viewport()
	_original_scale = _viewport.scaling_3d_scale
	_original_mode = _viewport.scaling_3d_mode
	if enable_gpu_frame_measurement:
		_gpu_rid = _viewport.get_viewport_rid()
		RenderingServer.viewport_set_measure_render_time(_gpu_rid, true)
	if use_spatial_fsr_if_bilinear and RenderingServer.get_current_rendering_method() != "gl_compatibility":
		if _viewport.scaling_3d_mode == Viewport.SCALING_3D_MODE_BILINEAR:
			_viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR
	reset_to_maximum()


func _process(delta: float) -> void:
	if not enabled or _viewport == null or delta <= 0.0:
		return
	_warmup_elapsed += delta
	_cooldown_elapsed += delta
	if _warmup_elapsed < warmup_seconds:
		return
	_elapsed += delta
	var fps: float = Engine.get_frames_per_second()
	if fps > 0.0:
		_fps_sum += fps
		_samples += 1
		_cpu_cost_seconds_sum += maxf(
			float(Performance.get_monitor(Performance.TIME_PROCESS)),
			float(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS))
		)
		if enable_gpu_frame_measurement:
			var gpu_ms: float = RenderingServer.viewport_get_measured_render_time_gpu(_gpu_rid)
			if is_finite(gpu_ms) and gpu_ms > 0.0:
				_gpu_ms_sum += gpu_ms
				_gpu_samples += 1
	if _elapsed < sampling_seconds:
		return
	_elapsed = 0.0
	if _samples == 0:
		return
	var averaged_fps: float = _fps_sum / float(_samples)
	var cpu_cost_seconds: float = _cpu_cost_seconds_sum / float(_samples)
	var has_gpu_measurement: bool = _gpu_samples > 0
	var average_gpu_ms: float = _gpu_ms_sum / float(_gpu_samples) if has_gpu_measurement else 0.0
	_fps_sum = 0.0
	_cpu_cost_seconds_sum = 0.0
	_gpu_ms_sum = 0.0
	_gpu_samples = 0
	_samples = 0
	if _cooldown_elapsed < cooldown_seconds:
		return
	var next: float = _viewport.scaling_3d_scale
	if has_gpu_measurement:
		next = calculate_next_scale_from_gpu(
			_viewport.scaling_3d_scale, average_gpu_ms, target_fps,
			minimum_scale, maximum_scale, decrease_step, increase_step,
			gpu_over_budget_ratio, gpu_headroom_ratio
		)
	else:
		next = calculate_next_scale(
			_viewport.scaling_3d_scale, averaged_fps, target_fps,
			minimum_scale, maximum_scale, decrease_step, increase_step,
			low_fps_ratio, high_fps_ratio
		)
		if next < _viewport.scaling_3d_scale and skip_cpu_bound_drops:
			if is_cpu_bound(cpu_cost_seconds, target_fps, cpu_guard_budget_ratio):
				return
	if not is_equal_approx(next, _viewport.scaling_3d_scale):
		_viewport.scaling_3d_scale = next
		_cooldown_elapsed = 0.0


func reset_to_maximum() -> void:
	if _viewport == null:
		return
	_viewport.scaling_3d_scale = clampf(maximum_scale, 0.25, 2.0)
	_elapsed = 0.0
	_fps_sum = 0.0
	_cpu_cost_seconds_sum = 0.0
	_gpu_ms_sum = 0.0
	_gpu_samples = 0
	_samples = 0
	_cooldown_elapsed = 0.0


func _exit_tree() -> void:
	if enable_gpu_frame_measurement and _gpu_rid.is_valid():
		RenderingServer.viewport_set_measure_render_time(_gpu_rid, false)
	if restore_on_exit and _viewport != null:
		_viewport.scaling_3d_scale = _original_scale
		_viewport.scaling_3d_mode = _original_mode


static func calculate_next_scale(current_scale: float, fps: float, target: float,
		min_scale: float, max_scale: float, down_step: float, up_step: float,
		low_ratio: float, high_ratio: float) -> float:
	var low: float = clampf(min_scale, 0.25, 2.0)
	var high: float = clampf(max_scale, low, 2.0)
	var current: float = clampf(current_scale, low, high)
	if fps <= 0.0 or target <= 0.0:
		return current
	if fps < target * low_ratio:
		return clampf(snappedf(current - maxf(down_step, 0.0), 0.005), low, high)
	if fps >= target * high_ratio:
		return clampf(snappedf(current + maxf(up_step, 0.0), 0.005), low, high)
	return current


## TIME_PROCESS/TIME_PHYSICS_PROCESS are CPU hints, not GPU frame timings.
## If scripting already exhausts the frame budget, reducing render pixels
## is unlikely to help. Never mislabel this as actual GPU-bound detection.
static func is_cpu_bound(cpu_cost_seconds: float, target: float, guard_ratio: float) -> bool:
	if not is_finite(cpu_cost_seconds) or target <= 0.0:
		return false
	return cpu_cost_seconds > 0.0 and cpu_cost_seconds >= (1.0 / target) * maxf(guard_ratio, 0.0)


## Pixel cost scales roughly with the square of render scale. This threshold
## control avoids guessing based on a V-Sync-capped FPS alone.
static func calculate_next_scale_from_gpu(current_scale: float, gpu_ms: float, target: float,
		min_scale: float, max_scale: float, down_step: float, up_step: float,
		over_budget_ratio: float, headroom_ratio: float) -> float:
	var low: float = clampf(min_scale, 0.25, 2.0)
	var high: float = clampf(max_scale, low, 2.0)
	var current: float = clampf(current_scale, low, high)
	if not is_finite(gpu_ms) or gpu_ms <= 0.0 or target <= 0.0:
		return current
	var budget_ms: float = 1000.0 / target
	if gpu_ms > budget_ms * maxf(over_budget_ratio, 1.0):
		return clampf(snappedf(current - maxf(down_step, 0.0), 0.005), low, high)
	if gpu_ms < budget_ms * clampf(headroom_ratio, 0.0, 1.0):
		return clampf(snappedf(current + maxf(up_step, 0.0), 0.005), low, high)
	return current
