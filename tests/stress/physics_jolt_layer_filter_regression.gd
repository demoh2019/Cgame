extends SceneTree
## Native Jolt collision-mask regression for the packed body-pair filter.
## Bodies are deliberately isolated along X, and gravity is disabled so
## falling-through versus stopped-by-floor is easy to distinguish.

const PREFIX := "JOLT_LAYER_FILTER_RESULT:"
const FRAMES := 90

const CASES := [
	{"name": "bidirectional", "floor_layer": 1, "floor_mask": 2, "ball_layer": 2, "ball_mask": 1, "collide": true},
	{"name": "ball_selects_floor", "floor_layer": 1, "floor_mask": 0, "ball_layer": 2, "ball_mask": 1, "collide": true},
	{"name": "no_matching_bits", "floor_layer": 1, "floor_mask": 0, "ball_layer": 4, "ball_mask": 8, "collide": false},
	{"name": "high_layer_bits", "floor_layer": 1 << 20, "floor_mask": 0, "ball_layer": 2, "ball_mask": 1 << 20, "collide": true},
	{"name": "both_masks_empty", "floor_layer": 1, "floor_mask": 0, "ball_layer": 2, "ball_mask": 0, "collide": false},
]


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var space := PhysicsServer3D.space_create()
	PhysicsServer3D.space_set_active(space, true)
	var floor_shape := PhysicsServer3D.box_shape_create()
	PhysicsServer3D.shape_set_data(floor_shape, Vector3(3.5, 0.5, 3.5))
	var ball_shape := PhysicsServer3D.sphere_shape_create()
	PhysicsServer3D.shape_set_data(ball_shape, 0.45)

	var floors: Array[RID] = []
	var balls: Array[RID] = []
	for index in range(CASES.size()):
		var setup: Dictionary = CASES[index]
		var x := float(index) * 10.0

		var floor_body := PhysicsServer3D.body_create()
		PhysicsServer3D.body_set_mode(floor_body, PhysicsServer3D.BODY_MODE_STATIC)
		PhysicsServer3D.body_add_shape(floor_body, floor_shape)
		PhysicsServer3D.body_set_collision_layer(floor_body, int(setup["floor_layer"]))
		PhysicsServer3D.body_set_collision_mask(floor_body, int(setup["floor_mask"]))
		PhysicsServer3D.body_set_state(floor_body, PhysicsServer3D.BODY_STATE_TRANSFORM,
				Transform3D(Basis(), Vector3(x, -0.5, 0.0)))
		PhysicsServer3D.body_set_space(floor_body, space)
		floors.append(floor_body)

		var ball := PhysicsServer3D.body_create()
		PhysicsServer3D.body_set_mode(ball, PhysicsServer3D.BODY_MODE_RIGID)
		PhysicsServer3D.body_add_shape(ball, ball_shape)
		PhysicsServer3D.body_set_collision_layer(ball, int(setup["ball_layer"]))
		PhysicsServer3D.body_set_collision_mask(ball, int(setup["ball_mask"]))
		PhysicsServer3D.body_set_param(ball, PhysicsServer3D.BODY_PARAM_GRAVITY_SCALE, 0.0)
		PhysicsServer3D.body_set_state(ball, PhysicsServer3D.BODY_STATE_CAN_SLEEP, false)
		PhysicsServer3D.body_set_state(ball, PhysicsServer3D.BODY_STATE_TRANSFORM,
				Transform3D(Basis(), Vector3(x, 2.0, 0.0)))
		PhysicsServer3D.body_set_state(ball, PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY,
				Vector3(0.0, -3.0, 0.0))
		PhysicsServer3D.body_set_space(ball, space)
		balls.append(ball)

	for frame in range(FRAMES):
		await physics_frame

	var failed_cases: Array[String] = []
	var final_heights: Dictionary = {}
	for i in range(CASES.size()):
		var setup: Dictionary = CASES[i]
		var ball_transform: Transform3D = PhysicsServer3D.body_get_state(
				balls[i], PhysicsServer3D.BODY_STATE_TRANSFORM)
		var y := ball_transform.origin.y
		final_heights[String(setup["name"])] = y
		if not ball_transform.origin.is_finite():
			failed_cases.append(String(setup["name"]) + ": nonfinite transform")
		elif bool(setup["collide"]) and y < 0.1:
			failed_cases.append(String(setup["name"]) + ": fell through a matching floor")
		elif not bool(setup["collide"]) and y > -0.5:
			failed_cases.append(String(setup["name"]) + ": unexpected collision with an excluded floor")

	PhysicsServer3D.space_set_active(space, false)
	for body in balls:
		PhysicsServer3D.free_rid(body)
	for body in floors:
		PhysicsServer3D.free_rid(body)
	PhysicsServer3D.free_rid(ball_shape)
	PhysicsServer3D.free_rid(floor_shape)
	PhysicsServer3D.free_rid(space)

	print(PREFIX + JSON.stringify({
		"cases": CASES.size(),
		"frames": FRAMES,
		"final_heights": final_heights,
		"failed_cases": failed_cases,
	}))
	if failed_cases.is_empty():
		print("Jolt layer filter regression passed.")
		quit(0)
	else:
		for failure in failed_cases:
			printerr(failure)
		quit(1)
