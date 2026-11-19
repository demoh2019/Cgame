# Regression: broadphase AABBs overlap, but rotated thin shapes do not.
# Verify persistent separated pairs remain stationary, then translate one
# body into true contact and check that the cache is invalidated.
# Run: godot --headless --path tests/stress --script res://physics_contact_separation_cache_regression.gd
extends SceneTree


const PAIR_COUNT := 12
const HOLD_FRAMES := 30
const CONTACT_FRAMES := 45
const ROTATION := PI / 4.0
const LANE_SPACING := 180.0
const SEPARATION := 20.0
const OVERLAP_OFFSET := 2.0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var results: Array[Dictionary] = []
	results.append(await _exercise_2d())
	results.append(await _exercise_3d())
	var failures := 0
	for result in results:
		print("SEPARATED_NARROWPHASE_CACHE:" + JSON.stringify(result))
		if not bool(result.get("valid", false)):
			failures += 1
	if failures > 0:
		printerr("Negative contact recycling regression failed (%d dimension(s))." % failures)
		quit(1)
	else:
		print("Negative contact recycling regression passed for 2D and 3D.")
		quit(0)


func _exercise_2d() -> Dictionary:
	var server := PhysicsServer2D
	var space := server.space_create()
	var shape := server.rectangle_shape_create()
	# 2D box shape data is half-size; AABB x/y spans overlap under 45 degrees,
	# despite a 20-unit gap along the narrow side of the boxes.
	server.shape_set_data(shape, Vector2(60.0, 6.0))
	var perpendicular := Vector2(-sin(ROTATION), cos(ROTATION))
	var statics: Array[RID] = []
	var dynamics: Array[RID] = []
	var expected: Array[Vector2] = []
	for i in range(PAIR_COUNT):
		var origin := Vector2(float(i) * LANE_SPACING, 0.0)
		var static_body := server.body_create()
		server.body_set_mode(static_body, server.BODY_MODE_STATIC)
		server.body_add_shape(static_body, shape)
		server.body_set_state(static_body, server.BODY_STATE_TRANSFORM, Transform2D(ROTATION, origin))
		server.body_set_space(static_body, space)
		statics.append(static_body)

		var dynamic_body := server.body_create()
		server.body_set_mode(dynamic_body, server.BODY_MODE_RIGID)
		server.body_add_shape(dynamic_body, shape)
		server.body_set_param(dynamic_body, server.BODY_PARAM_GRAVITY_SCALE, 0.0)
		server.body_set_state(dynamic_body, server.BODY_STATE_CAN_SLEEP, false)
		var position := origin + perpendicular * SEPARATION
		server.body_set_state(dynamic_body, server.BODY_STATE_TRANSFORM, Transform2D(ROTATION, position))
		server.body_set_space(dynamic_body, space)
		dynamics.append(dynamic_body)
		expected.append(position)

	server.space_set_active(space, true)
	var valid := true
	var peak_pairs := 0
	for frame in range(HOLD_FRAMES):
		await physics_frame
		peak_pairs = maxi(peak_pairs, int(Performance.get_monitor(Performance.PHYSICS_2D_COLLISION_PAIRS)))
		for i in range(PAIR_COUNT):
			var pose: Transform2D = server.body_get_state(dynamics[i], server.BODY_STATE_TRANSFORM)
			var velocity: Vector2 = server.body_get_state(dynamics[i], server.BODY_STATE_LINEAR_VELOCITY)
			if not pose.origin.is_finite() or not velocity.is_finite() or pose.origin.distance_to(expected[i]) > 0.01:
				valid = false
				break
		if not valid:
			break

	# A changed relative offset must invalidate the saved negative result.
	# The new 10-unit overlap is well above the penetration allowance.
	for i in range(PAIR_COUNT):
		expected[i] -= perpendicular * (SEPARATION - OVERLAP_OFFSET)
		server.body_set_state(dynamics[i], server.BODY_STATE_TRANSFORM, Transform2D(ROTATION, expected[i]))
	var moved_after_overlap := false
	if valid:
		for frame in range(CONTACT_FRAMES):
			await physics_frame
			for i in range(PAIR_COUNT):
				var pose: Transform2D = server.body_get_state(dynamics[i], server.BODY_STATE_TRANSFORM)
				var velocity: Vector2 = server.body_get_state(dynamics[i], server.BODY_STATE_LINEAR_VELOCITY)
				if not pose.origin.is_finite() or not velocity.is_finite() or velocity.length_squared() > 100000000.0:
					valid = false
					break
				if pose.origin.distance_to(expected[i]) > 0.5:
					moved_after_overlap = true
			if not valid:
				break

	server.space_set_active(space, false)
	for body in dynamics:
		server.free_rid(body)
	for body in statics:
		server.free_rid(body)
	server.free_rid(shape)
	server.free_rid(space)
	return {
		"dimension": "2D", "pairs": PAIR_COUNT, "peak_broadphase_pairs": peak_pairs,
		"moved_after_overlap": moved_after_overlap,
		"valid": valid and peak_pairs >= 6 and moved_after_overlap,
	}


func _exercise_3d() -> Dictionary:
	var server := PhysicsServer3D
	var space := server.space_create()
	var shape := server.box_shape_create()
	# 3D box shape data uses full dimensions.
	server.shape_set_data(shape, Vector3(120.0, 12.0, 10.0))
	var perpendicular := Vector3(-sin(ROTATION), cos(ROTATION), 0.0)
	var basis := Basis(Vector3(0.0, 0.0, 1.0), ROTATION)
	var statics: Array[RID] = []
	var dynamics: Array[RID] = []
	var expected: Array[Vector3] = []
	for i in range(PAIR_COUNT):
		var origin := Vector3(float(i) * LANE_SPACING, 0.0, 0.0)
		var static_body := server.body_create()
		server.body_set_mode(static_body, server.BODY_MODE_STATIC)
		server.body_add_shape(static_body, shape)
		server.body_set_state(static_body, server.BODY_STATE_TRANSFORM, Transform3D(basis, origin))
		server.body_set_space(static_body, space)
		statics.append(static_body)

		var dynamic_body := server.body_create()
		server.body_set_mode(dynamic_body, server.BODY_MODE_RIGID)
		server.body_add_shape(dynamic_body, shape)
		server.body_set_param(dynamic_body, server.BODY_PARAM_GRAVITY_SCALE, 0.0)
		server.body_set_state(dynamic_body, server.BODY_STATE_CAN_SLEEP, false)
		var position := origin + perpendicular * SEPARATION
		server.body_set_state(dynamic_body, server.BODY_STATE_TRANSFORM, Transform3D(basis, position))
		server.body_set_space(dynamic_body, space)
		dynamics.append(dynamic_body)
		expected.append(position)

	server.space_set_active(space, true)
	var valid := true
	var peak_pairs := 0
	for frame in range(HOLD_FRAMES):
		await physics_frame
		peak_pairs = maxi(peak_pairs, int(Performance.get_monitor(Performance.PHYSICS_3D_COLLISION_PAIRS)))
		for i in range(PAIR_COUNT):
			var pose: Transform3D = server.body_get_state(dynamics[i], server.BODY_STATE_TRANSFORM)
			var velocity: Vector3 = server.body_get_state(dynamics[i], server.BODY_STATE_LINEAR_VELOCITY)
			if not pose.origin.is_finite() or not velocity.is_finite() or pose.origin.distance_to(expected[i]) > 0.01:
				valid = false
				break
		if not valid:
			break

	for i in range(PAIR_COUNT):
		expected[i] -= perpendicular * (SEPARATION - OVERLAP_OFFSET)
		server.body_set_state(dynamics[i], server.BODY_STATE_TRANSFORM, Transform3D(basis, expected[i]))
	var moved_after_overlap := false
	if valid:
		for frame in range(CONTACT_FRAMES):
			await physics_frame
			for i in range(PAIR_COUNT):
				var pose: Transform3D = server.body_get_state(dynamics[i], server.BODY_STATE_TRANSFORM)
				var velocity: Vector3 = server.body_get_state(dynamics[i], server.BODY_STATE_LINEAR_VELOCITY)
				if not pose.origin.is_finite() or not velocity.is_finite() or velocity.length_squared() > 100000000.0:
					valid = false
					break
				if pose.origin.distance_to(expected[i]) > 0.5:
					moved_after_overlap = true
			if not valid:
				break

	server.space_set_active(space, false)
	for body in dynamics:
		server.free_rid(body)
	for body in statics:
		server.free_rid(body)
	server.free_rid(shape)
	server.free_rid(space)
	return {
		"dimension": "3D", "pairs": PAIR_COUNT, "peak_broadphase_pairs": peak_pairs,
		"moved_after_overlap": moved_after_overlap,
		"valid": valid and peak_pairs >= 6 and moved_after_overlap,
	}
