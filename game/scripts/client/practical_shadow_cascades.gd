extends RefCounted
## PSSM quality policy for outdoor sun shadows. This chooses only the depth
## partition; it does not change shadow-map resolution, cascade count or
## GPU sampling. High/Ultra use the native quantized logarithmic/uniform blend.
## The existing Godot split properties stay the fallback for stock engines.

const NEAR_PLANE := 0.35


static func plan(level: int, renderer: String, shadow_distance: float) -> Dictionary:
	var tier: int = clampi(level, 0, 3)
	var enabled: bool = renderer == "forward_plus" and tier >= 2 \
		and is_finite(shadow_distance) and shadow_distance >= 8.0 \
		and shadow_distance <= 8192.0
	return {
		"enabled": enabled,
		"near": NEAR_PLANE,
		"far": shadow_distance if enabled else 0.0,
		"lambda": 0.68 if tier == 2 else 0.62,
	}


## Return true if the new native API handled the plan. Repeated requests
## are valid and idempotent; there is no fallback upload in that case.
static func try_apply(sun: DirectionalLight3D, level: int, renderer: String) -> bool:
	if sun == null:
		return false
	var p: Dictionary = plan(level, renderer, sun.directional_shadow_max_distance)
	if not bool(p["enabled"]) or not sun.has_method("configure_practical_shadow_cascades"):
		return false
	return bool(sun.call("configure_practical_shadow_cascades",
		float(p["near"]), float(p["far"]), float(p["lambda"])))
