@tool
extends MeshInstance3D
class_name OWTerrain3D
## Runtime/editable triangulated heightfield. Two blended material layers.

const TERRAIN_SHADER := preload("res://addons/open_world_toolkit/terrain_layers.gdshader")

@export var pcg_graph: OWPCGGraph

@export var heightmap: OWHeightmap:
	set(value):
		if heightmap != null and heightmap.changed.is_connected(rebuild_mesh):
			heightmap.changed.disconnect(rebuild_mesh)
		heightmap = value
		if heightmap != null and not heightmap.changed.is_connected(rebuild_mesh):
			heightmap.changed.connect(rebuild_mesh)
		if is_inside_tree():
			rebuild_mesh()

@export var ground_color: Color = Color(0.25, 0.38, 0.19):
	set(value):
		ground_color = value
		_update_material()
@export var detail_color: Color = Color(0.45, 0.38, 0.31):
	set(value):
		detail_color = value
		_update_material()
@export var ground_texture: Texture2D:
	set(value):
		ground_texture = value
		_update_material()
@export var detail_texture: Texture2D:
	set(value):
		detail_texture = value
		_update_material()
@export_range(0.01, 128.0, 0.01) var uv_repeats: float = 4.0:
	set(value):
		uv_repeats = value
		_update_material()

var _terrain_material: ShaderMaterial


func _enter_tree() -> void:
	if heightmap == null:
		heightmap = OWHeightmap.new()
	if heightmap != null and not heightmap.changed.is_connected(rebuild_mesh):
		heightmap.changed.connect(rebuild_mesh)
	rebuild_mesh()


func _exit_tree() -> void:
	if heightmap != null and heightmap.changed.is_connected(rebuild_mesh):
		heightmap.changed.disconnect(rebuild_mesh)


func _update_material() -> void:
	if _terrain_material == null:
		return
	_terrain_material.set_shader_parameter("ground_color", ground_color)
	_terrain_material.set_shader_parameter("detail_color", detail_color)
	_terrain_material.set_shader_parameter("ground_texture", ground_texture)
	_terrain_material.set_shader_parameter("detail_texture", detail_texture)
	_terrain_material.set_shader_parameter("use_ground_texture", ground_texture != null)
	_terrain_material.set_shader_parameter("use_detail_texture", detail_texture != null)
	_terrain_material.set_shader_parameter("uv_repeats", uv_repeats)


func rebuild_mesh() -> void:
	if heightmap == null:
		mesh = null
		return
	heightmap.ensure_storage()
	var width := heightmap.columns
	var depth := heightmap.rows
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	var count := width * depth
	vertices.resize(count)
	normals.resize(count)
	uvs.resize(count)
	colors.resize(count)
	indices.resize((width - 1) * (depth - 1) * 6)
	for z in depth:
		for x in width:
			var idx := z * width + x
			var px := x * heightmap.cell_size
			var pz := z * heightmap.cell_size
			vertices[idx] = Vector3(px, heightmap.heights[idx], pz)
			normals[idx] = heightmap.sample_normal(px, pz)
			uvs[idx] = Vector2(float(x) / float(width - 1), float(z) / float(depth - 1))
			colors[idx] = Color(heightmap.blend[idx], 0.0, 0.0, 1.0)
	var triangle_index := 0
	for z in depth - 1:
		for x in width - 1:
			var top_left := z * width + x
			for corner in [top_left, top_left + width, top_left + 1, top_left + 1, top_left + width, top_left + width + 1]:
				indices[triangle_index] = corner
				triangle_index += 1
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var generated := ArrayMesh.new()
	generated.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	if _terrain_material == null:
		_terrain_material = ShaderMaterial.new()
		_terrain_material.shader = TERRAIN_SHADER
	_update_material()
	generated.surface_set_material(0, _terrain_material)
	mesh = generated


func intersect_world_ray(origin: Vector3, direction: Vector3, distance: float = 4096.0) -> Variant:
	## Ray-march against the heightfield. Returns world-space hit or null.
	if heightmap == null or distance <= 0.0:
		return null
	var inverse := global_transform.affine_inverse()
	var local_origin := inverse * origin
	var local_direction := (inverse.basis * direction).normalized()
	if local_direction.is_zero_approx():
		return null
	var max_height := 0.0
	var min_height := 0.0
	for h in heightmap.heights:
		max_height = maxf(max_height, h)
		min_height = minf(min_height, h)
	var bounds := AABB(Vector3(0.0, min_height - 0.1, 0.0), Vector3(heightmap.get_width(), max_height - min_height + 0.2, heightmap.get_depth()))
	if bounds.intersects_ray(local_origin, local_direction) == null:
		return null
	var t_start := 0.0
	var t_end := distance
	for axis in 3:
		var coordinate := local_origin[axis]
		var component := local_direction[axis]
		var low := bounds.position[axis]
		var high := bounds.end[axis]
		if absf(component) < 0.000001:
			if coordinate < low or coordinate > high:
				return null
		else:
			var t0 := (low - coordinate) / component
			var t1 := (high - coordinate) / component
			t_start = maxf(t_start, minf(t0, t1))
			t_end = minf(t_end, maxf(t0, t1))
	if t_start > t_end:
		return null
	var segments := clampi(int(ceil((t_end - t_start) / maxf(0.1, heightmap.cell_size * 0.25))), 1, 2048)
	var prev_t := t_start
	var prev := local_origin + local_direction * prev_t
	var prev_difference := prev.y - heightmap.sample_height(prev.x, prev.z)
	for step in range(1, segments + 1):
		var t := lerpf(t_start, t_end, float(step) / float(segments))
		var point := local_origin + local_direction * t
		var difference := point.y - heightmap.sample_height(point.x, point.z)
		if prev_difference >= 0.0 and difference <= 0.0:
			var lo := prev_t
			var hi := t
			for refinement in 12:
				var midpoint := (lo + hi) * 0.5
				var current := local_origin + local_direction * midpoint
				if current.y > heightmap.sample_height(current.x, current.z):
					lo = midpoint
				else:
					hi = midpoint
			return global_transform * (local_origin + local_direction * ((lo + hi) * 0.5))
		prev_t = t
		prev_difference = difference
	return null