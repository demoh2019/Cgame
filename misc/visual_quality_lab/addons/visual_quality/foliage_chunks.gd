extends Node3D
class_name ChunkedFoliage3D
## Scene-local vegetation built from small GPU-instanced cells instead of one
## unbounded MultiMesh. Each cell has its own culling AABB and visibility range.

@export_range(1, 9, 1) var chunks_per_axis: int = 5
@export_range(4.0, 30.0, 1.0) var chunk_size: float = 14.0
@export_range(0, 64, 1) var trees_per_chunk: int = 24
@export_range(0.0, 30.0, 1.0) var clear_radius: float = 12.0
@export var world_seed: int = 20261120
@export var spawn_on_ready: bool = true

var _trunk_instances: Array[MultiMeshInstance3D] = []
var _leaf_instances: Array[MultiMeshInstance3D] = []
var _generated_root: Node3D
var _quality: int = 1


func _ready() -> void:
	if spawn_on_ready:
		rebuild()


func rebuild() -> void:
	if is_instance_valid(_generated_root):
		remove_child(_generated_root)
		_generated_root.queue_free()
	_trunk_instances.clear()
	_leaf_instances.clear()
	_generated_root = Node3D.new()
	_generated_root.name = "GeneratedFoliage"
	add_child(_generated_root)
	if trees_per_chunk <= 0:
		return
	var trunk_mesh: CylinderMesh = CylinderMesh.new()
	trunk_mesh.top_radius = 0.10
	trunk_mesh.bottom_radius = 0.19
	trunk_mesh.height = 2.0
	trunk_mesh.radial_segments = 6
	var trunk_material: StandardMaterial3D = StandardMaterial3D.new()
	trunk_material.albedo_color = Color(0.29, 0.17, 0.095)
	trunk_material.roughness = 1.0
	trunk_mesh.material = trunk_material
	var leaf_mesh: SphereMesh = SphereMesh.new()
	leaf_mesh.radius = 0.88
	leaf_mesh.height = 1.76
	leaf_mesh.radial_segments = 8
	leaf_mesh.rings = 4
	var leaf_material: StandardMaterial3D = StandardMaterial3D.new()
	leaf_material.albedo_color = Color(0.07, 0.27, 0.17)
	leaf_material.roughness = 0.92
	leaf_mesh.material = leaf_material
	for z in range(chunks_per_axis):
		for x in range(chunks_per_axis):
			var half: float = float(chunks_per_axis - 1) * 0.5
			var center: Vector2 = Vector2((float(x) - half) * chunk_size, (float(z) - half) * chunk_size)
			var positions: PackedVector3Array = sample_cell_positions(
				world_seed, x, z, trees_per_chunk, chunk_size, center, clear_radius
			)
			if positions.is_empty():
				continue
			var rng: RandomNumberGenerator = RandomNumberGenerator.new()
			rng.seed = cell_seed(world_seed + 991, x, z)
			var trunks: MultiMesh = MultiMesh.new()
			trunks.transform_format = MultiMesh.TRANSFORM_3D
			trunks.mesh = trunk_mesh
			trunks.instance_count = positions.size()
			var leaves: MultiMesh = MultiMesh.new()
			leaves.transform_format = MultiMesh.TRANSFORM_3D
			leaves.mesh = leaf_mesh
			leaves.instance_count = positions.size()
			for i in range(positions.size()):
				var scale: float = rng.randf_range(0.8, 1.35)
				var local: Vector3 = positions[i]
				var yaw: float = rng.randf_range(0.0, TAU)
				var trunk_basis: Basis = Basis(Vector3.UP, yaw).scaled(Vector3(scale, scale, scale))
				trunks.set_instance_transform(i, Transform3D(trunk_basis, local + Vector3(0, scale, 0)))
				var leaf_basis: Basis = Basis(Vector3.UP, yaw).scaled(Vector3(scale, scale * 1.15, scale))
				leaves.set_instance_transform(i, Transform3D(leaf_basis, local + Vector3(0, scale * 2.45, 0)))
			var bounds: AABB = AABB(Vector3(-chunk_size * 0.5, -0.25, -chunk_size * 0.5), Vector3(chunk_size, 5.5, chunk_size))
			trunks.custom_aabb = bounds
			leaves.custom_aabb = bounds
			var cell: Node3D = Node3D.new()
			cell.name = "Cell_%d_%d" % [x, z]
			cell.position = Vector3(center.x, 0.0, center.y)
			_generated_root.add_child(cell)
			var trunks_node: MultiMeshInstance3D = MultiMeshInstance3D.new()
			trunks_node.name = "Trunks"
			trunks_node.multimesh = trunks
			cell.add_child(trunks_node)
			var leaves_node: MultiMeshInstance3D = MultiMeshInstance3D.new()
			leaves_node.name = "Canopies"
			leaves_node.multimesh = leaves
			cell.add_child(leaves_node)
			_trunk_instances.append(trunks_node)
			_leaf_instances.append(leaves_node)
	set_quality(_quality)


func set_quality(profile: int) -> void:
	_quality = clampi(profile, 0, 2)
	var fractions: PackedFloat32Array = PackedFloat32Array([0.35, 0.65, 1.0])
	var distances: PackedFloat32Array = PackedFloat32Array([28.0, 48.0, 78.0])
	for instance in _trunk_instances + _leaf_instances:
		instance.multimesh.visible_instance_count = mini(
			instance.multimesh.instance_count,
			ceili(float(instance.multimesh.instance_count) * fractions[_quality])
		)
		instance.visibility_range_end = distances[_quality]
		instance.visibility_range_end_margin = 5.0


func cell_count() -> int:
	return _trunk_instances.size()


static func cell_seed(base_seed: int, x: int, z: int) -> int:
	return base_seed ^ (x * 73856093) ^ (z * 19349663)


## Testable pure sampler; no global RNG, file access, GPU or scene dependencies.
static func sample_cell_positions(base_seed: int, x: int, z: int, count: int,
		cell_width: float, center: Vector2, exclusion_radius: float) -> PackedVector3Array:
	var out: PackedVector3Array = PackedVector3Array()
	if count <= 0 or not is_finite(cell_width) or cell_width <= 0.0:
		return out
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = cell_seed(base_seed, x, z)
	var safe_count: int = mini(count, 64)
	var clear_radius_squared: float = maxf(exclusion_radius, 0.0) * maxf(exclusion_radius, 0.0)
	# Bounded attempts keep an entirely excluded cell from stalling the editor.
	for _attempt in range(safe_count * 5):
		if out.size() >= safe_count:
			break
		var local_x: float = rng.randf_range(-cell_width * 0.5, cell_width * 0.5)
		var local_z: float = rng.randf_range(-cell_width * 0.5, cell_width * 0.5)
		var world_pos: Vector2 = center + Vector2(local_x, local_z)
		if world_pos.length_squared() < clear_radius_squared:
			continue
		out.append(Vector3(local_x, 0.0, local_z))
	return out
