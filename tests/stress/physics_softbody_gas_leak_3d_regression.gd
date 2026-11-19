# Closed tetrahedral soft-body balloon: compare sealed gas with a vented shell.
# Test the *actual* GodotPhysics3D force integration, not only the EOS helper.
# Run: --headless --path tests/stress --script res://physics_softbody_gas_leak_3d_regression.gd
extends SceneTree

const PRESSURE := 12.0
const GAMMA := 1.0
const SETTINGS := {
	"physics/3d/solver/soft_body_gas_pressure_gamma": GAMMA,
	"physics/3d/solver/soft_body_gas_leak_rate": 0.0,
	"physics/3d/solver/soft_body_xpbd_volume_compliance": 0.0,
	"physics/3d/solver/soft_body_shape_matching_stiffness": 0.0,
}


func _initialize() -> void:
	_run.call_deferred()


func _make_mesh() -> ArrayMesh:
	var surface: Array = []
	surface.resize(Mesh.ARRAY_MAX)
	surface[Mesh.ARRAY_VERTEX] = PackedVector3Array([
		Vector3(0, 0, 0), Vector3(1, 0, 0),
		Vector3(0, 1, 0), Vector3(0, 0, 1)
	])
	# Outward-wound sealed tetrahedron: each undirected edge is used
	# by precisely two faces with opposite directions.
	surface[Mesh.ARRAY_INDEX] = PackedInt32Array([
		0, 2, 1, 0, 1, 3, 0, 3, 2, 1, 2, 3
	])
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, surface)
	return mesh


func _make_balloon(mesh: ArrayMesh, offset: Vector3, leak_rate: float) -> Dictionary:
	ProjectSettings.set_setting("physics/3d/solver/soft_body_gas_leak_rate", leak_rate)
	var space := PhysicsServer3D.space_create()
	PhysicsServer3D.area_set_param(space, PhysicsServer3D.AREA_PARAM_GRAVITY, 0.0)
	PhysicsServer3D.area_set_param(space, PhysicsServer3D.AREA_PARAM_GRAVITY_VECTOR, Vector3.DOWN)
	var balloon := PhysicsServer3D.soft_body_create()
	PhysicsServer3D.soft_body_set_mesh(balloon, mesh.get_rid())
	PhysicsServer3D.soft_body_set_simulation_precision(balloon, 8)
	PhysicsServer3D.soft_body_set_linear_stiffness(balloon, 0.0)
	PhysicsServer3D.soft_body_set_damping_coefficient(balloon, 0.25)
	PhysicsServer3D.soft_body_set_collision_layer(balloon, 0)
	PhysicsServer3D.soft_body_set_collision_mask(balloon, 0)
	PhysicsServer3D.soft_body_set_pressure_coefficient(balloon, PRESSURE)
	PhysicsServer3D.soft_body_set_transform(balloon, Transform3D(Basis(), offset))
	PhysicsServer3D.soft_body_set_space(balloon, space)
	PhysicsServer3D.space_set_active(space, true)
	return {"space": space, "body": balloon, "offset": offset, "leak_rate": leak_rate}


func _sample_balloon(record: Dictionary) -> Dictionary:
	var p: Array[Vector3] = []
	var finite := true
	for i in range(4):
		var world: Vector3 = PhysicsServer3D.soft_body_get_point_global_position(record.body, i)
		p.append(world)
		finite = finite and world.is_finite()
	var signed_six_volume: float = (p[1] - p[0]).cross(p[2] - p[0]).dot(p[3] - p[0])
	return {"finite": finite, "volume": absf(signed_six_volume) / 6.0,
		"leak_rate": record.leak_rate}


func _run() -> void:
	var original: Dictionary = {}
	for key in SETTINGS:
		original[key] = ProjectSettings.get_setting(key)
		ProjectSettings.set_setting(key, SETTINGS[key])
	var mesh := _make_mesh()
	var sealed := _make_balloon(mesh, Vector3.ZERO, 0.0)
	var vented := _make_balloon(mesh, Vector3(10, 0, 0), 25.0)
	# Both spaces have cached independently configured gas leak rates.
	for frame in range(90):
		await physics_frame
	await process_frame
	var sealed_state := _sample_balloon(sealed)
	var vented_state := _sample_balloon(vented)
	var sealed_volume: float = sealed_state.volume
	var vented_volume: float = vented_state.volume

	for balloon in [sealed, vented]:
		PhysicsServer3D.space_set_active(balloon.space, false)
		PhysicsServer3D.free_rid(balloon.body)
		PhysicsServer3D.free_rid(balloon.space)
	for key in original:
		ProjectSettings.set_setting(key, original[key])

	# The inflation mismatch must be visible in integrated geometry,
	# while both balloon meshes remain finite and non-degenerate.
	if not (sealed_state.finite and vented_state.finite and
			sealed_volume > 0.16667 and vented_volume > 0.0 and
			sealed_volume > vented_volume * 1.15):
		printerr("Gas leak soft-body regression FAILED: sealed=", sealed_state,
				" vented=", vented_state)
		quit(1)
		return
	print("SoftBody sealed gas discharge passed: sealed=", sealed_volume,
			" vented=", vented_volume)
	quit(0)
