@tool
extends Node3D
## Editable heightfield terrain with four paint layers and GPU-instanced foliage.
## This is a bounded prototype, not a streaming/infinite world implementation.

const TERRAIN_SHADER: Shader = preload("res://addons/open_world/terrain_layers.gdshader")

enum BrushMode { RAISE, LOWER, SMOOTH, PAINT }

@export_range(2, 128, 1) var resolution: int = 64
@export_range(0.25, 16.0, 0.25) var cell_size: float = 2.0
@export_range(0.25, 64.0, 0.25) var texture_repeat_meters: float = 4.0

@export_group("Terrain Layers")
@export var layer_0_color: Color = Color(0.37, 0.47, 0.24)
@export var layer_1_color: Color = Color(0.45, 0.36, 0.27)
@export var layer_2_color: Color = Color(0.53, 0.51, 0.48)
@export var layer_3_color: Color = Color(0.82, 0.79, 0.65)
@export var layer_0_texture: Texture2D
@export var layer_1_texture: Texture2D
@export var layer_2_texture: Texture2D
@export var layer_3_texture: Texture2D

@export_group("Foliage")
@export var foliage_mesh: Mesh

# Save the authoring data, not thousands of generated mesh/physics nodes.
@export_storage var height_data: PackedFloat32Array = PackedFloat32Array()
@export_storage var paint_data: PackedColorArray = PackedColorArray()
@export_storage var foliage_points: PackedVector3Array = PackedVector3Array()
@export_storage var foliage_scales: PackedFloat32Array = PackedFloat32Array()

var _mesh_instance: MeshInstance3D
var _collision_body: StaticBody3D
var _collision_shape: CollisionShape3D
var _foliage_instance: MultiMeshInstance3D
var _terrain_material: ShaderMaterial


func _ready() -> void:
	call_deferred("rebuild")


func _side() -> int:
	return clampi(resolution, 2, 128) + 1


func _index(x: int, z: int) -> int:
	return z * _side() + x


func _ensure_data() -> void:
	var size: int = _side() * _side()
	if height_data.size() != size:
		height_data.resize(size)
		height_data.fill(0.0)
	if paint_data.size() != size:
		paint_data.resize(size)
		paint_data.fill(Color(1.0, 0.0, 0.0, 0.0))


func _ensure_nodes() -> void:
	if not is_instance_valid(_mesh_instance):
		_mesh_instance = MeshInstance3D.new()
		_mesh_instance.name = "__OpenWorldTerrainMesh"
		add_child(_mesh_instance, false, Node.INTERNAL_MODE_FRONT)
	if not is_instance_valid(_collision_body):
		_collision_body = StaticBody3D.new()
		_collision_body.name = "__OpenWorldTerrainCollision"
		add_child(_collision_body, false, Node.INTERNAL_MODE_FRONT)
		_collision_shape = CollisionShape3D.new()
		_collision_body.add_child(_collision_shape, false, Node.INTERNAL_MODE_FRONT)
	if not is_instance_valid(_foliage_instance):
		_foliage_instance = MultiMeshInstance3D.new()
		_foliage_instance.name = "__OpenWorldFoliage"
		add_child(_foliage_instance, false, Node.INTERNAL_MODE_FRONT)


func get_collision_body() -> StaticBody3D:
	_ensure_nodes()
	return _collision_body


func get_height_copy() -> PackedFloat32Array:
	_ensure_data()
	return height_data.duplicate()


func get_paint_copy() -> PackedColorArray:
	_ensure_data()
	return paint_data.duplicate()


func restore_data(heights: PackedFloat32Array, weights: PackedColorArray) -> void:
	var expected: int = _side() * _side()
	if heights.size() != expected or weights.size() != expected:
		push_error("Terrain data dimensions do not match resolution.")
		return
	height_data = heights.duplicate()
	paint_data = weights.duplicate()
	rebuild()


func _height_at_grid(x: int, z: int) -> float:
	return height_data[_index(clampi(x, 0, _side() - 1), clampi(z, 0, _side() - 1))]


func sample_height(local_x: float, local_z: float) -> float:
	_ensure_data()
	var extent: float = float(_side() - 1)
	var gx: float = clampf(local_x / cell_size + extent * 0.5, 0.0, extent)
	var gz: float = clampf(local_z / cell_size + extent * 0.5, 0.0, extent)
	var x0: int = floori(gx)
	var z0: int = floori(gz)
	var x1: int = mini(x0 + 1, _side() - 1)
	var z1: int = mini(z0 + 1, _side() - 1)
	var fx: float = gx - float(x0)
	var fz: float = gz - float(z0)
	var a: float = lerpf(_height_at_grid(x0, z0), _height_at_grid(x1, z0), fx)
	var b: float = lerpf(_height_at_grid(x0, z1), _height_at_grid(x1, z1), fx)
	return lerpf(a, b, fz)


func _normal_at(x: int, z: int) -> Vector3:
	var dx: float = _height_at_grid(x - 1, z) - _height_at_grid(x + 1, z)
	var dz: float = _height_at_grid(x, z - 1) - _height_at_grid(x, z + 1)
	return Vector3(dx, 2.0 * cell_size, dz).normalized()


func _refresh_material() -> void:
	if _terrain_material == null:
		_terrain_material = ShaderMaterial.new()
		_terrain_material.shader = TERRAIN_SHADER
	var colors: Array[Color] = [layer_0_color, layer_1_color, layer_2_color, layer_3_color]
	var textures: Array[Texture2D] = [layer_0_texture, layer_1_texture, layer_2_texture, layer_3_texture]
	for layer in range(4):
		_terrain_material.set_shader_parameter("tint_%d" % layer, colors[layer])
		_terrain_material.set_shader_parameter("use_texture_%d" % layer, textures[layer] != null)
		if textures[layer] != null:
			_terrain_material.set_shader_parameter("texture_%d" % layer, textures[layer])


func rebuild() -> void:
	_ensure_data()
	_ensure_nodes()
	_refresh_material()
	var side: int = _side()
	var vertex_count: int = side * side
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var uv := PackedVector2Array()
	var indices := PackedInt32Array()
	vertices.resize(vertex_count)
	normals.resize(vertex_count)
	colors.resize(vertex_count)
	uv.resize(vertex_count)
	indices.resize((side - 1) * (side - 1) * 6)
	var half: float = float(side - 1) * 0.5
	for z in range(side):
		for x in range(side):
			var id: int = _index(x, z)
			vertices[id] = Vector3((float(x) - half) * cell_size, height_data[id], (float(z) - half) * cell_size)
			normals[id] = _normal_at(x, z)
			colors[id] = paint_data[id]
			uv[id] = Vector2(float(x) * cell_size, float(z) * cell_size) / maxf(0.25, texture_repeat_meters)

	var cursor := 0
	for z in range(side - 1):
		for x in range(side - 1):
			var a: int = _index(x, z)
			var b: int = _index(x + 1, z)
			var c: int = _index(x, z + 1)
			var d: int = _index(x + 1, z + 1)
			# Winding faces +Y (XZ is left-handed as viewed from above).
			for id in [a, c, b, b, c, d]:
				indices[cursor] = id
				cursor += 1

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_TEX_UV] = uv
	arrays[Mesh.ARRAY_INDEX] = indices
	var output := ArrayMesh.new()
	output.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	output.surface_set_material(0, _terrain_material)
	_mesh_instance.mesh = output
	_collision_shape.shape = output.create_trimesh_shape()
	_refresh_foliage()


func apply_brush(world_point: Vector3, radius: float, strength: float, mode: BrushMode, layer: int = 0) -> int:
	_ensure_data()
	if radius <= 0.0 or strength <= 0.0:
		return 0
	var p: Vector3 = to_local(world_point)
	var half: float = float(_side() - 1) * 0.5
	var gx: float = p.x / cell_size + half
	var gz: float = p.z / cell_size + half
	var reach: float = radius / cell_size
	var x_min: int = maxi(0, floori(gx - reach))
	var x_max: int = mini(_side() - 1, ceili(gx + reach))
	var z_min: int = maxi(0, floori(gz - reach))
	var z_max: int = mini(_side() - 1, ceili(gz + reach))
	var old_heights: PackedFloat32Array = height_data.duplicate()
	var affected := 0
	var target: Color = Color(1.0, 0.0, 0.0, 0.0)
	match clampi(layer, 0, 3):
		1: target = Color(0.0, 1.0, 0.0, 0.0)
		2: target = Color(0.0, 0.0, 1.0, 0.0)
		3: target = Color(0.0, 0.0, 0.0, 1.0)
	for z in range(z_min, z_max + 1):
		for x in range(x_min, x_max + 1):
			var dist: float = Vector2((float(x) - gx) * cell_size, (float(z) - gz) * cell_size).length()
			if dist > radius:
				continue
			var amount: float = strength * pow(1.0 - dist / radius, 2.0)
			var id: int = _index(x, z)
			match mode:
				BrushMode.RAISE: height_data[id] += amount
				BrushMode.LOWER: height_data[id] -= amount
				BrushMode.SMOOTH:
					var avg: float = (
						old_heights[_index(maxi(x - 1, 0), z)] +
						old_heights[_index(mini(x + 1, _side() - 1), z)] +
						old_heights[_index(x, maxi(z - 1, 0))] +
						old_heights[_index(x, mini(z + 1, _side() - 1))]
					) * 0.25
					height_data[id] = lerpf(old_heights[id], avg, clampf(amount, 0.0, 1.0))
				BrushMode.PAINT: paint_data[id] = paint_data[id].lerp(target, clampf(amount, 0.0, 1.0))
			affected += 1
	if affected > 0:
		rebuild()
	return affected


func thermal_erode(iterations: int = 1, talus: float = 0.25, rate: float = 0.2) -> void:
	_ensure_data()
	var side: int = _side()
	var safe_rate: float = clampf(rate, 0.0, 0.25)
	for iteration in range(clampi(iterations, 0, 100)):
		var delta := PackedFloat32Array()
		delta.resize(height_data.size())
		delta.fill(0.0)
		for z in range(side):
			for x in range(side):
				var id: int = _index(x, z)
				for neighbor in [Vector2i(x + 1, z), Vector2i(x, z + 1)]:
					if neighbor.x >= side or neighbor.y >= side:
						continue
					var other: int = _index(neighbor.x, neighbor.y)
					var difference: float = height_data[id] - height_data[other]
					var moved: float = maxf(absf(difference) - maxf(0.0, talus), 0.0) * safe_rate
					if difference > 0.0:
						delta[id] -= moved
						delta[other] += moved
					elif difference < 0.0:
						delta[id] += moved
						delta[other] -= moved
		for id in range(height_data.size()):
			height_data[id] += delta[id]
	rebuild()


func get_foliage_points_copy() -> PackedVector3Array:
	return foliage_points.duplicate()


func get_foliage_scales_copy() -> PackedFloat32Array:
	return foliage_scales.duplicate()


func restore_foliage(points: PackedVector3Array, scales: PackedFloat32Array) -> void:
	if points.size() != scales.size():
		push_error("Foliage point and scale arrays must have the same length.")
		return
	foliage_points = points.duplicate()
	foliage_scales = scales.duplicate()
	_refresh_foliage()


func scatter_foliage(count: int, seed_value: int = 1, min_up: float = 0.7) -> void:
	_ensure_data()
	var random := RandomNumberGenerator.new()
	random.seed = seed_value
	var extent: float = float(_side() - 1) * cell_size * 0.5
	var points := PackedVector3Array()
	var scales := PackedFloat32Array()
	for attempt in range(clampi(count, 0, 10000)):
		var x: float = random.randf_range(-extent, extent)
		var z: float = random.randf_range(-extent, extent)
		var gx: int = clampi(roundi(x / cell_size + float(_side() - 1) * 0.5), 0, _side() - 1)
		var gz: int = clampi(roundi(z / cell_size + float(_side() - 1) * 0.5), 0, _side() - 1)
		if _normal_at(gx, gz).y < clampf(min_up, 0.0, 1.0):
			continue
		points.append(Vector3(x, 0.0, z))
		scales.append(random.randf_range(0.8, 1.2))
	restore_foliage(points, scales)


func _refresh_foliage() -> void:
	_ensure_nodes()
	if foliage_mesh == null or foliage_points.is_empty():
		_foliage_instance.multimesh = null
		return
	if foliage_points.size() != foliage_scales.size():
		push_error("Invalid foliage data: mismatched arrays.")
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = foliage_mesh
	mm.instance_count = foliage_points.size()
	for i in range(foliage_points.size()):
		var p: Vector3 = foliage_points[i]
		var basis := Basis(Vector3.UP, float(i) * 2.39996323)
		basis = basis.scaled(Vector3.ONE * foliage_scales[i])
		mm.set_instance_transform(i, Transform3D(basis, Vector3(p.x, sample_height(p.x, p.z), p.z)))
	_foliage_instance.multimesh = mm
