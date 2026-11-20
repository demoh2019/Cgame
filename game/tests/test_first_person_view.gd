extends RefCounted
## First-person look and movement must agree with the server's yaw convention.
const FirstPersonView = preload("res://scripts/client/first_person_view.gd")


func run(t) -> void:
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
