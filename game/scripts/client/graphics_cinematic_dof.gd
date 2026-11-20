extends RefCounted
## Thin-lens-inspired selective focus using Godot's *native* depth-of-field.
## Far-only and Forward+ High/Ultra: player, nearby enemies and UI remain sharp.
## One persistent CameraAttributesPractical owns both DOF and eye adaptation.
## No duplicate fullscreen CanvasItem blur or camera-dependent material copies.


## Camera distance to the character is supplied by the active isometric orbit.
## Keep the entire interactive vicinity in focus even while zooming or riding.
static func settings(level: int, renderer: String, subject_distance: float,
		photo_mode: bool = false) -> Dictionary:
	var tier: int = clampi(level, 0, 3)
	var enabled: bool = renderer == "forward_plus" and tier >= 2
	var focus_distance: float = clampf(subject_distance, 1.0, 180.0) if is_finite(subject_distance) else 22.0
	var margin: float = 34.0 if tier == 2 else 25.0
	var threshold: float = 52.0 if tier == 2 else 44.0
	var transition: float = 42.0 if tier == 2 else 34.0
	var amount: float = 0.08 if tier == 2 else 0.14
	if photo_mode and enabled:
		# Photos have a tighter, still readable background blur.
		margin = 27.0 if tier == 2 else 20.0
		threshold = 43.0 if tier == 2 else 36.0
		transition = 31.0 if tier == 2 else 25.0
		amount = 0.11 if tier == 2 else 0.18
	return {
		"enabled": enabled,
		"distance": maxf(focus_distance + margin, threshold),
		"transition": transition,
		"amount": amount if enabled else 0.0,
	}


## Coalesced native call on the fork. On stock Godot the same feature uses
## ordinary setters, but only after a material change in distance/quality.
static func apply(world: WorldEnvironment, level: int, renderer: String,
		subject_distance: float = 22.0, photo_mode: bool = false) -> void:
	if world == null:
		return
	var p: Dictionary = settings(level, renderer, subject_distance, photo_mode)
	var attr: CameraAttributesPractical = world.camera_attributes as CameraAttributesPractical
	if attr == null:
		attr = CameraAttributesPractical.new()
		world.camera_attributes = attr
	var enabled: bool = bool(p["enabled"])
	if not enabled:
		if attr.dof_blur_far_enabled or attr.dof_blur_near_enabled:
			if attr.has_method("configure_cinematic_dof"):
				attr.call("configure_cinematic_dof", false, 52.0, 42.0, 0.0)
			else:
				attr.dof_blur_near_enabled = false
				attr.dof_blur_far_enabled = false
		return
	var distance: float = float(p["distance"])
	var transition: float = float(p["transition"])
	var amount: float = float(p["amount"])
	# 1.2 metres hysteresis: normal camera damping cannot flood the rendering
	# thread with focus changes each frame. The active profile is still exact.
	if attr.dof_blur_far_enabled and not attr.dof_blur_near_enabled 			and absf(attr.dof_blur_far_distance - distance) < 1.2 			and is_equal_approx(attr.dof_blur_far_transition, transition) 			and is_equal_approx(attr.dof_blur_amount, amount):
		return
	if attr.has_method("configure_cinematic_dof"):
		attr.call("configure_cinematic_dof", true, distance, transition, amount)
	else:
		# Stock Godot fallback. Configure everything first, enable far last.
		attr.dof_blur_near_enabled = false
		attr.dof_blur_far_distance = distance
		attr.dof_blur_far_transition = transition
		attr.dof_blur_amount = amount
		attr.dof_blur_far_enabled = true
