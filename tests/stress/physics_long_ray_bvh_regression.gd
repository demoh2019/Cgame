# Regression: streaming 2D ray casts must retain a finite, ordered hit
# fraction even when a float32 ray's squared length overflows.
# Run: godot --headless --path tests/stress --script res://physics_long_ray_bvh_regression.gd
extends SceneTree


func _initialize() -> void:
	_run.call_deferred()


func _make_circle(space: RID, shape: RID, x: float) -> RID:
	var body: RID = PhysicsServer2D.body_create()
	PhysicsServer2D.body_set_mode(body, PhysicsServer2D.BODY_MODE_STATIC)
	PhysicsServer2D.body_add_shape(body, shape)
	PhysicsServer2D.body_set_state(body, PhysicsServer2D.BODY_STATE_TRANSFORM, Transform2D(0.0, Vector2(x, 0.0)))
	PhysicsServer2D.body_set_space(body, space)
	return body


func _check_ray(state: PhysicsDirectSpaceState2D, from: Vector2, to: Vector2, expected: RID, label: String) -> int:
	var params := PhysicsRayQueryParameters2D.create(from, to)
	params.collide_with_bodies = true
	var hit: Dictionary = state.intersect_ray(params)
	if hit.is_empty():
		printerr("FAIL %s: expected a long-ray collision" % label)
		return 1
	if hit["rid"] != expected:
		printerr("FAIL %s: wrong nearest collider RID %s" % [label, hit["rid"]])
		return 1
	var position: Vector2 = hit["position"]
	var normal: Vector2 = hit["normal"]
	if not position.is_finite() or not normal.is_finite():
		printerr("FAIL %s: non-finite ray hit" % label)
		return 1
	var fraction: float = (position.x - from.x) / (to.x - from.x)
	if fraction < 0.20 or fraction > 0.30:
		printerr("FAIL %s: wrong hit fraction %s" % [label, fraction])
		return 1
	print("PASS %s: ray fraction=%.6f" % [label, fraction])
	return 0


func _run() -> void:
	var space: RID = PhysicsServer2D.space_create()
	var shape: RID = PhysicsServer2D.circle_shape_create()
	PhysicsServer2D.shape_set_data(shape, 1.0e16)

	# These coordinates are representable by float32, but their squared
	# segment length is not. The first hit is near the quarter-ray mark.
	var left: RID = _make_circle(space, shape, -5.0e19)
	var right: RID = _make_circle(space, shape, 5.0e19)

	PhysicsServer2D.space_set_active(space, true)
	await physics_frame
	await physics_frame

	var failures: int = 0
	var state: PhysicsDirectSpaceState2D = PhysicsServer2D.space_get_direct_state(space)
	if state == null:
		printerr("FAIL: physics direct space state unavailable")
		failures = 1
	else:
		failures += _check_ray(state, Vector2(-1.0e20, 0.0), Vector2(1.0e20, 0.0), left, "left-to-right")
		failures += _check_ray(state, Vector2(1.0e20, 0.0), Vector2(-1.0e20, 0.0), right, "right-to-left")

	PhysicsServer2D.space_set_active(space, false)
	PhysicsServer2D.free_rid(left)
	PhysicsServer2D.free_rid(right)
	PhysicsServer2D.free_rid(shape)
	PhysicsServer2D.free_rid(space)

	if failures:
		printerr("Long-ray BVH regression failed: %d" % failures)
		quit(1)
	else:
		print("Long-ray BVH regression passed.")
		quit(0)
