# Regression for 3D streaming BVH rays with float32 length-squared overflow.
# Run: godot --headless --path tests/stress --script res://physics_long_ray_bvh_3d_regression.gd
extends SceneTree


func _initialize() -> void:
	_run.call_deferred()


func _make_sphere(space: RID, shape: RID, x: float) -> RID:
	var body: RID = PhysicsServer3D.body_create()
	PhysicsServer3D.body_set_mode(body, PhysicsServer3D.BODY_MODE_STATIC)
	PhysicsServer3D.body_add_shape(body, shape)
	PhysicsServer3D.body_set_state(body, PhysicsServer3D.BODY_STATE_TRANSFORM, Transform3D(Basis(), Vector3(x, 0.0, 0.0)))
	PhysicsServer3D.body_set_space(body, space)
	return body


func _check_ray(state: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3, expected: RID, label: String) -> int:
	var params := PhysicsRayQueryParameters3D.create(from, to)
	params.collide_with_bodies = true
	var hit: Dictionary = state.intersect_ray(params)
	if hit.is_empty():
		printerr("FAIL %s: no hit" % label)
		return 1
	if hit["rid"] != expected:
		printerr("FAIL %s: incorrect nearest collider %s" % [label, hit["rid"]])
		return 1
	var point: Vector3 = hit["position"]
	var normal: Vector3 = hit["normal"]
	if not point.is_finite() or not normal.is_finite():
		printerr("FAIL %s: non-finite hit result" % label)
		return 1
	var fraction: float = (point.x - from.x) / (to.x - from.x)
	if fraction < 0.20 or fraction > 0.30:
		printerr("FAIL %s: incorrect entry fraction %.6f" % [label, fraction])
		return 1
	print("PASS %s: fraction=%.6f" % [label, fraction])
	return 0


func _run() -> void:
	var space: RID = PhysicsServer3D.space_create()
	var shape: RID = PhysicsServer3D.sphere_shape_create()
	PhysicsServer3D.shape_set_data(shape, 1.0e16)

	var left: RID = _make_sphere(space, shape, -5.0e19)
	var right: RID = _make_sphere(space, shape, 5.0e19)

	PhysicsServer3D.space_set_active(space, true)
	await physics_frame
	await physics_frame

	var errors: int = 0
	var state: PhysicsDirectSpaceState3D = PhysicsServer3D.space_get_direct_state(space)
	if state == null:
		printerr("FAIL: direct space state unavailable")
		errors += 1
	else:
		errors += _check_ray(state, Vector3(-1.0e20, 0.0, 0.0), Vector3(1.0e20, 0.0, 0.0), left, "left-to-right")
		errors += _check_ray(state, Vector3(1.0e20, 0.0, 0.0), Vector3(-1.0e20, 0.0, 0.0), right, "right-to-left")

	PhysicsServer3D.space_set_active(space, false)
	PhysicsServer3D.free_rid(left)
	PhysicsServer3D.free_rid(right)
	PhysicsServer3D.free_rid(shape)
	PhysicsServer3D.free_rid(space)

	if errors:
		printerr("3D long-ray BVH regression failed: %d" % errors)
		quit(1)
	else:
		print("3D long-ray BVH regression passed.")
		quit(0)
