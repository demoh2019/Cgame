extends RefCounted
## Screen-space contact shadows use one engine-native, half-resolution
## SSAO target. The quality profile changes only when graphics quality or
## renderer backend changes; this is not an extra postprocess pass.

static var _last_plan: Dictionary = {}


static func settings(level: int, method: String) -> Dictionary:
	var tier: int = clampi(level, 0, 3)
	var enabled: bool = method == "forward_plus" and tier >= 2
	return {
		"quality": (
			RenderingServer.ENV_SSAO_QUALITY_HIGH if enabled and tier == 3
			else (RenderingServer.ENV_SSAO_QUALITY_MEDIUM if enabled
			else RenderingServer.ENV_SSAO_QUALITY_VERY_LOW)),
		"half_size": true,
		"blur_passes": 2,
		"adaptive_target": 0.5,
		"fadeout_from": 50.0,
		"fadeout_to": 300.0,
	}


static func needs_apply(previous: Dictionary, next: Dictionary) -> bool:
	return previous != next


static func apply(level: int, method: String) -> void:
	var plan: Dictionary = settings(level, method)
	if not needs_apply(_last_plan, plan):
		return
	RenderingServer.environment_set_ssao_quality(
		int(plan["quality"]), bool(plan["half_size"]),
		float(plan["adaptive_target"]), int(plan["blur_passes"]),
		float(plan["fadeout_from"]), float(plan["fadeout_to"]))
	_last_plan = plan
