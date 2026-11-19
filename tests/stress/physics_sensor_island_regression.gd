# Regression: area-only constraint islands must deliver callbacks even when
# all their constraints are discarded by pre_solve (no solver work remains).
# Run with built-in GodotPhysics 2D and 3D:
# godot --headless --path tests/stress --script res://physics_sensor_island_regression.gd
extends SceneTree

const PAIRS := 48


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var counters := {"enter2d": 0, "exit2d": 0, "enter3d": 0, "exit3d": 0}
	var scene2d := Node2D.new()
	var scene3d := Node3D.new()
	root.add_child(scene2d)
	root.add_child(scene3d)

	var circle := CircleShape2D.new()
	circle.radius = 4.0
	var sphere := SphereShape3D.new()
	sphere.radius = 1.0

	var bodies2d: Array[StaticBody2D] = []
	var bodies3d: Array[StaticBody3D] = []

	# Every pair occupies a separate broadphase region. Each monitored
	# overlap creates an area constraint that pre_solve removes from the
	# velocity solver, while its enter/exit callbacks still must fire.
	for i in range(PAIRS):
		var position2d := Vector2(float(i) * 40.0, 0.0)
		var area2d := Area2D.new()
		area2d.position = position2d
		area2d.collision_layer = 1
		area2d.collision_mask = 1
		var area_collision2d := CollisionShape2D.new()
		area_collision2d.shape = circle
		area2d.add_child(area_collision2d)
		area2d.body_entered.connect(func(_body: Node2D) -> void:
			counters["enter2d"] += 1
		)
		area2d.body_exited.connect(func(_body: Node2D) -> void:
			counters["exit2d"] += 1
		)
		scene2d.add_child(area2d)

		var body2d := StaticBody2D.new()
		body2d.position = position2d
		body2d.collision_layer = 1
		var body_collision2d := CollisionShape2D.new()
		body_collision2d.shape = circle
		body2d.add_child(body_collision2d)
		scene2d.add_child(body2d)
		bodies2d.append(body2d)

		var position3d := Vector3(float(i) * 20.0, 0.0, 0.0)
		var area3d := Area3D.new()
		area3d.position = position3d
		area3d.collision_layer = 1
		area3d.collision_mask = 1
		var area_collision3d := CollisionShape3D.new()
		area_collision3d.shape = sphere
		area3d.add_child(area_collision3d)
		area3d.body_entered.connect(func(_body: Node3D) -> void:
			counters["enter3d"] += 1
		)
		area3d.body_exited.connect(func(_body: Node3D) -> void:
			counters["exit3d"] += 1
		)
		scene3d.add_child(area3d)

		var body3d := StaticBody3D.new()
		body3d.position = position3d
		body3d.collision_layer = 1
		var body_collision3d := CollisionShape3D.new()
		body_collision3d.shape = sphere
		body3d.add_child(body_collision3d)
		scene3d.add_child(body3d)
		bodies3d.append(body3d)

	for _frame in range(8):
		await physics_frame

	var failed := false
	if counters["enter2d"] != PAIRS or counters["enter3d"] != PAIRS:
		printerr("Sensor island enter events mismatch: ", counters)
		failed = true

	# Moving static bodies out also exercises area-only island pre-solve
	# for the exit transition; no rigid-body solver task is necessary.
	for body in bodies2d:
		body.position.y = 300.0
	for body in bodies3d:
		body.position.y = 100.0

	for _frame in range(8):
		await physics_frame

	if counters["exit2d"] != PAIRS or counters["exit3d"] != PAIRS:
		printerr("Sensor island exit events mismatch: ", counters)
		failed = true

	scene2d.free()
	scene3d.free()
	if failed:
		quit(1)
	else:
		print("Physics sensor island regression passed: ", counters)
		quit(0)
