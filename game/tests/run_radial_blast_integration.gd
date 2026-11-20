extends SceneTree
## Native physics integration regression for wall-shielded velocity-change blasts.
## Launch with Cgame native editor after importing game assets:
## godot --headless --path game --script res://tests/run_radial_blast_integration.gd
##
## Uses two real RigidBody3D nodes with different masses at equal range,
## a static wall between the field and only one target, and real physics
## frames (not just source-text checks or pure falloff calculations).

var _checks := 0
var _failures: Array[String] = []


func _check(ok: bool, name: String) -> void:
	_checks += 1
	if not ok:
		_failures.append(name)
		printerr("FAIL " + name)


func _body(stage: Node3D, at: Vector3, mass: float) -> RigidBody3D:
	var body := RigidBody3D.new()
	body.mass = mass
	body.gravity_scale = 0.0
	body.can_sleep = false
	body.collision_layer = 1 << 20 # Decorative debris, never a wall.
	body.collision_mask = 0
	body.linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	body.linear_damp = 0.0
	body.position = at
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.3
	shape.shape = sphere
	body.add_child(shape)
	stage.add_child(body)
	return body


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	if not ClassDB.class_exists("RadialForceField3D"):
		_check(false, "Cgame native RadialForceField3D class is present")
		quit(1)
		return
	var stage := Node3D.new()
	root.add_child(stage)
	# World-layer blocker between the origin (0,0,0) and the +X fragment.
	var wall := StaticBody3D.new()
	wall.collision_layer = 1
	wall.collision_mask = 0
	wall.position = Vector3(3, 0, 0)
	var wall_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.6, 4.0, 4.0)
	wall_shape.shape = box
	wall.add_child(wall_shape)
	stage.add_child(wall)

	var shielded := _body(stage, Vector3(6, 0, 0), 2.0)
	var unblocked := _body(stage, Vector3(-6, 0, 0), 8.0)
	var field := ClassDB.instantiate("RadialForceField3D") as Node3D
	_check(field != null, "field can be instantiated as Node3D")
	if field == null:
		stage.queue_free()
		quit(1)
		return
	_check(field.has_method("set_occlusion_mask"),
		"new world-geometry occlusion API is present in the native build")
	if not field.has_method("set_occlusion_mask"):
		stage.queue_free()
		quit(1)
		return
	field.set("radius", 10.0)
	field.set("strength", 12.0)
	field.set("falloff", 0) # Uniform over sphere for a clean mass comparison.
	field.set("collision_mask", 1 << 20)
	field.set("occlusion_mask", 1)
	field.set("occlusion_attenuation", 0.25)
	field.set("max_occlusion_rays", 2)
	field.set("mass_independent", true)
	field.set("upward_bias", 0.0)
	field.set("free_after_fire", false)
	stage.add_child(field)

	# Allow the PhysicsServer to register both bodies and the static wall.
	await physics_frame
	await physics_frame
	field.call("fire") # Immediate during physics, otherwise deferred safely.
	await physics_frame
	await physics_frame
	var shielded_velocity: Vector3 = shielded.linear_velocity
	var unblocked_velocity: Vector3 = unblocked.linear_velocity
	_check(unblocked_velocity.x < -2.0,
		"unblocked heavy body is accelerated away from the explosion")
	_check(shielded_velocity.x > 0.1,
		"lighter body behind wall is still moved by attenuated shockwave")
	_check(unblocked_velocity.length() > shielded_velocity.length(),
		"the obstacle shields its target even though that target has less mass")
	if unblocked_velocity.length() > 0.1:
		var ratio: float = shielded_velocity.length() / unblocked_velocity.length()
		_check(absf(ratio - 0.25) < 0.08,
			"real physics impulses obey the configured 25% wall transmission")
	stage.queue_free()
	await process_frame
	print("RADIAL BLAST INTEGRATION: %d checks, %d failures" % [_checks, _failures.size()])
	quit(1 if not _failures.is_empty() else 0)
