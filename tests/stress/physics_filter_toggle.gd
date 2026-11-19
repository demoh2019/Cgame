extends RefCounted
## Exercise dynamic broadphase layer/mask filtering without moving colliders.
## Static bodies use mask=0 and areas use layer=0, so only the area's
## collision mask determines whether the pair should exist.

func run_2d(tree: SceneTree, scale: int, frames: int) -> Dictionary:
	var world := Node2D.new()
	tree.root.add_child(world)
	var shape := CircleShape2D.new()
	shape.radius = 0.45
	var count := 16 * scale
	var areas: Array[Area2D] = []
	areas.resize(count)
	for i in range(count):
		var position_2d := Vector2(float(i % 128) * 3.0, float(int(i / 128)) * 3.0)
		var body := StaticBody2D.new()
		body.collision_layer = 1
		body.collision_mask = 0
		body.position = position_2d
		var body_shape := CollisionShape2D.new()
		body_shape.shape = shape
		body.add_child(body_shape)
		world.add_child(body)

		var area := Area2D.new()
		area.collision_layer = 0
		area.collision_mask = 1
		area.monitoring = true
		area.position = position_2d
		var area_shape := CollisionShape2D.new()
		area_shape.shape = shape
		area.add_child(area_shape)
		world.add_child(area)
		areas[i] = area

	for i in range(3):
		await tree.physics_frame

	var mismatch_count := 0
	var max_toggle_usec := 0
	var total_toggle_usec := 0
	var phases := maxi(2, frames)
	for phase in range(phases):
		var target_mask := 0 if phase % 2 == 0 else 1
		var started := Time.get_ticks_usec()
		for area in areas:
			area.collision_mask = target_mask
		var elapsed := Time.get_ticks_usec() - started
		total_toggle_usec += elapsed
		max_toggle_usec = maxi(max_toggle_usec, elapsed)

		# No transforms or shape AABBs change between phases.
		# The pair must be regenerated purely by the mask update.
		await tree.physics_frame
		await tree.physics_frame
		for area in areas:
			if area.get_overlapping_bodies().size() != target_mask:
				mismatch_count += 1

	world.queue_free()
	await tree.process_frame
	if mismatch_count != 0:
		return {"error": "2D broadphase pair filtering did not follow stationary mask changes", "mismatches": mismatch_count}
	return {"objects": count * 2, "filter_changes": count * phases,
			"toggle_phases": phases, "total_toggle_ms": float(total_toggle_usec) / 1000.0,
			"peak_toggle_ms": float(max_toggle_usec) / 1000.0,
			"stationary_pairs_verified": count * phases}


func run_3d(tree: SceneTree, scale: int, frames: int) -> Dictionary:
	var world := Node3D.new()
	tree.root.add_child(world)
	var shape := SphereShape3D.new()
	shape.radius = 0.45
	var count := 16 * scale
	var areas: Array[Area3D] = []
	areas.resize(count)
	for i in range(count):
		var position_3d := Vector3(float(i % 128) * 3.0, float(int(i / 128)) * 3.0, 0.0)
		var body := StaticBody3D.new()
		body.collision_layer = 1
		body.collision_mask = 0
		body.position = position_3d
		var body_shape := CollisionShape3D.new()
		body_shape.shape = shape
		body.add_child(body_shape)
		world.add_child(body)

		var area := Area3D.new()
		area.collision_layer = 0
		area.collision_mask = 1
		area.monitoring = true
		area.position = position_3d
		var area_shape := CollisionShape3D.new()
		area_shape.shape = shape
		area.add_child(area_shape)
		world.add_child(area)
		areas[i] = area

	for i in range(3):
		await tree.physics_frame

	var mismatch_count := 0
	var max_toggle_usec := 0
	var total_toggle_usec := 0
	var phases := maxi(2, frames)
	for phase in range(phases):
		var target_mask := 0 if phase % 2 == 0 else 1
		var started := Time.get_ticks_usec()
		for area in areas:
			area.collision_mask = target_mask
		var elapsed := Time.get_ticks_usec() - started
		total_toggle_usec += elapsed
		max_toggle_usec = maxi(max_toggle_usec, elapsed)

		await tree.physics_frame
		await tree.physics_frame
		for area in areas:
			if area.get_overlapping_bodies().size() != target_mask:
				mismatch_count += 1

	world.queue_free()
	await tree.process_frame
	if mismatch_count != 0:
		return {"error": "3D broadphase pair filtering did not follow stationary mask changes", "mismatches": mismatch_count}
	return {"objects": count * 2, "filter_changes": count * phases,
			"toggle_phases": phases, "total_toggle_ms": float(total_toggle_usec) / 1000.0,
			"peak_toggle_ms": float(max_toggle_usec) / 1000.0,
			"stationary_pairs_verified": count * phases}
