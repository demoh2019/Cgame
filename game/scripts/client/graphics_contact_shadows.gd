extends RefCounted
## Cinematic screen-space contact shadows for the ONE existing sun/moon.
## The native Cgame renderer skips the depth prepass and SSCS GPU work when
## all eligible lights disable contact shadows. Not a new light or shadow map.
##
## Unreal and Unity HDRP use contact shadows to resolve small opaque objects
## that cannot contribute meaningful silhouettes in distant shadow cascades.
## This pass is expensive relative to a simple shadow lookup, so we reserve
## it for high-end Forward+ and tune softness for foliage and small rocks.


static func settings(level: int, rendering_method: String) -> Dictionary:
	var tier: int = clampi(level, 0, 3)
	var enabled: bool = rendering_method == "forward_plus" and tier >= 2
	return {
		"enabled": enabled,
		"blur": 0.65 if tier == 2 else (0.95 if tier == 3 else 1.0),
	}


## Idempotent quality switch; leaves the existing cascades, PCSS, sun color
## and dynamic shadow opacity untouched. Never run this once per frame.
static func apply(sun: DirectionalLight3D, level: int,
		rendering_method: String) -> void:
	if sun == null:
		return
	var policy: Dictionary = settings(level, rendering_method)
	var allowed: bool = bool(policy["enabled"])
	if sun.shadow_contact_shadows_allow != allowed:
		sun.shadow_contact_shadows_allow = allowed
	if allowed:
		var blur: float = float(policy["blur"])
		if absf(sun.shadow_contact_shadows_blur - blur) > 0.001:
			sun.shadow_contact_shadows_blur = blur
