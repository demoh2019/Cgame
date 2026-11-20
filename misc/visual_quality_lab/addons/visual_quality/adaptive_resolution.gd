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

var _viewport: Viewport
var _original_scale: float = 1.0
var _original_mode: Viewport.Scaling3DMode
var _elapsed: float = 0.0
var _warmup_elapsed: float = 0.0
var _cooldown_elapsed: float = 0.0
var _fps_sum: float = 0.0
var _samples: int = 0


func _ready() -> void:
	_viewport = get_viewport()
	_original_scale = _viewport.scaling_3d_scale
	_original_mode = _viewport.scaling_3d_mode
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
	if _elapsed < sampling_seconds:
		return
	_elapsed = 0.0
	if _samples == 0:
		return
	var averaged_fps: float = _fps_sum / float(_samples)
	_fps_sum = 0.0
	_samples = 0
	if _cooldown_elapsed < cooldown_seconds:
		return
	var next: float = calculate_next_scale(
		_viewport.scaling_3d_scale, averaged_fps, target_fps,
		minimum_scale, maximum_scale, decrease_step, increase_step,
		low_fps_ratio, high_fps_ratio
	)
	if not is_equal_approx(next, _viewport.scaling_3d_scale):
		_viewport.scaling_3d_scale = next
		_cooldown_elapsed = 0.0


func reset_to_maximum() -> void:
	if _viewport == null:
		return
	_viewport.scaling_3d_scale = clampf(maximum_scale, 0.25, 2.0)
	_elapsed = 0.0
	_fps_sum = 0.0
	_samples = 0
	_cooldown_elapsed = 0.0


func _exit_tree() -> void:
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
