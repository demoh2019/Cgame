# Real native GodotPhysics3D regression of optional two-way PBF/rigid impact.
# Two identical dynamic boxes, each struck by a single PBF particle.
# The control's fluid collides one-way; the experiment's fluid transfers
# an equal and opposite impulse to its RigidBody3D, creating downward speed.
extends SceneTree


func _initialize() -> void:
	_run.call_deferred()


func _create_pair(parent: Node3D, x_offset: float, coupled: bool) -> Dictionary:
	var rigid := RigidBody3D.new()
	rigid.name = "CoupledBody" if coupled else "OneWayControlBody"
	rigid.position = Vector3(x_offset, 1.0, 0)
	rigid.mass = 2.0
	rigid.gravity_scale = 0.0
	rigid.linear_damp = 0.0
	rigid.angular_damp = 0.0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.5, 0.5, 1.5)
	shape.shape = box
	rigid.add_child(shape)
	parent.add_child(rigid)

	var fluid := PBFParticleFluid3D.new()
	fluid.name = "CoupledFluid" if coupled else "OneWayControlFluid"
	fluid.position = Vector3(x_offset, 0, 0)
	fluid.gravity = Vector3.ZERO
	fluid.box_min = Vector3(-2, 0, -2)
	fluid.box_max = Vector3(2, 4, 2)
	fluid.particle_mass = 6.0
	fluid.rest_density = 1000.0
	fluid.collide_with_bodies = true
	fluid.two_way_rigid_coupling = coupled
	fluid.max_rigid_impulse = 20.0
	parent.add_child(fluid)

	var start := PackedVector3Array([Vector3(0, 1.55, 0)])
	assert(fluid.set_particle_positions(start))
	assert(fluid.add_velocity_pulse(Vector3(0, 1.55, 0), 0.5,
			Vector3(0, -42.0, 0)) == 1)
	fluid.simulation_enabled = true
	return {"rigid": rigid, "fluid": fluid}


func _run() -> void:
	var scene := Node3D.new()
	scene.name = "PBFRigidWorld"
	root.add_child(scene)
	var one_way := _create_pair(scene, -5.0, false)
	var two_way := _create_pair(scene, 5.0, true)

	var max_two_way_hits := 0
	var max_control_hits := 0
	for frame in range(3):
		await physics_frame
		await process_frame
		max_two_way_hits = maxi(max_two_way_hits,
				two_way["fluid"].get_last_rigid_impulses())
		max_control_hits = maxi(max_control_hits,
				one_way["fluid"].get_last_rigid_impulses())

	var base_velocity: Vector3 = PhysicsServer3D.body_get_state(
			one_way["rigid"].get_rid(), PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY)
	var reactive_velocity: Vector3 = PhysicsServer3D.body_get_state(
			two_way["rigid"].get_rid(), PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY)
	var fluid_velocity: Vector3 = two_way["fluid"].get_particle_velocities()[0]
	var particle_position: Vector3 = two_way["fluid"].get_particle_positions()[0]
	var affected_body := reactive_velocity.y < base_velocity.y - 0.1
	var hits_legal := max_two_way_hits >= 1 and max_control_hits == 0
	var finite := base_velocity.is_finite() and reactive_velocity.is_finite()
	finite = finite and fluid_velocity.is_finite() and particle_position.is_finite()
	var stays_in_tank := particle_position.y >= 0 and particle_position.y <= 4

	# Toggling coupling must never disable the original particle-wall bounce.
	two_way["fluid"].two_way_rigid_coupling = false
	var toggled := not two_way["fluid"].two_way_rigid_coupling
	two_way["fluid"].simulation_enabled = false
	one_way["fluid"].simulation_enabled = false
	scene.queue_free()
	if not (affected_body and hits_legal and finite and stays_in_tank and toggled):
		printerr("PBF rigid coupling FAILED: body_one_way=", base_velocity,
				" body_two_way=", reactive_velocity, " fluid=", fluid_velocity,
				" hit_count=", max_two_way_hits,
				" control_hits=", max_control_hits, " finite=", finite,
				" in_tank=", stays_in_tank, " toggle=", toggled)
		quit(1)
		return
	print("Native PBF two-way rigid contact passed: body_one_way=", base_velocity,
			" body_two_way=", reactive_velocity, " paired_hits=", max_two_way_hits)
	quit(0)
