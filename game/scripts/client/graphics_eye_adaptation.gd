extends RefCounted
## Native Godot camera exposure, limited to premium Forward+ renderers.
## Uses one persistent CameraAttributesPractical on the shared WorldEnvironment.
## It must not override the artist-driven ACES/day-night exposure curve.

static func settings(level: int, method: String) -> Dictionary:
	var tier: int = clampi(level, 0, 3)
	var enabled: bool = method == "forward_plus" and tier >= 2
	return {
		"enabled": enabled,
		# Narrow exposure bounds preserve nighttime darkness, warm sunsets
		# and the artist-authored cinematic tone map. Ultra has a little
		# extra latitude for moving between bright outdoors and bunkers.
		"min_sensitivity": 90.0 if tier == 2 else (80.0 if tier == 3 else 100.0),
		"max_sensitivity": 150.0 if tier == 2 else (200.0 if tier == 3 else 100.0),
		"speed": 0.65 if tier == 2 else (0.85 if tier == 3 else 0.5),
		"scale": 0.4,
	}


static func apply(world: WorldEnvironment, level: int, method: String) -> void:
	if world == null:
		return
	var p: Dictionary = settings(level, method)
	# Keep the same resource when switching quality. No camera/scene mesh
	# rebuild, no reinitialization every frame, and no DOF is activated.
	var attributes: CameraAttributesPractical = world.camera_attributes as CameraAttributesPractical
	if attributes == null:
		attributes = CameraAttributesPractical.new()
		world.camera_attributes = attributes
	attributes.auto_exposure_min_sensitivity = float(p["min_sensitivity"])
	attributes.auto_exposure_max_sensitivity = float(p["max_sensitivity"])
	attributes.auto_exposure_speed = float(p["speed"])
	attributes.auto_exposure_scale = float(p["scale"])
	attributes.dof_blur_near_enabled = false
	attributes.dof_blur_far_enabled = false
	# Apply enabled last so live renderer switches never use stale limits.
	attributes.auto_exposure_enabled = bool(p["enabled"])
