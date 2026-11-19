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
	var space := PhysicsServer2D.space_create()
	var shape := PhysicsServer2D.rectangle_shape_create()
	# 2D box shape data is half-size; AABB x/y spans overlap under 45 degrees,
	# despite a 20-unit gap along the narrow side of the boxes.
	PhysicsServer2D.shape_set_data(shape, Vector2(60.0, 6.0))
	var perpendicular := Vector2(-sin(ROTATION), cos(ROTATION))
	var statics: Array[RID] = []
	var dynamics: Array[RID] = []
	var expected: Array[Vector2] = []
	for i in range(PAIR_COUNT):
		var origin := Vector2(float(i) * LANE_SPACING, 0.0)
		var static_body := PhysicsServer2D.body_create()
		PhysicsServer2D.body_set_mode(static_body, PhysicsServer2D.BODY_MODE_STATIC)
		PhysicsServer2D.body_add_shape(static_body, shape)
		PhysicsServer2D.body_set_state(static_body, PhysicsServer2D.BODY_STATE_TRANSFORM, Transform2D(ROTATION, origin))
		PhysicsServer2D.body_set_space(static_body, space)
		statics.append(static_body)

		var dynamic_body := PhysicsServer2D.body_create()
		PhysicsServer2D.body_set_mode(dynamic_body, PhysicsServer2D.BODY_MODE_RIGID)
		PhysicsServer2D.body_add_shape(dynamic_body, shape)
		PhysicsServer2D.body_set_param(dynamic_body, PhysicsServer2D.BODY_PARAM_GRAVITY_SCALE, 0.0)
		PhysicsServer2D.body_set_state(dynamic_body, PhysicsServer2D.BODY_STATE_CAN_SLEEP, false)
		var position := origin + perpendicular * SEPARATION
		PhysicsServer2D.body_set_state(dynamic_body, PhysicsServer2D.BODY_STATE_TRANSFORM, Transform2D(ROTATION, position))
		PhysicsServer2D.body_set_space(dynamic_body, space)
		dynamics.append(dynamic_body)
		expected.append(position)

	PhysicsServer2D.space_set_active(space, true)
	var valid := true
	var peak_pairs := 0
	for frame in range(HOLD_FRAMES):
		await physics_frame
		peak_pairs = maxi(peak_pairs, int(Performance.get_monitor(Performance.PHYSICS_2D_COLLISION_PAIRS)))
		for i in range(PAIR_COUNT):
			var pose: Transform2D = PhysicsServer2D.body_get_state(dynamics[i], PhysicsServer2D.BODY_STATE_TRANSFORM)
			var velocity: Vector2 = PhysicsServer2D.body_get_state(dynamics[i], PhysicsServer2D.BODY_STATE_LINEAR_VELOCITY)
			if not pose.origin.is_finite() or not velocity.is_finite() or pose.origin.distance_to(expected[i]) > 0.01:
				valid = false
				break
		if not valid:
			break

	# A changed relative offset must invalidate the saved negative result.
	# The new 10-unit overlap is well above the penetration allowance.
	for i in range(PAIR_COUNT):
		expected[i] -= perpendicular * (SEPARATION - OVERLAP_OFFSET)
		PhysicsServer2D.body_set_state(dynamics[i], PhysicsServer2D.BODY_STATE_TRANSFORM, Transform2D(ROTATION, expected[i]))
	var moved_after_overlap := false
	if valid:
		for frame in range(CONTACT_FRAMES):
			await physics_frame
			for i in range(PAIR_COUNT):
				var pose: Transform2D = PhysicsServer2D.body_get_state(dynamics[i], PhysicsServer2D.BODY_STATE_TRANSFORM)
				var velocity: Vector2 = PhysicsServer2D.body_get_state(dynamics[i], PhysicsServer2D.BODY_STATE_LINEAR_VELOCITY)
				if not pose.origin.is_finite() or not velocity.is_finite() or velocity.length_squared() > 100000000.0:
					valid = false
					break
				if pose.origin.distance_to(expected[i]) > 0.5:
					moved_after_overlap = true
			if not valid:
				break

	PhysicsServer2D.space_set_active(space, false)
	for body in dynamics:
		PhysicsServer2D.free_rid(body)
	for body in statics:
		PhysicsServer2D.free_rid(body)
	PhysicsServer2D.free_rid(shape)
	PhysicsServer2D.free_rid(space)
	return {
		"dimension": "2D", "pairs": PAIR_COUNT, "peak_broadphase_pairs": peak_pairs,
		"moved_after_overlap": moved_after_overlap,
		"valid": valid and peak_pairs >= 6 and moved_after_overlap,
	}


func _exercise_3d() -> Dictionary:
	var space := PhysicsServer3D.space_create()
	var shape := PhysicsServer3D.box_shape_create()
	# 3D box shape data uses full dimensions.
	PhysicsServer3D.shape_set_data(shape, Vector3(120.0, 12.0, 10.0))
	var perpendicular := Vector3(-sin(ROTATION), cos(ROTATION), 0.0)
	var basis := Basis(Vector3(0.0, 0.0, 1.0), ROTATION)
	var statics: Array[RID] = []
	var dynamics: Array[RID] = []
	var expected: Array[Vector3] = []
	for i in range(PAIR_COUNT):
		var origin := Vector3(float(i) * LANE_SPACING, 0.0, 0.0)
		var static_body := PhysicsServer3D.body_create()
		PhysicsServer3D.body_set_mode(static_body, PhysicsServer3D.BODY_MODE_STATIC)
		PhysicsServer3D.body_add_shape(static_body, shape)
		PhysicsServer3D.body_set_state(static_body, PhysicsServer3D.BODY_STATE_TRANSFORM, Transform3D(basis, origin))
		PhysicsServer3D.body_set_space(static_body, space)
		statics.append(static_body)

		var dynamic_body := PhysicsServer3D.body_create()
		PhysicsServer3D.body_set_mode(dynamic_body, PhysicsServer3D.BODY_MODE_RIGID)
		PhysicsServer3D.body_add_shape(dynamic_body, shape)
		PhysicsServer3D.body_set_param(dynamic_body, PhysicsServer3D.BODY_PARAM_GRAVITY_SCALE, 0.0)
		PhysicsServer3D.body_set_state(dynamic_body, PhysicsServer3D.BODY_STATE_CAN_SLEEP, false)
		var position := origin + perpendicular * SEPARATION
		PhysicsServer3D.body_set_state(dynamic_body, PhysicsServer3D.BODY_STATE_TRANSFORM, Transform3D(basis, position))
		PhysicsServer3D.body_set_space(dynamic_body, space)
		dynamics.append(dynamic_body)
		expected.append(position)

	PhysicsServer3D.space_set_active(space, true)
	var valid := true
	var peak_pairs := 0
	for frame in range(HOLD_FRAMES):
		await physics_frame
		peak_pairs = maxi(peak_pairs, int(Performance.get_monitor(Performance.PHYSICS_3D_COLLISION_PAIRS)))
		for i in range(PAIR_COUNT):
			var pose: Transform3D = PhysicsServer3D.body_get_state(dynamics[i], PhysicsServer3D.BODY_STATE_TRANSFORM)
			var velocity: Vector3 = PhysicsServer3D.body_get_state(dynamics[i], PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY)
			if not pose.origin.is_finite() or not velocity.is_finite() or pose.origin.distance_to(expected[i]) > 0.01:
				valid = false
				break
		if not valid:
			break

	for i in range(PAIR_COUNT):
		expected[i] -= perpendicular * (SEPARATION - OVERLAP_OFFSET)
		PhysicsServer3D.body_set_state(dynamics[i], PhysicsServer3D.BODY_STATE_TRANSFORM, Transform3D(basis, expected[i]))
	var moved_after_overlap := false
	if valid:
		for frame in range(CONTACT_FRAMES):
			await physics_frame
			for i in range(PAIR_COUNT):
				var pose: Transform3D = PhysicsServer3D.body_get_state(dynamics[i], PhysicsServer3D.BODY_STATE_TRANSFORM)
				var velocity: Vector3 = PhysicsServer3D.body_get_state(dynamics[i], PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY)
				if not pose.origin.is_finite() or not velocity.is_finite() or velocity.length_squared() > 100000000.0:
					valid = false
					break
				if pose.origin.distance_to(expected[i]) > 0.5:
					moved_after_overlap = true
			if not valid:
				break

	PhysicsServer3D.space_set_active(space, false)
	for body in dynamics:
		PhysicsServer3D.free_rid(body)
	for body in statics:
		PhysicsServer3D.free_rid(body)
	PhysicsServer3D.free_rid(shape)
	PhysicsServer3D.free_rid(space)
	return {
		"dimension": "3D", "pairs": PAIR_COUNT, "peak_broadphase_pairs": peak_pairs,
		"moved_after_overlap": moved_after_overlap,
		"valid": valid and peak_pairs >= 6 and moved_after_overlap,
	}
