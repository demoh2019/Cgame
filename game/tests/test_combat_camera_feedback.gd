extends RefCounted
## Validate cosmetic event strength independently from server-authoritative combat.
const Feedback = preload("res://scripts/client/combat_camera_feedback.gd")


func run(t) -> void:
	t.current = "world-space combat impact falloff"
	t.near(Feedback.falloff(0.0, 1.0, 9.0), 1.0, 0.0001,
		"nearby impacts retain full feedback")
	t.near(Feedback.falloff(1.0, 1.0, 9.0), 1.0, 0.0001,
		"inner radius never dims the strike")
	t.near(Feedback.falloff(5.0, 1.0, 9.0), 0.5, 0.0001,
		"halfway between radii produces half-strength impulse")
	t.near(Feedback.falloff(9.0, 1.0, 9.0), 0.0, 0.0001,
		"outside impacts never shake the local camera")
	t.near(Feedback.falloff(100.0, 1.0, 9.0), 0.0, 0.0001,
		"distant combat is visually quiet")
	t.check(Feedback.falloff(1.001, 1.0, 9.0) > 0.999,
		"near-distance threshold is smooth")
	t.check(Feedback.falloff(8.999, 1.0, 9.0) < 0.001,
		"far-distance threshold is smooth")
	t.eq(Feedback.falloff(INF, 1.0, 9.0), 0.0,
		"invalid event distance cannot move the camera")
	t.eq(Feedback.falloff(2.0, 9.0, 1.0), 0.0,
		"reversed radii cannot create invalid camera transforms")
	t.eq(Feedback.falloff(-1.0, 1.0, 9.0), 0.0,
		"negative event distance is rejected")

	t.current = "actual native Camera3D server-event feedback"
	var camera := Camera3D.new()
	t.check(camera.has_method("add_spatial_trauma"),
		"Cgame engine exposes a shared native spatial trauma API")
	Feedback.apply(camera, "flash_thrown", Vector3.ZERO, Vector3.ZERO, 1.0)
	t.near(float(camera.call("get_trauma")), 0.25, 0.0001,
		"nearby flash explosion causes a bounded native impulse")
	camera.call("set_trauma", 0.0)
	Feedback.apply(camera, "flash_thrown", Vector3(100.0, 0.0, 0.0), Vector3.ZERO, 1.0)
	t.near(float(camera.call("get_trauma")), 0.0, 0.0001,
		"distant flash does not shake the view")
	Feedback.apply(camera, "flash_thrown", Vector3.ZERO, Vector3.ZERO, 0.0)
	t.near(float(camera.call("get_trauma")), 0.0, 0.0001,
		"accessibility reduced shake setting can fully disable feedback")
	Feedback.apply(camera, "flash_thrown", Vector3.ZERO, Vector3.ZERO, 0.5)
	t.near(float(camera.call("get_trauma")), 0.125, 0.0001,
		"accessibility scales server-event visuals without affecting damage")
	var previous: float = float(camera.call("get_trauma"))
	Feedback.apply(camera, "flash_thrown", Vector3(INF, 0.0, 0.0), Vector3.ZERO, 1.0)
	Feedback.apply(camera, "unknown_event", Vector3.ZERO, Vector3.ZERO, 1.0)
	t.near(float(camera.call("get_trauma")), previous, 0.0001,
		"invalid coordinates and unknown events cannot create camera shake")
	camera.free()

	t.current = "playable online combat cue integration"
	var online: String = FileAccess.get_file_as_string(
		"res://scripts/client/online_main.gd")
	for cue in ["hit_zombie", "zombie_died", "knockback", "flash_thrown", "barricade_broken"]:
		t.check(Feedback.PROFILES.has(cue),
			"impact %s has a finite bounded strength and range" % cue)
		t.check(online.contains('CombatCameraFeedback.apply(camera, "' + cue + '"'),
			"online combat triggers spatial feedback for %s" % cue)
	t.check(online.contains("UiSettings.shake_scale()"),
		"existing reduce-screen-shake preference is still respected")
