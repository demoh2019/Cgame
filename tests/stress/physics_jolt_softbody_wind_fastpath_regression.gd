extends SceneTree
## Jolt soft-body wind: compare no-attenuation, mixed attenuation and calm
## phases while exercising the per-body wind-area scratch and finite motion.

const PREFIX := "JOLT_SOFTBODY_WIND_FASTPATH_RESULT:"
const GRID := 16
const PHASE_FRAMES := 16

var entered: int = 0
var errors: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _on_area_body(status: int, body: RID, instance_id: int, body_shape: int, area_shape: int) -> void:
	if status == PhysicsServer3D.AREA_BODY_ADDED:
		entered += 1


func _make_cloth() -> ArrayMesh:
	var vertices := PackedVector3Array()
	var indices := PackedInt32Array()
	for z in range(GRID):
		for x in range(GRID):
			vertices.append(Vector3((float(x) - float(GRID - 1) / 2.0) * 0.14,
					0.0, (float(z) - float(GRID - 1) / 2.0) * 0.14))
	for z in range(GRID - 1):
		for x in range(GRID - 1):
			var a := z * GRID + x
			var b := a + 1
			var c := a + GRID
			var d := c + 1
			indices.append_array(PackedInt32Array([a, c, b, b, c, d]))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _make_wind_area(space: RID, sphere: RID, attenuation: float) -> RID:
	var area := PhysicsServer3D.area_create()
	PhysicsServer3D.area_add_shape(area, sphere)
	PhysicsServer3D.area_set_collision_layer(area, 1)
	PhysicsServer3D.area_set_collision_mask(area, 1)
	PhysicsServer3D.area_set_monitor_callback(area, Callable(self, "_on_area_body"))
	PhysicsServer3D.area_set_param(area, PhysicsServer3D.AREA_PARAM_WIND_SOURCE, Vector3.ZERO)
	PhysicsServer3D.area_set_param(area, PhysicsServer3D.AREA_PARAM_WIND_DIRECTION, Vector3.UP)
	PhysicsServer3D.area_set_param(area, PhysicsServer3D.AREA_PARAM_WIND_ATTENUATION_FACTOR, attenuation)
	PhysicsServer3D.area_set_param(area, PhysicsServer3D.AREA_PARAM_WIND_FORCE_MAGNITUDE, 0.0)
	PhysicsServer3D.area_set_space(area, space)
	return area


func _probe(soft_body: RID, label: String) -> float:
	var position := PhysicsServer3D.soft_body_get_point_global_position(soft_body, GRID * 8 + 8)
	var bounds := PhysicsServer3D.soft_body_get_bounds(soft_body)
	if not position.is_finite() or not bounds.position.is_finite() or not bounds.size.is_finite():
		errors.append(label + ": nonfinite soft-body position or bounds")
	return position.y


func _run() -> void:
	var space := PhysicsServer3D.space_create()
	PhysicsServer3D.space_set_active(space, true)
	PhysicsServer3D.area_set_param(space, PhysicsServer3D.AREA_PARAM_GRAVITY, 0.0)
	var mesh := _make_cloth()
	var soft_body := PhysicsServer3D.soft_body_create()
	PhysicsServer3D.soft_body_set_mesh(soft_body, mesh.get_rid())
	PhysicsServer3D.soft_body_set_state(soft_body, PhysicsServer3D.BODY_STATE_CAN_SLEEP, false)
	PhysicsServer3D.soft_body_set_collision_layer(soft_body, 1)
	PhysicsServer3D.soft_body_set_collision_mask(soft_body, 1)
	PhysicsServer3D.soft_body_set_space(soft_body, space)

	var sphere := PhysicsServer3D.sphere_shape_create()
	PhysicsServer3D.shape_set_data(sphere, 12.0)
	var constant_area := _make_wind_area(space, sphere, 0.0)
	var attenuated_area := _make_wind_area(space, sphere, 1.25)
	for frame in range(5):
		await physics_frame
	var before_wind := _probe(soft_body, "initial")

	var start_usec := Time.get_ticks_usec()
	# One area with zero attenuation: no pow() or centroid needed per face.
	PhysicsServer3D.area_set_param(constant_area, PhysicsServer3D.AREA_PARAM_WIND_FORCE_MAGNITUDE, 60.0)
	for frame in range(PHASE_FRAMES):
		await physics_frame
	var after_constant_wind := _probe(soft_body, "constant")
	if after_constant_wind <= before_wind + 0.001:
		errors.append("Constant wind did not displace the cloth upward")

	# Mixed attenuation must still evaluate the original attenuation formula.
	PhysicsServer3D.area_set_param(attenuated_area, PhysicsServer3D.AREA_PARAM_WIND_FORCE_MAGNITUDE, 20.0)
	for frame in range(PHASE_FRAMES):
		await physics_frame
	var after_mixed_wind := _probe(soft_body, "mixed")

	# Empty the scratch and then restore zero-attenuation wind.
	PhysicsServer3D.area_set_param(constant_area, PhysicsServer3D.AREA_PARAM_WIND_FORCE_MAGNITUDE, 0.0)
	PhysicsServer3D.area_set_param(attenuated_area, PhysicsServer3D.AREA_PARAM_WIND_FORCE_MAGNITUDE, 0.0)
	for frame in range(6):
		await physics_frame
	var after_calm := _probe(soft_body, "calm")
	PhysicsServer3D.area_set_param(constant_area, PhysicsServer3D.AREA_PARAM_WIND_FORCE_MAGNITUDE, 60.0)
	for frame in range(8):
		await physics_frame
	var after_restored := _probe(soft_body, "restored")
	var elapsed_ms := float(Time.get_ticks_usec() - start_usec) / 1000.0

	PhysicsServer3D.area_set_monitor_callback(constant_area, Callable())
	PhysicsServer3D.area_set_monitor_callback(attenuated_area, Callable())
	PhysicsServer3D.area_set_space(constant_area, RID())
	PhysicsServer3D.area_set_space(attenuated_area, RID())
	PhysicsServer3D.soft_body_set_space(soft_body, RID())
	PhysicsServer3D.space_set_active(space, false)
	PhysicsServer3D.free_rid(constant_area)
	PhysicsServer3D.free_rid(attenuated_area)
	PhysicsServer3D.free_rid(sphere)
	PhysicsServer3D.free_rid(soft_body)
	PhysicsServer3D.free_rid(space)

	print(PREFIX + JSON.stringify({
		"mesh_vertices": GRID * GRID,
		"mesh_triangles": (GRID - 1) * (GRID - 1) * 2,
		"constant_wind_y": after_constant_wind,
		"mixed_wind_y": after_mixed_wind,
		"calm_y": after_calm,
		"restored_y": after_restored,
		"initial_y": before_wind,
		"area_entries": entered,
		"elapsed_ms": elapsed_ms,
		"errors": errors
	}))
	if errors.is_empty():
		print("Jolt soft-body wind fast path regression passed.")
		quit(0)
	else:
		for failure in errors:
			printerr(failure)
		quit(1)
