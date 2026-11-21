extends RefCounted
## Portable GPU-only over-budget panic step. Mirrors native
## DynamicResolutionPanicPolicy, with no viewport mutation or frame history.
## Caller provides verified consecutive GPU frames and manages cooldown.


static func calculate_scale(current_scale: float, floor_scale: float,
		gpu_ms: float, target_ms: float,
		consecutive_frames: int, required_frames: int = 3) -> float:
	if not is_finite(current_scale) or not is_finite(floor_scale) \
			or not is_finite(gpu_ms) or not is_finite(target_ms) \
			or current_scale < 0.5 or current_scale > 1.0 \
			or floor_scale < 0.5 or floor_scale > current_scale \
			or gpu_ms < 0.0 or gpu_ms > 80.0 \
			or target_ms < 5.0 or target_ms > 40.0 \
			or required_frames < 1 or required_frames > 10 \
			or consecutive_frames < 0 or consecutive_frames > 1000:
		return -1.0
	if gpu_ms < maxf(38.0, target_ms * 1.75) \
			or consecutive_frames < required_frames \
			or current_scale <= floor_scale:
		return current_scale
	var projected: float = current_scale * sqrt(target_ms / gpu_ms)
	var step_limited: float = maxf(current_scale - 0.12, projected)
	var quantized: float = roundf(step_limited * 100.0) / 100.0
	return minf(current_scale, maxf(floor_scale, quantized))
