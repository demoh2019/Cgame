@tool
extends Node3D
class_name WorldTerrain3D
## Experimental editable heightfield. X/Z coordinates start at the node origin.
## Stored arrays belong to the scene; generated mesh children are transient.

enum BrushMode { RAISE, SMOOTH, FLATTEN, PAINT, PAINT_TEXTURE_LAYER }

@export_range(3, 513, 1) var resolution: int = 65
@export_range(0.25, 32.0, 0.25) var cell_size: float = 2.0
@export_range(2, 128, 1) var chunk_cells: int = 32
@export var surface_material: Material
@export var use_texture_layers: bool = false
@export_range(0.1, 256.0, 0.1) var texture_repeat: float = 12.0
@export var texture_0: Texture2D
@export var texture_1: Texture2D
@export var texture_2: Texture2D
@export var texture_3: Texture2D
@export var enable_collision: bool = false
@export_storage var height_data: PackedFloat32Array = PackedFloat32Array()
@export_storage var color_data: PackedColorArray = PackedColorArray()
@export_storage var weight_data: PackedColorArray = PackedColorArray()

const GENERATED_NAME: String = "_WorldTerrainGenerated"
const DEFAULT_COLOR: Color = Color(0.32, 0.48, 0.26, 1.0)
const DEFAULT_WEIGHTS: Color = Color(1.0, 0.0, 0.0, 0.0)
const SPLAT_SHADER = preload("res://addons/open_world_tools/terrain_splat.gdshader")

func _ready() -> void:
	initialize_storage()
	rebuild()


func initialize_storage() -> void:
	resolution = clampi(resolution, 3, 513)
	cell_size = maxf(cell_size, 0.01)
	chunk_cells = clampi(chunk_cells, 2, 128)
	var needed: int = resolution * resolution
	if height_data.size() != needed:
		height_data.resize(needed)
		height_data.fill(0.0)
	if color_data.size() != needed:
		color_data.resize(needed)
		color_data.fill(DEFAULT_COLOR)
	if weight_data.size() != needed:
		weight_data.resize(needed)
		weight_data.fill(DEFAULT_WEIGHTS)


func sample_index(x: int, z: int) -> int:
	return z * resolution + x


func contains_xz(x: float, z: float) -> bool:
	var span: float = float(resolution - 1) * cell_size
	return x >= 0.0 and z >= 0.0 and x <= span and z <= span


func get_height_at(x: float, z: float) -> float:
	initialize_storage()
	var grid_x: float = clampf(x / cell_size, 0.0, float(resolution - 1))
	var grid_z: float = clampf(z / cell_size, 0.0, float(resolution - 1))
	var x0: int = floori(grid_x)
	var z0: int = floori(grid_z)
	var x1: int = mini(x0 + 1, resolution - 1)
	var z1: int = mini(z0 + 1, resolution - 1)
	var a: float = lerpf(height_data[sample_index(x0, z0)], height_data[sample_index(x1, z0)], grid_x - float(x0))
	var b: float = lerpf(height_data[sample_index(x0, z1)], height_data[sample_index(x1, z1)], grid_x - float(x0))
	return lerpf(a, b, grid_z - float(z0))


func get_normal_at(x: float, z: float) -> Vector3:
	var dx: float = get_height_at(x + cell_size, z) - get_height_at(x - cell_size, z)
	var dz: float = get_height_at(x, z + cell_size) - get_height_at(x, z - cell_size)
	return Vector3(-dx, 2.0 * cell_size, -dz).normalized()


func restore_samples(heights: PackedFloat32Array, colors: PackedColorArray, weights: PackedColorArray = PackedColorArray()) -> void:
	if heights.size() != resolution * resolution or colors.size() != resolution * resolution or (weights.size() > 0 and weights.size() != resolution * resolution):
		push_warning("Terrain snapshot dimensions do not match current resolution.")
		return
	height_data = heights.duplicate()
	color_data = colors.duplicate()
	if weights.size() == resolution * resolution:
		weight_data = weights.duplicate()
	rebuild()


func apply_brush(local_position: Vector3, radius: float, strength: float, mode: int, target_height: float = 0.0, paint_color: Color = Color.WHITE, layer_index: int = 0) -> int:
	initialize_storage()
	if radius <= 0.0 or strength == 0.0 or (strength < 0.0 and mode != BrushMode.RAISE):
		return 0
	var previous: PackedFloat32Array = height_data.duplicate()
	var changed: int = 0
	var center_x: float = local_position.x / cell_size
	var center_z: float = local_position.z / cell_size
	var steps: float = radius / cell_size
	var left: int = maxi(0, floori(center_x - steps))
	var right: int = mini(resolution - 1, ceili(center_x + steps))
	var top: int = maxi(0, floori(center_z - steps))
	var bottom: int = mini(resolution - 1, ceili(center_z + steps))
	for z in range(top, bottom + 1):
		for x in range(left, right + 1):
			var distance: float = Vector2(float(x) * cell_size - local_position.x, float(z) * cell_size - local_position.z).length()
			if distance > radius:
				continue
			var falloff: float = pow(1.0 - distance / radius, 2.0)
			var amount: float = strength * falloff
			var index: int = sample_index(x, z)
			match mode:
				BrushMode.RAISE:
					height_data[index] += amount
				BrushMode.SMOOTH:
					var total: float = 0.0
					var count: int = 0
					for dz in range(-1, 2):
						for dx in range(-1, 2):
							var nx: int = x + dx
							var nz: int = z + dz
							if nx >= 0 and nx < resolution and nz >= 0 and nz < resolution:
								total += previous[sample_index(nx, nz)]
								count += 1
					height_data[index] = lerpf(previous[index], total / float(count), clampf(amount, 0.0, 1.0))
				BrushMode.FLATTEN:
					height_data[index] = lerpf(previous[index], target_height, clampf(amount, 0.0, 1.0))
				BrushMode.PAINT:
					color_data[index] = color_data[index].lerp(paint_color, clampf(amount, 0.0, 1.0))
				BrushMode.PAINT_TEXTURE_LAYER:
					var target_weights: Color = DEFAULT_WEIGHTS
					match layer_index:
						0: target_weights = Color(1.0, 0.0, 0.0, 0.0)
						1: target_weights = Color(0.0, 1.0, 0.0, 0.0)
						2: target_weights = Color(0.0, 0.0, 1.0, 0.0)
						3: target_weights = Color(0.0, 0.0, 0.0, 1.0)
						_: continue
					weight_data[index] = weight_data[index].lerp(target_weights, clampf(amount, 0.0, 1.0))
			changed += 1
	if changed > 0:
		rebuild()
	return changed


func erode_thermal(iterations: int, talus: float, rate: float) -> void:
	## Distribute material between adjacent samples without losing total height.
	initialize_storage()
	if iterations <= 0 or rate <= 0.0:
		return
	rate = clampf(rate, 0.0, 1.0)
	talus = maxf(talus, 0.0)
	for _step in range(iterations):
		var deltas: PackedFloat32Array = PackedFloat32Array()
		deltas.resize(height_data.size())
		deltas.fill(0.0)
		for z in range(resolution):
			for x in range(resolution):
				var a: int = sample_index(x, z)
				for offset in [Vector2i(1, 0), Vector2i(0, 1)]:
					var nx: int = x + offset.x
					var nz: int = z + offset.y
					if nx >= resolution or nz >= resolution:
						continue
					var b: int = sample_index(nx, nz)
					var diff: float = height_data[a] - height_data[b]
					if absf(diff) <= talus:
						continue
					var flow: float = (absf(diff) - talus) * rate * 0.125
					if diff < 0.0:
						flow = -flow
					deltas[a] -= flow
					deltas[b] += flow
		for index in range(height_data.size()):
			height_data[index] += deltas[index]
	rebuild()


func rebuild() -> void:
	initialize_storage()
	if not is_inside_tree():
		return
	var root: Node3D = get_node_or_null(GENERATED_NAME) as Node3D
	if root == null:
		root = Node3D.new()
		root.name = GENERATED_NAME
		add_child(root, false, Node.INTERNAL_MODE_BACK)
	for child in root.get_children():
		root.remove_child(child)
		child.free()
	var material: Material = surface_material
	if material == null and use_texture_layers:
		material = _make_splat_material()
	if material == null:
		var fallback: StandardMaterial3D = StandardMaterial3D.new()
		fallback.vertex_color_use_as_albedo = true
		fallback.roughness = 1.0
		material = fallback
	for start_z in range(0, resolution - 1, chunk_cells):
		for start_x in range(0, resolution - 1, chunk_cells):
			var end_x: int = mini(start_x + chunk_cells, resolution - 1)
			var end_z: int = mini(start_z + chunk_cells, resolution - 1)
			var surface: SurfaceTool = SurfaceTool.new()
			surface.begin(Mesh.PRIMITIVE_TRIANGLES)
			for z in range(start_z, end_z):
				for x in range(start_x, end_x):
					_add_vertex(surface, x, z)
					_add_vertex(surface, x, z + 1)
					_add_vertex(surface, x + 1, z)
					_add_vertex(surface, x + 1, z)
					_add_vertex(surface, x, z + 1)
					_add_vertex(surface, x + 1, z + 1)
			var mesh: ArrayMesh = surface.commit()
			var chunk: MeshInstance3D = MeshInstance3D.new()
			chunk.name = "Chunk_%d_%d" % [start_x, start_z]
			chunk.mesh = mesh
			chunk.material_override = material
			root.add_child(chunk)
			if enable_collision:
				var body: StaticBody3D = StaticBody3D.new()
				var shape: CollisionShape3D = CollisionShape3D.new()
				shape.shape = mesh.create_trimesh_shape()
				body.add_child(shape)
				chunk.add_child(body)


func _add_vertex(surface: SurfaceTool, x: int, z: int) -> void:
	var position: Vector3 = Vector3(float(x) * cell_size, height_data[sample_index(x, z)], float(z) * cell_size)
	surface.set_color(weight_data[sample_index(x, z)] if use_texture_layers else color_data[sample_index(x, z)])
	surface.set_uv(Vector2(float(x) / float(resolution - 1), float(z) / float(resolution - 1)))
	surface.set_normal(get_normal_at(position.x, position.z))
	surface.add_vertex(position)


func _make_splat_material() -> ShaderMaterial:
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = SPLAT_SHADER
	material.set_shader_parameter("texture_repeat", texture_repeat)
	for i in range(4):
		var texture: Texture2D = null
		match i:
			0: texture = texture_0
			1: texture = texture_1
			2: texture = texture_2
			3: texture = texture_3
		if texture == null:
			var image: Image = Image.create(1, 1, false, Image.FORMAT_RGBA8)
			image.fill(Color.WHITE)
			texture = ImageTexture.create_from_image(image)
		material.set_shader_parameter("layer_%d" % i, texture)
	return material


func import_heightmap(image: Image, max_height: float) -> bool:
	if image == null or image.is_empty() or max_height < 0.0:
		return false
	initialize_storage()
	for z in range(resolution):
		for x in range(resolution):
			var image_x: int = roundi(float(x) / float(resolution - 1) * float(image.get_width() - 1))
			var image_y: int = roundi(float(z) / float(resolution - 1) * float(image.get_height() - 1))
			height_data[sample_index(x, z)] = image.get_pixel(image_x, image_y).get_luminance() * max_height
	rebuild()
	return true