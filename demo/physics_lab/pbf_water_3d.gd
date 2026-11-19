extends Node3D
## Native Cgame CPU PBF liquid demonstration, self-contained and opt-in.
## Particle dynamics run in C++ PBFParticleFluid3D; GDScript only draws them.
## The simulation is local to this station, not global water rendering.

const BLOCK_ORIGIN := Vector3(-0.70, 1.55, -0.70)
const BLOCK_SIZE := Vector3i(7, 5, 7)
const BLOCK_SPACING := 0.21

var fluid: PBFParticleFluid3D
var instances: MultiMesh
var label: Label3D


func _ready() -> void:
	name = "PBFWaterDemo"
	position = Vector3(-28, 0, -11)
	fluid = PBFParticleFluid3D.new()
	fluid.name = "PBFWaterCPU"
	fluid.smoothing_radius = 0.37
	fluid.rest_density = 1000.0
	fluid.particle_mass = 6.0
	fluid.particle_radius = 0.075
	fluid.solver_iterations = 5
	fluid.xsph_viscosity = 0.03
	fluid.artificial_pressure = 0.002
	fluid.boundary_restitution = 0.15
	fluid.box_min = Vector3(-1.7, 0.0, -1.7)
	fluid.box_max = Vector3(1.7, 3.3, 1.7)
	fluid.collide_with_bodies = false
	fluid.two_way_rigid_coupling = false
	fluid.max_rigid_impulse = 20.0
	add_child(fluid)

	assert(fluid.create_block(BLOCK_ORIGIN, BLOCK_SIZE, BLOCK_SPACING))
	var ball := SphereMesh.new()
	ball.radius = 0.082
	ball.height = 0.164
	ball.radial_segments = 8
	ball.rings = 4
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.12, 0.56, 1.0)
	material.metallic = 0.08
	material.roughness = 0.2
	ball.material = material

	instances = MultiMesh.new()
	instances.transform_format = MultiMesh.TRANSFORM_3D
	instances.mesh = ball
	instances.instance_count = fluid.get_particle_count()
	var renderer := MultiMeshInstance3D.new()
	renderer.name = "ParticleRenderer"
	renderer.multimesh = instances
	fluid.add_child(renderer)

	label = Label3D.new()
	label.name = "StationLabel"
	label.text = "NATIVE CPU PBF FLUID | %d particles | U: reset | I: pause | O: stir | P: rigid coupling" % fluid.get_particle_count()
	label.position = Vector3(0, 3.65, 0)
	label.font_size = 40
	label.pixel_size = 0.006
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(label)

	var bottom := MeshInstance3D.new()
	bottom.name = "LiquidTankFloor"
	var floor_mesh := BoxMesh.new()
	floor_mesh.size = Vector3(3.4, 0.12, 3.4)
	bottom.mesh = floor_mesh
	bottom.position = Vector3(0, -0.07, 0)
	add_child(bottom)

	# A real RigidBody3D obstacle for opt-in two-way fluid interaction.
	# Its CollisionShape3D receives a native impulse at each hit point;
	# angular velocity emerges naturally on off-center impacts.
	var reactive_body := RigidBody3D.new()
	reactive_body.name = "ReactiveFloat"
	reactive_body.mass = 2.0
	reactive_body.position = Vector3(0.0, 1.05, 0.0)
	var floating_shape := CollisionShape3D.new()
	var sphere_collision := SphereShape3D.new()
	sphere_collision.radius = 0.32
	floating_shape.shape = sphere_collision
	reactive_body.add_child(floating_shape)
	var float_visual := MeshInstance3D.new()
	var float_mesh := SphereMesh.new()
	float_mesh.radius = 0.32
	float_mesh.height = 0.64
	float_visual.mesh = float_mesh
	reactive_body.add_child(float_visual)
	add_child(reactive_body)

	fluid.simulation_enabled = true
	_update_visuals()


func _process(_delta: float) -> void:
	if fluid == null or instances == null:
		return
	_update_visuals()


func _update_visuals() -> void:
	var points := fluid.get_particle_positions()
	for i in range(points.size()):
		instances.set_instance_transform(i, Transform3D(Basis(), points[i]))


func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo or fluid == null:
		return
	match event.keycode:
		KEY_U:
			fluid.create_block(BLOCK_ORIGIN, BLOCK_SIZE, BLOCK_SPACING)
		KEY_I:
			fluid.simulation_enabled = not fluid.simulation_enabled
			label.text = "NATIVE CPU PBF FLUID | %d particles | %s" % [
				fluid.get_particle_count(), "RUNNING" if fluid.simulation_enabled else "PAUSED"
			]
		KEY_O:
			# Stir the free surface with an upward/lateral velocity pulse.
			# This is a native kernel call; no per-particle GDScript loop.
			fluid.add_velocity_pulse(Vector3(0, 1.0, 0), 1.8, Vector3(3.0, 4.5, 0))
		KEY_P:
			# Expensive ray sweeps and rigid-body momentum exchange are
			# only enabled when the player explicitly opts in.
			fluid.two_way_rigid_coupling = not fluid.two_way_rigid_coupling
			fluid.collide_with_bodies = fluid.two_way_rigid_coupling
			label.text = "NATIVE CPU PBF FLUID | Rigid coupling: %s | Paired hits: %d" % [
				"ON" if fluid.two_way_rigid_coupling else "OFF",
				fluid.get_last_rigid_impulses()
			]
