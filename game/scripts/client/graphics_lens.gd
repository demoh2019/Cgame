extends RefCounted
## Native camera-lens finish (engine fork: Environment.lens_*), like the
## "Scene Fringe" and "Film Grain" settings of Unreal Engine 5 and Unity HDRP.
## Runs inside the existing Forward+ tonemap pass: no extra pass or render target.
## Chromatic aberration is applied in HDR before tonemapping, grain after it;
## the lens flare reuses the glow buffer, so it only appears where bloom does.

static func settings(level: int, rendering_method: String) -> Dictionary:
	var tier: int = clampi(level, 0, 3)
	if rendering_method != "forward_plus" or tier < 2:
		return {"chromatic_aberration": 0.0, "film_grain": 0.0, "lens_flare": 0.0, "motion_blur": 0.0, "vignette": 0.0}
	# Subtle on purpose: edge fringes and grain should be felt, not noticed.
	return {
		"chromatic_aberration": 0.35 if tier == 2 else 0.5,
		"film_grain": 0.18 if tier == 2 else 0.24,
		# UE-style image-based flare ghosts/halo from the bloom buffer (sun, lightning, fires).
		"lens_flare": 0.45 if tier == 2 else 0.6,
		# Per-pixel velocity blur (camera pans, running creatures, swinging weapons).
		# A short "shutter" keeps the top-down diorama readable while turning fast.
		"motion_blur": 0.3 if tier == 2 else 0.4,
		# Native optical cos^4 vignette in the HDR tonemap pass (UE5 Vignette Intensity);
		# replaces the flat canvas vignette of the grade pass on these tiers.
		"vignette": 0.4 if tier == 2 else 0.45,
	}


## Returns true when the engine draws the vignette natively (the grade pass must then skip its own).
static func apply(env: Environment, level: int, rendering_method: String) -> bool:
	if env == null or not ("lens_film_grain" in env):
		return false # Stock Godot without the fork's native lens effects.
	var profile: Dictionary = settings(level, rendering_method)
	env.set("lens_chromatic_aberration", float(profile["chromatic_aberration"]))
	env.set("lens_film_grain", float(profile["film_grain"]))
	if "lens_flare" in env:
		env.set("lens_flare", float(profile["lens_flare"]))
	if "motion_blur_amount" in env:
		env.set("motion_blur_amount", float(profile["motion_blur"]))
	if "lens_vignette" in env:
		env.set("lens_vignette", float(profile["vignette"]))
		return float(profile["vignette"]) > 0.0
	return false


## Subtle barrel distortion of a wide real lens (UE5 Lens Distortion, HDRP
## Lens Distortion). Applied in the existing canvas grade pass; kept small so
## the top-down playfield stays readable.
static func distortion(level: int, rendering_method: String) -> float:
	var tier: int = clampi(level, 0, 3)
	if tier < 2 or rendering_method == "gl_compatibility":
		return 0.0
	return 0.035 if tier == 2 else 0.05
