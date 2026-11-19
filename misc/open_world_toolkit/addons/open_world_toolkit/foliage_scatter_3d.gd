@tool
extends MultiMeshInstance3D
class_name OWFoliageScatter3D
## Deterministic, batched foliage placement over a heightfield.

@export var terrain: OWTerrain3D
@export var foliage_mesh: Mesh
@export_range(0.0, 10.0, 0.001) var density: float = 0.05
@export_range(0, 1000000, 1) var seed: int = 1
@export_range(0.0, 90.0, 1.0) var max_slope_degrees: float = 40.0
@export var min_elevation: float = -10000.0
@export var max_elevation: float = 10000.0
@export_range(0.01, 10.0, 0.01) var min_scale: float = 0.8
@export_range(0.01, 10.0, 0.01) var max_scale: float = 1.3
@export_range(0, 100000, 1) var max_instances: int = 10000


func scatter() -> int:
	if terrain == null or terrain.heightmap == null or foliage_mesh == null:
		multimesh = null
		return 0
	var data := terrain.heightmap
	data.ensure_storage()
	var area := data.get_width() * data.get_depth()
	var expected := mini(max_instances, maxi(0, int(round(area * density))))
	var placements: Array[Transform3D] = []
	var random := RandomNumberGenerator.new()
	random.seed = seed
	var max_angle_cosine := cos(deg_to_rad(max_slope_degrees))
	var attempts := maxi(expected * 12, expected)
	for attempt in attempts:
		if placements.size() >= expected:
			break
		var x := random.randf_range(0.0, data.get_width())
		var z := random.randf_range(0.0, data.get_depth())
		var y := data.sample_height(x, z)
		if y < min_elevation or y > max_elevation:
			continue
		var normal := (terrain.global_transform.basis * data.sample_normal(x, z)).normalized()
		if normal.dot(Vector3.UP) < max_angle_cosine:
			continue
		var angle := random.randf_range(0.0, TAU)
		var scale_value := random.randf_range(minf(min_scale, max_scale), maxf(min_scale, max_scale))
		var world_position := terrain.to_global(Vector3(x, y, z))
		var local_position := to_local(world_position)
		placements.append(Transform3D(Basis(Vector3.UP, angle).scaled(Vector3.ONE * scale_value), local_position))
	var result := MultiMesh.new()
	result.transform_format = MultiMesh.TRANSFORM_3D
	result.mesh = foliage_mesh
	result.instance_count = placements.size()
	for i in placements.size():
		result.set_instance_transform(i, placements[i])
	multimesh = result
	return placements.size()