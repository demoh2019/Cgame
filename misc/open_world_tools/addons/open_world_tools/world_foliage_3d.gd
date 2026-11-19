@tool
extends MultiMeshInstance3D
class_name WorldFoliage3D
## Deterministic GPU-instanced placement on a WorldTerrain3D surface.

@export var terrain: WorldTerrain3D
@export var foliage_mesh: Mesh
@export_range(0, 100000, 1) var placement_count: int = 350
@export_range(0, 90, 1) var max_slope_degrees: float = 35.0
@export_range(0.01, 10.0, 0.01) var min_instance_scale: float = 0.75
@export_range(0.01, 10.0, 0.01) var max_instance_scale: float = 1.4
@export var random_seed: int = 1337


func scatter() -> int:
	if terrain == null or foliage_mesh == null:
		multimesh = null
		return 0
	terrain.initialize_storage()
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = random_seed
	var edge: float = float(terrain.resolution - 1) * terrain.cell_size
	var slope_threshold: float = cos(deg_to_rad(max_slope_degrees))
	var transforms: Array[Transform3D] = []
	for i in range(placement_count):
		for attempt in range(12):
			var x: float = rng.randf_range(0.0, edge)
			var z: float = rng.randf_range(0.0, edge)
			if terrain.get_normal_at(x, z).dot(Vector3.UP) < slope_threshold:
				continue
			var pos: Vector3 = Vector3(x, terrain.get_height_at(x, z), z)
			var yaw: float = rng.randf_range(0.0, TAU)
			var scale_value: float = rng.randf_range(min_instance_scale, maxf(min_instance_scale, max_instance_scale))
			var basis: Basis = Basis(Vector3.UP, yaw).scaled(Vector3.ONE * scale_value)
			# MultiMesh transforms are local to this node, not the terrain.
			transforms.append(global_transform.affine_inverse() * (terrain.global_transform * Transform3D(basis, pos)))
			break
	var instances: MultiMesh = MultiMesh.new()
	instances.transform_format = MultiMesh.TRANSFORM_3D
	instances.mesh = foliage_mesh
	instances.instance_count = transforms.size()
	for i in range(transforms.size()):
		instances.set_instance_transform(i, transforms[i])
	multimesh = instances
	return transforms.size()