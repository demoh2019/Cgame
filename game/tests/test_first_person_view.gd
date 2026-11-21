extends RefCounted
## First-person look and movement must agree with the server's yaw convention.
const FirstPersonView = preload("res://scripts/client/first_person_view.gd")
const FirstPersonViewmodel = preload("res://scripts/client/first_person_viewmodel.gd")
const UiSettings = preload("res://scripts/client/ui_settings.gd")


func run(t) -> void:
	_feel(t)
	t.current = "W walks where the camera looks"
	for yaw in [0.0, PI * 0.5, PI, -PI * 0.5, 0.7, -2.3]:
		var world: Vector2 = FirstPersonView.to_world_move(Vector2(0, -1), yaw)
		t.near(world.x, sin(yaw), 0.0001, "forward x at yaw %.2f" % yaw)
		t.near(world.y, cos(yaw), 0.0001, "forward z at yaw %.2f" % yaw)
		var cam := FirstPersonView.camera_transform(Vector3.ZERO, yaw, 0.0, 1.6)
		var look: Vector3 = -cam.basis.z
		t.near(look.x, sin(yaw), 0.0001, "camera looks along facing x")
		t.near(look.z, cos(yaw), 0.0001, "camera looks along facing z")
		var strafe: Vector2 = FirstPersonView.to_world_move(Vector2(1, 0), yaw)
		t.near(strafe.x, cam.basis.x.x, 0.0001, "D strafes toward camera right x")
		t.near(strafe.y, cam.basis.x.z, 0.0001, "D strafes toward camera right z")

	t.current = "default top-down view keeps its mapping"
	# Facing away from the default camera (-Z), FP movement equals the old world mapping.
	var same: Vector2 = FirstPersonView.to_world_move(Vector2(0.6, -0.8), PI)
	t.near(same.x, 0.6, 0.0001, "right stays +X")
	t.near(same.y, -0.8, 0.0001, "forward stays -Z")
	t.check(FirstPersonView.to_world_move(Vector2(1, -1), 0.3).length() <= 1.0001, "diagonal stays normalized")

	t.current = "mouse look turns the way the mouse moves and clamps pitch"
	var turned: Vector2 = FirstPersonView.apply_look(PI, 0.0, Vector2(100, 0))
	var cam_before := FirstPersonView.camera_transform(Vector3.ZERO, PI, 0.0, 1.6)
	var new_look: Vector3 = -FirstPersonView.camera_transform(Vector3.ZERO, turned.x, 0.0, 1.6).basis.z
	t.check(new_look.dot(cam_before.basis.x) > 0.0, "moving the mouse right turns right")
	var down: Vector2 = FirstPersonView.apply_look(0.0, 0.0, Vector2(0, 100000))
	t.near(down.y, -FirstPersonView.MAX_PITCH, 0.0001, "pitch cannot flip over")
	var cam_down := FirstPersonView.camera_transform(Vector3.ZERO, 0.0, -0.5, 1.6)
	t.check((-cam_down.basis.z).y < 0.0, "negative pitch looks down")
	var wrapped: Vector2 = FirstPersonView.apply_look(PI - 0.01, 0.0, Vector2(-100, 0))
	t.check(wrapped.x >= -PI and wrapped.x <= PI, "yaw stays wrapped")

	t.current = "eyes sit at a sensible height"
	t.check(FirstPersonView.eye_height(true, false) < FirstPersonView.eye_height(false, false), "crouching lowers the eyes")
	t.check(FirstPersonView.eye_height(false, true) > FirstPersonView.eye_height(false, false), "riding raises the eyes")
	t.near(FirstPersonView.camera_transform(Vector3(1, 2, 3), 0.0, 0.0, 1.6).origin.y, 3.6, 0.0001, "camera at feet + eye height")

	t.current = "cosmetic jump"
	t.eq(FirstPersonView.jump_offset(-1.0), 0.0, "on the ground")
	t.near(FirstPersonView.jump_offset(FirstPersonView.JUMP_SECONDS * 0.5), FirstPersonView.JUMP_HEIGHT, 0.0001, "apex at mid-jump")
	t.eq(FirstPersonView.jump_offset(FirstPersonView.JUMP_SECONDS), 0.0, "lands again")


func _feel(t) -> void:
	t.current = "first-person lens and look settings"
	t.near(FirstPersonView.fov(75.0), 75.0, 0.001, "default lens")
	t.near(FirstPersonView.fov(10.0), FirstPersonView.FOV_MIN, 0.001, "lens clamped low")
	t.near(FirstPersonView.fov(NAN), FirstPersonView.FOV_DEFAULT, 0.001, "NaN falls back to default")
	t.check(FirstPersonView.fov(75.0) > 38.0 * 1.5, "first person is far wider than the isometric 38 degree lens")
	var s: Vector2 = FirstPersonView.look_sensitivity(2.0, false)
	t.near(s.x, FirstPersonView.MOUSE_SENSITIVITY * 2.0, 1e-7, "sensitivity multiplier")
	t.check(FirstPersonView.look_sensitivity(1.0, true).y < 0.0, "invert Y flips pitch")
	var up: Vector2 = FirstPersonView.apply_look_scaled(0.0, 0.0, Vector2(0, -100), FirstPersonView.look_sensitivity(1.0, false))
	var inv: Vector2 = FirstPersonView.apply_look_scaled(0.0, 0.0, Vector2(0, -100), FirstPersonView.look_sensitivity(1.0, true))
	t.check(up.y > 0.0 and inv.y < 0.0, "mouse up looks up, inverted looks down")
	t.near(FirstPersonView.apply_look_scaled(0.0, 1.4, Vector2(0, -10000), Vector2(0.01, 0.01)).y, FirstPersonView.MAX_PITCH, 1e-5, "pitch clamped")

	t.current = "head bob, lean, landing"
	t.eq(FirstPersonView.head_bob(1.0, 0.0), Vector2.ZERO, "no bob standing still")
	t.eq(FirstPersonView.head_bob(1.0, 4.0, false), Vector2.ZERO, "comfort option disables bob")
	t.check(FirstPersonView.head_bob(PI * 0.5, 4.0).length() > 0.0, "bob while walking")
	t.check(absf(FirstPersonView.head_bob(PI * 0.5, 4.0).y) <= FirstPersonView.BOB_HEIGHT * 1.5, "bob stays small")
	var p := FirstPersonView.advance_bob_phase(0.0, FirstPersonView.BOB_STRIDE, 0.5)
	t.near(p, PI, 0.0001, "half a stride is half a cycle")
	t.check(FirstPersonView.advance_bob_phase(6.0, 4.0, 1.0) < TAU, "phase wraps")
	t.check(FirstPersonView.strafe_roll(4.0) < 0.0 and FirstPersonView.strafe_roll(-4.0) > 0.0, "lean into the strafe")
	t.near(absf(FirstPersonView.strafe_roll(100.0)), FirstPersonView.MAX_ROLL, 1e-6, "lean clamped")
	t.near(FirstPersonView.strafe_roll(4.0, false), 0.0, 1e-6, "comfort option disables lean")
	t.near(FirstPersonView.landing_dip(-1.0), 0.0, 1e-6, "no dip off the ground event")
	t.check(FirstPersonView.landing_dip(0.1) < 0.0, "camera dips on landing")
	t.near(FirstPersonView.landing_dip(0.35), 0.0, 1e-6, "dip ends")

	t.current = "crosshair and held item"
	t.check(FirstPersonView.crosshair_spread(6.0, false) > FirstPersonView.crosshair_spread(0.0, false), "spread opens with speed")
	t.check(FirstPersonView.crosshair_spread(0.0, true) > FirstPersonView.crosshair_spread(0.0, false), "spread opens in the air")
	var cross := FirstPersonView.make_crosshair()
	FirstPersonView.layout_crosshair(cross, 10.0, 1.0)
	t.check((cross.get_child(1) as ColorRect).position.x >= 10.0, "right bar moves out with the gap")
	t.check((cross.get_child(4) as ColorRect).color.g < 0.5, "hit marker tints the crosshair red")
	cross.free()
	var sway := FirstPersonView.viewmodel_sway(Vector2(10000, -10000))
	t.check(absf(sway.x) <= 0.0901 and absf(sway.y) <= 0.0701, "sway clamped")
	t.eq(FirstPersonView.attack_pose(-1.0, true), Vector3.ZERO, "no attack pose idle")
	t.check(FirstPersonView.attack_pose(0.05, true).x > 0.0, "gun kicks back toward the eye")
	t.eq(FirstPersonView.attack_pose(0.3, true), Vector3.ZERO, "recoil settles")
	t.check(FirstPersonView.attack_pose(0.1, false).z < 0.0 and FirstPersonView.attack_pose(0.25, false).z > 0.0, "melee winds up then slashes across")
	t.eq(FirstPersonView.attack_pose(0.5, false), Vector3.ZERO, "swing settles")

	t.current = "shadow-only body"
	var body := Node3D.new()
	var mesh := MeshInstance3D.new()
	body.add_child(mesh)
	var off := MeshInstance3D.new()
	off.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	body.add_child(off)
	FirstPersonView.set_body_shadow_only(body, true)
	t.eq(mesh.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY, "body becomes shadow only")
	t.eq(off.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "shadowless parts stay hidden entirely")
	FirstPersonView.set_body_shadow_only(body, true)
	FirstPersonView.set_body_shadow_only(body, false)
	t.eq(mesh.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_ON, "restored after repeated calls")
	body.free()

	t.current = "held item models"
	t.check(FirstPersonViewmodel.make_item("") == null, "empty hands")
	t.check(FirstPersonViewmodel.make_item("not_a_weapon_9") == null, "unknown item has no model")
	var rod := FirstPersonViewmodel.make_item("fishing_rod")
	t.check(rod != null, "fishing rod is built in code")
	if rod != null:
		for g in rod.find_children("*", "GeometryInstance3D", true, false):
			t.eq((g as GeometryInstance3D).cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "held item never casts shadows")
		rod.free()
	t.near(UiSettings.sanitize("fp_fov", 500.0), 110.0, 0.001, "fov setting clamped")
	t.near(UiSettings.sanitize("mouse_sensitivity", "x"), 1.0, 0.001, "bad sensitivity falls back")
	t.eq(UiSettings.sanitize("invert_y", 1), true, "invert flag is a bool")
