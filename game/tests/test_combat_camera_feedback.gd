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

	t.current = "Unreal-style source-oriented camera trauma (visual only)"
	var directed_camera := Camera3D.new()
	t.check(directed_camera.has_method("add_directional_spatial_trauma"),
		"Cgame exposes optional impact orientation without a new scene node")
	t.check(directed_camera.has_method("get_shake_direction_impulse"),
		"native directional camera state can be inspected without moving the player")
	Feedback.apply(directed_camera, "hit_zombie",
		Vector3(2, 0, 0), Vector3.ZERO, 1.0)
	t.near(float(directed_camera.call("get_trauma")), 0.12 * Feedback.falloff(2.0, 0.6, 4.0),
		0.00001, "directional hit preserves the original spatial trauma strength")
	var hit_direction: Vector3 = directed_camera.call("get_shake_direction_impulse")
	t.check(hit_direction.x > 0.0 and absf(hit_direction.y) < 0.00001,
		"the camera kick points toward the world impact, not a random axis")
	t.check(hit_direction.length() <= 1.0,
		"directional impulse is bounded after source attenuation")
	directed_camera.call("set_trauma", 0.0)
	Feedback.apply(directed_camera, "flash_thrown",
		Vector3.ZERO, Vector3.ZERO, 1.0)
	t.near(float(directed_camera.call("get_trauma")), 0.25, 0.00001,
		"nondirectional flash keeps existing trauma semantics")
	t.eq(directed_camera.call("get_shake_direction_impulse"), Vector3.ZERO,
		"screen flash does not change directional camera kick")
	directed_camera.call("set_trauma", 0.0)
	Feedback.apply(directed_camera, "barricade_broken",
		Vector3(1, 0, 0), Vector3.ZERO, 0.5)
	t.check(float(directed_camera.call("get_trauma")) > 0.0,
		"barricade destruction uses directional impact with accessibility scaling")
	var barricade_direction: Vector3 = directed_camera.call("get_shake_direction_impulse")
	t.check(barricade_direction.x > 0.0,
		"barricade break points the camera toward the destruction")
	directed_camera.call("set_trauma", 0.0)
	Feedback.apply(directed_camera, "knockback", Vector3.ZERO, Vector3.ZERO, 0.0)
	t.eq(directed_camera.call("get_shake_direction_impulse"), Vector3.ZERO,
		"reduce-screen-shake setting disables directional and radial impulses")
	Feedback.apply(directed_camera, "knockback",
		Vector3(INF, 0, 0), Vector3.ZERO, 1.0)
	t.eq(directed_camera.call("get_shake_direction_impulse"), Vector3.ZERO,
		"malformed server event cannot inject invalid camera displacement")
	directed_camera.free()

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
