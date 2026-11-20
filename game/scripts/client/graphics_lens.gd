extends RefCounted
## Native camera-lens finish (engine fork: Environment.lens_*), like the
## "Scene Fringe" and "Film Grain" settings of Unreal Engine 5 and Unity HDRP.
## Runs inside the existing Forward+ tonemap pass: no extra pass or render target.
## Chromatic aberration is applied in HDR before tonemapping, grain after it.

static func settings(level: int, rendering_method: String) -> Dictionary:
	var tier: int = clampi(level, 0, 3)
	if rendering_method != "forward_plus" or tier < 2:
		return {"chromatic_aberration": 0.0, "film_grain": 0.0}
	# Subtle on purpose: edge fringes and grain should be felt, not noticed.
	return {
		"chromatic_aberration": 0.35 if tier == 2 else 0.5,
		"film_grain": 0.18 if tier == 2 else 0.24,
	}


static func apply(env: Environment, level: int, rendering_method: String) -> void:
	if env == null or not ("lens_film_grain" in env):
		return # Stock Godot without the fork's native lens effects.
	var profile: Dictionary = settings(level, rendering_method)
	env.set("lens_chromatic_aberration", float(profile["chromatic_aberration"]))
	env.set("lens_film_grain", float(profile["film_grain"]))
