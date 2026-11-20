extends RefCounted
## Native far-only cinema focus preserves gameplay clarity and eye adaptation.
const DOF = preload("res://scripts/client/graphics_cinematic_dof.gd")
const Eye = preload("res://scripts/client/graphics_eye_adaptation.gd")
const Atmosphere = preload("res://scripts/client/atmosphere.gd")
const Main = preload("res://scripts/client/online_main.gd")


func run(t) -> void:
	t.current = "cinematic focus has a strict renderer and quality budget"
	for method in ["gl_compatibility", "mobile", "unknown", ""]:
		for tier in 4:
			t.check(not bool(DOF.settings(tier, method, 21.0)["enabled"]),
				"unsupported renderer never starts a depth blur pass")
	for tier in [0, 1]:
		t.check(not bool(DOF.settings(tier, "forward_plus", 21.0)["enabled"]),
			"Performance and Balanced preserve maximum sharpness")
	for tier in [2, 3]:
		t.check(bool(DOF.settings(tier, "forward_plus", 21.0)["enabled"]),
			"only High/Ultra Forward+ may use far depth of field")
	var high: Dictionary = DOF.settings(2, "forward_plus", 21.0)
	var ultra: Dictionary = DOF.settings(3, "forward_plus", 21.0)
	t.check(float(high["amount"]) > 0.0 and float(high["amount"]) <= 0.1,
		"High has just a hint of lens separation")
	t.check(float(ultra["amount"]) > float(high["amount"]) and
		float(ultra["amount"]) <= 0.15, "Ultra has a subtle cinematic lens")
	t.check(float(high["distance"]) > 21.0 + 24.0,
		"main player and nearby enemies remain sharp")
	t.check(float(ultra["distance"]) > 21.0 + 18.0,
		"Ultra still protects interactive foreground")
	t.check(float(high["transition"]) > 25.0 and
		float(ultra["transition"]) > 25.0, "no harsh blur band across terrain")

	t.current = "isometric zoom and photo-mode focus"
	var zoom_out: Dictionary = DOF.settings(3, "forward_plus", 48.0)
	t.check(float(zoom_out["distance"]) > float(ultra["distance"]),
		"zooming out moves the focus boundary to protect the player")
	var photo: Dictionary = DOF.settings(3, "forward_plus", 21.0, true)
	t.check(float(photo["distance"]) < float(ultra["distance"]),
		"photo orbit narrows the far-focus plane")
	t.check(float(photo["amount"]) > float(ultra["amount"]),
		"photo mode gets stronger controlled background bokeh")
	t.check(float(photo["amount"]) <= 0.2, "photo mode avoids excessive blur")
	for camera_distance in [-100.0, 0.0, 20.0, 100.0, 10000.0, INF]:
		var p: Dictionary = DOF.settings(3, "forward_plus", camera_distance)
		t.check(is_finite(float(p["distance"])) and
			float(p["distance"]) >= 44.0 and float(p["distance"]) <= 230.0,
			"invalid or extreme camera distances stay safe and bounded")
	t.eq(DOF.settings(-10, "forward_plus", 21.0),
		DOF.settings(0, "forward_plus", 21.0),
		"unknown low quality is clamped")
	t.eq(DOF.settings(99, "forward_plus", 21.0),
		DOF.settings(3, "forward_plus", 21.0),
		"unknown high quality is clamped")

	t.current = "native camera attributes retain auto-exposure and reversibility"
	var world := WorldEnvironment.new()
	Eye.apply(world, 3, "forward_plus")
	var attr := world.camera_attributes as CameraAttributesPractical
	t.check(attr != null, "same persistent camera resource powers both effects")
	if attr == null:
		world.free()
		return
	var initial_iso: float = attr.auto_exposure_max_sensitivity
	t.check(attr.auto_exposure_enabled, "Ultra eye adaptation is active")
	DOF.apply(world, 3, "forward_plus", 21.0)
	t.check(attr.dof_blur_far_enabled and not attr.dof_blur_near_enabled,
		"native depth-of-field is far-only")
	t.near(attr.dof_blur_far_distance, float(ultra["distance"]), 0.001,
		"native far distance matches game focus budget")
	t.near(attr.dof_blur_amount, float(ultra["amount"]), 0.001,
		"native blur is constrained to the cinematic budget")
	t.check(attr.auto_exposure_enabled and world.camera_attributes == attr,
		"DOF cannot reset auto-exposure or replace resource")
	t.near(attr.auto_exposure_max_sensitivity, initial_iso, 0.0001,
		"cinema focus preserves Ultra ISO cap")
	DOF.apply(world, 3, "forward_plus", 48.0)
	t.check(attr.dof_blur_far_distance > float(ultra["distance"]),
		"live camera zoom moves native depth plane")
	DOF.apply(world, 3, "forward_plus", 21.0, true)
	t.near(attr.dof_blur_amount, float(photo["amount"]), 0.001,
		"photo mode updates native bokeh without new material")
	DOF.apply(world, 3, "gl_compatibility", 21.0)
	t.check(not attr.dof_blur_far_enabled and not attr.dof_blur_near_enabled,
		"renderer fallback immediately releases DOF work")
	t.check(attr.auto_exposure_enabled,
		"DOF fallback never modifies exposure (owned by Eye)")
	DOF.apply(world, 2, "forward_plus", 21.0)
	t.check(attr.dof_blur_far_enabled, "High reenables gentle far blur")
	DOF.apply(world, 0, "forward_plus", 21.0)
	t.check(not attr.dof_blur_far_enabled,
		"Performance restores the sharp low-cost rendering path")
	DOF.apply(null, 3, "forward_plus", 21.0)
	t.check(true, "missing world environment is safe")
	world.free()

	t.current = "integration in real shared atmosphere and main camera"
	var atmo: String = (Atmosphere as Script).source_code
	var main: String = (Main as Script).source_code
	t.check(atmo.contains("GraphicsEyeAdaptation.apply(world_environment") and
		atmo.contains("GraphicsCinematicDof.apply(world_environment"),
		"atmosphere applies depth of field after eye-adaptation profile")
	t.check(main.contains("GraphicsCinematicDof.apply(atmosphere.world_environment"),
		"gameplay and photo cameras adjust DOF from real camera distance")
	t.check(main.contains("camera_fx.photo_active") and
		main.contains("_dof_elapsed >= 0.35"),
		"photo zoom changes are batched at a low update rate")
	t.check(main.contains("post.layer = -10") and
		main.contains("camera_fx.setup(camera)"),
		"existing post effects and CanvasLayer HUD are unaffected")
