extends RefCounted
## GPU-driven meshlet renderer. Uploads meshlets (scripts/shared/meshlets.gd) to storage
## buffers and, when the rendering device reports RenderingDevice.SUPPORTS_MESH_SHADER
## (Vulkan VK_EXT_mesh_shader), draws them with a task + mesh shader pipeline from a
## CompositorEffect: the task stage culls meshlets (frustum + normal cone) on the GPU and
## launches one mesh work group per survivor, so the CPU never touches per-meshlet visibility.
## Without mesh shader support (headless, Metal, old GPUs) it falls back to an ArrayMesh /
## MultiMesh built from the same meshlets, using an exact CPU port of the task-shader culling.
##
## Credits / sources (original implementation, project license; concepts only):
##   - meshoptimizer by Arseny Kapoulkine, MIT license (meshlet layout, normal-cone test).
##   - Khronos VK_EXT_mesh_shader / GL_EXT_mesh_shader specifications (task payload, mesh outputs).
##   - Public Godot 4 CompositorEffect + RenderingDevice tutorials (pattern, CC-BY-3.0 docs).
##
## The mesh shader path is UNVERIFIED until run on a GPU with VK_EXT_mesh_shader; the packing,
## CPU culling and fallback paths are covered by tests/test_meshlet_renderer.gd.
##
## Packed GPU layout (all little endian, std430 / std140 compatible):
##   positions   vec4 per vertex slot in each resident page (xyz, 1.0)
##   vertex_ids  uint per meshlet vertex slot: absolute physical GPU slot vertex offset
##   triangles   uint per triangle: a | b << 8 | c << 16 (local indices into the meshlet vertex list)
##   descriptors 48 bytes per meshlet: uvec4 (vertex_offset, triangle_offset, vertex_count,
##               triangle_count), vec4 (center.xyz, radius), vec4 (cone axis.xyz, cone cutoff)
##   frame UBO   256 bytes: mat4 view_proj, mat4 model, vec4 planes[6], vec4 camera_pos,
##               uvec4 (meshlet_count, flags, 0, 0)
##
## Indirect extension point: a compute culling pass can write {x, 1, 1} commands into a buffer
## created with STORAGE_BUFFER_USAGE_DISPATCH_INDIRECT and replace the direct draw below with
## RenderingDevice.draw_list_draw_mesh_tasks_indirect().

const Meshlets = preload("res://scripts/shared/meshlets.gd")
const PagePolicy = preload("res://scripts/shared/meshlet_page_streaming.gd")
const ClusterLOD = preload("res://scripts/shared/cluster_lod.gd")

const TASK_SHADER_PATH: String = "res://shaders/compute/meshlet.task.glsl"
const MESH_SHADER_PATH: String = "res://shaders/compute/meshlet.mesh.glsl"
const EFFECT_SCRIPT_PATH: String = "res://scripts/client/meshlet_compositor_effect.gd"

const MAX_MESHLET_VERTICES: int = 64
const MAX_MESHLET_TRIANGLES: int = 124
const TASK_GROUP_SIZE: int = 32
## RenderingDevice.MESH_TASK_MAX_GROUP_COUNT task groups of TASK_GROUP_SIZE meshlets each.
const MAX_MESHLETS: int = 65535 * 32
const DESCRIPTOR_STRIDE: int = 48
const FRAME_DATA_SIZE: int = 256
const FLAG_FRUSTUM_CULL: int = 1
const FLAG_CONE_CULL: int = 2

enum DrawPath { NONE, MESH_SHADER, FALLBACK }

## RenderingDevice.SUPPORTS_MESH_SHADER by value, so this script still parses (and falls back)
## on engine builds that predate the feature. Mesh APIs are called dynamically for the same reason.
const FEATURE_MESH_SHADER: int = 16

## Forces the ArrayMesh fallback even when mesh shaders are available (debugging, A/B tests).
var force_fallback: bool = false
var cull_flags: int = FLAG_FRUSTUM_CULL | FLAG_CONE_CULL
var model: Transform3D = Transform3D.IDENTITY
var last_path: int = DrawPath.NONE
var meshlet_count: int = 0
var vertex_count: int = 0
var last_error: String = ""
## GPU-only geometry page pool. The task shader still culls individual meshlets.
## Default keeps up to 64 pages (~3.5 MiB of meshlet payload) on the GPU.
## Avoid allocating duplicate flattened CPU geometry for the page-streamed path.
## The legacy full packed layout remains available when false.
var gpu_streamed_source_only: bool = false
var max_resident_pages: int = 64
var max_page_uploads_per_frame: int = 4
var last_page_uploads: int = 0



var _vertices: PackedVector3Array = PackedVector3Array()
var _meshlets: Array = []
var _packed: Dictionary = {}
var _page_bounds: Array[Dictionary] = []
var _slot_pages: PackedInt32Array = PackedInt32Array()
var _camera_pos: Vector3 = Vector3.ZERO
var _planes: Array = []

# GPU state (render thread, created lazily by record_draw).
var _rd: RenderingDevice = null
var _shader: RID = RID()
var _pipeline: RID = RID()
var _framebuffer: RID = RID()
var _fb_color: RID = RID()
var _fb_depth: RID = RID()
var _uniform_set: RID = RID()
var _buffers: Array[RID] = []
var _frame_buffer: RID = RID()
var _gpu_failed: bool = false



## Build the CPU fallback of a selected cluster cut without losing texture UVs,
## vertex colors, normals or tangents. The mesh-shader path is position-only
## for now; this ArrayMesh path is what authored PBR assets should use.
## One surface at a time: multi-material assets keep their surface boundaries.
static func build_material_preserving_cut(source_mesh: ArrayMesh,
		hierarchy: Dictionary, cut: PackedInt32Array, surface: int = 0) -> ArrayMesh:
	if source_mesh == null or surface < 0 or surface >= source_mesh.get_surface_count():
		return null
	# Blend shape targets need simplification-aware remapping. Refuse until
	# that pipeline exists instead of returning a silently corrupted mesh.
	if source_mesh.get_blend_shape_count() > 0:
		return null
	var source_arrays: Array = source_mesh.surface_get_arrays(surface)
	var arrays: Array = ClusterLOD.build_cut_arrays(source_arrays, hierarchy, cut)
	if arrays.is_empty():
		return null
	var output := ArrayMesh.new()
	# Mesh arrays do not encode custom attribute layouts. Preserve their
	# format bits (and eight-bone/compression options) explicitly, otherwise
	# a custom0/1/2/3 stream can be silently interpreted with the wrong stride.
	var src_format: int = source_mesh.surface_get_format(surface)
	var flags: int = src_format & (Mesh.ARRAY_FORMAT_CUSTOM_MASK 			| Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS | Mesh.ARRAY_FLAG_COMPRESS_ATTRIBUTES)
	output.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, flags)
	output.surface_set_material(0, source_mesh.surface_get_material(surface))
	output.resource_name = source_mesh.resource_name + "_cluster_lod"
	return output

# ---- packing (pure, no device) ---------------------------------------------------------------

## Packs meshlets built by Meshlets.build_meshlets() for upload. Returns {} (see "error" in the
## returned dictionary when non-empty) if a meshlet exceeds the mesh shader output limits.
@warning_ignore("integer_division")
static func pack_meshlets(vertices: PackedVector3Array, meshlets: Array) -> Dictionary:
	var total_vertex_slots: int = 0
	var total_triangles: int = 0
	for i in meshlets.size():
		var m: Dictionary = meshlets[i]
		var vids: PackedInt32Array = m["vertex_ids"]
		var idx: PackedInt32Array = m["indices"]
		if vids.size() > MAX_MESHLET_VERTICES or vids.size() == 0:
			return {"error": "meshlet %d has %d vertices (limit %d)" % [i, vids.size(), MAX_MESHLET_VERTICES]}
		if idx.size() % 3 != 0 or idx.size() == 0 or idx.size() / 3 > MAX_MESHLET_TRIANGLES:
			return {"error": "meshlet %d has an invalid triangle count (limit %d)" % [i, MAX_MESHLET_TRIANGLES]}
		for local_index in idx:
			if local_index < 0 or local_index >= vids.size():
				return {"error": "meshlet %d has a local index outside its vertex list" % i}
		for vid in vids:
			if vid < 0 or vid >= vertices.size():
				return {"error": "meshlet %d references vertex %d outside the vertex array" % [i, vid]}
		total_vertex_slots += vids.size()
		total_triangles += idx.size() / 3
	if meshlets.size() > MAX_MESHLETS:
		return {"error": "too many meshlets (%d, limit %d)" % [meshlets.size(), MAX_MESHLETS]}

	var positions := PackedByteArray()
	positions.resize(vertices.size() * 16)
	for i in vertices.size():
		var p: Vector3 = vertices[i]
		positions.encode_float(i * 16, p.x)
		positions.encode_float(i * 16 + 4, p.y)
		positions.encode_float(i * 16 + 8, p.z)
		positions.encode_float(i * 16 + 12, 1.0)

	var vertex_ids := PackedByteArray()
	vertex_ids.resize(maxi(total_vertex_slots, 1) * 4)
	var triangles := PackedByteArray()
	triangles.resize(maxi(total_triangles, 1) * 4)
	var descriptors := PackedByteArray()
	descriptors.resize(maxi(meshlets.size(), 1) * DESCRIPTOR_STRIDE)

	var vertex_cursor: int = 0
	var triangle_cursor: int = 0
	for i in meshlets.size():
		var m: Dictionary = meshlets[i]
		var vids: PackedInt32Array = m["vertex_ids"]
		var idx: PackedInt32Array = m["indices"]
		var tri_count: int = idx.size() / 3
		for k in vids.size():
			vertex_ids.encode_u32((vertex_cursor + k) * 4, vids[k])
		for t in tri_count:
			var packed_tri: int = idx[t * 3] | (idx[t * 3 + 1] << 8) | (idx[t * 3 + 2] << 16)
			triangles.encode_u32((triangle_cursor + t) * 4, packed_tri)
		var center: Vector3 = m["bounds_center"]
		var axis: Vector3 = m["cone_axis"]
		var o: int = i * DESCRIPTOR_STRIDE
		descriptors.encode_u32(o, vertex_cursor)
		descriptors.encode_u32(o + 4, triangle_cursor)
		descriptors.encode_u32(o + 8, vids.size())
		descriptors.encode_u32(o + 12, tri_count)
		descriptors.encode_float(o + 16, center.x)
		descriptors.encode_float(o + 20, center.y)
		descriptors.encode_float(o + 24, center.z)
		descriptors.encode_float(o + 28, float(m["bounds_radius"]))
		descriptors.encode_float(o + 32, axis.x)
		descriptors.encode_float(o + 36, axis.y)
		descriptors.encode_float(o + 40, axis.z)
		descriptors.encode_float(o + 44, float(m["cone_cutoff"]))
		vertex_cursor += vids.size()
		triangle_cursor += tri_count
	return {
		"error": "",
		"positions": positions,
		"vertex_ids": vertex_ids,
		"triangles": triangles,
		"descriptors": descriptors,
		"meshlet_count": meshlets.size(),
		"vertex_count": vertices.size(),
		"vertex_slots": total_vertex_slots,
		"triangle_count": total_triangles,
	}


## Validates source meshlets without materializing full flattened CPU upload
## streams. Streaming-only users keep the source mesh and page metadata on the
## CPU and pack only the pages being uploaded to GPU slots.
@warning_ignore("integer_division")
static func inspect_streamable_meshlets(vertices: PackedVector3Array, meshlets: Array) -> Dictionary:
	if meshlets.size() > MAX_MESHLETS:
		return {"error": "too many meshlets"}
	var slots: int = 0
	var tris: int = 0
	for i in meshlets.size():
		var meshlet: Dictionary = meshlets[i]
		var vids: PackedInt32Array = meshlet["vertex_ids"]
		var indices: PackedInt32Array = meshlet["indices"]
		if vids.is_empty() or vids.size() > MAX_MESHLET_VERTICES or \
				indices.is_empty() or indices.size() % 3 != 0 or indices.size() / 3 > MAX_MESHLET_TRIANGLES:
			return {"error": "invalid meshlet shape %d" % i}
		for id in vids:
			if id < 0 or id >= vertices.size() or not vertices[id].is_finite():
				return {"error": "invalid source vertex in meshlet %d" % i}
		for index in indices:
			if index < 0 or index >= vids.size():
				return {"error": "invalid local triangle in meshlet %d" % i}
		var center: Vector3 = meshlet["bounds_center"]
		var axis: Vector3 = meshlet["cone_axis"]
		if not center.is_finite() or not axis.is_finite() or \
				not is_finite(float(meshlet["bounds_radius"])) or float(meshlet["bounds_radius"]) < 0.0 or \
				not is_finite(float(meshlet["cone_cutoff"])):
			return {"error": "invalid meshlet bounds %d" % i}
		slots += vids.size()
		tris += indices.size() / 3
	return {"error": "", "meshlet_count": meshlets.size(),
		"vertex_count": vertices.size(), "vertex_slots": slots,
		"triangle_count": tris, "streaming_only": true}


## Encodes exactly one resident GPU slot. All vertex positions and triangle
## indices are copied into that slot's fixed storage window. Other pages are
## not present in the GPU buffers; the stable slot id is the task-group id.
## The full pack_meshlets() layout remains available for CPU tooling/tests.
@warning_ignore("integer_division")
static func pack_resident_page(vertices: PackedVector3Array, meshlets: Array,
		page_id: int, slot_id: int) -> Dictionary:
	if page_id < 0 or slot_id < 0 or slot_id >= 256 or page_id >= ceili(float(meshlets.size()) / float(TASK_GROUP_SIZE)):
		return {"error": "invalid page or slot"}
	var start: int = page_id * TASK_GROUP_SIZE
	var positions := PackedByteArray()
	positions.resize(PagePolicy.POSITIONS_BYTES)
	var vertex_ids := PackedByteArray()
	vertex_ids.resize(PagePolicy.VERTEX_IDS_BYTES)
	var triangles := PackedByteArray()
	triangles.resize(PagePolicy.TRIANGLES_BYTES)
	var descriptors := PackedByteArray()
	descriptors.resize(PagePolicy.DESCRIPTORS_BYTES)
	var count: int = mini(TASK_GROUP_SIZE, meshlets.size() - start)
	for local_id in count:
		var meshlet: Dictionary = meshlets[start + local_id]
		var vids: PackedInt32Array = meshlet["vertex_ids"]
		var idx: PackedInt32Array = meshlet["indices"]
		if vids.is_empty() or vids.size() > MAX_MESHLET_VERTICES or idx.is_empty() or \
				idx.size() % 3 != 0 or idx.size() / 3 > MAX_MESHLET_TRIANGLES:
			return {"error": "invalid meshlet dimensions"}
		for k in vids.size():
			var source_id: int = vids[k]
			if source_id < 0 or source_id >= vertices.size():
				return {"error": "invalid vertex id"}
			var position: Vector3 = vertices[source_id]
			var position_index: int = local_id * MAX_MESHLET_VERTICES + k
			var offset: int = position_index * 16
			positions.encode_float(offset, position.x)
			positions.encode_float(offset + 4, position.y)
			positions.encode_float(offset + 8, position.z)
			positions.encode_float(offset + 12, 1.0)
			vertex_ids.encode_u32(position_index * 4,
				slot_id * TASK_GROUP_SIZE * MAX_MESHLET_VERTICES + position_index)
		var triangle_count: int = idx.size() / 3
		for k in triangle_count:
			var a: int = idx[k * 3]
			var b: int = idx[k * 3 + 1]
			var c: int = idx[k * 3 + 2]
			if a < 0 or b < 0 or c < 0 or a >= vids.size() or b >= vids.size() or c >= vids.size():
				return {"error": "invalid local triangle"}
			triangles.encode_u32((local_id * MAX_MESHLET_TRIANGLES + k) * 4,
				a | (b << 8) | (c << 16))
		var offset: int = local_id * DESCRIPTOR_STRIDE
		descriptors.encode_u32(offset,
			slot_id * TASK_GROUP_SIZE * MAX_MESHLET_VERTICES + local_id * MAX_MESHLET_VERTICES)
		descriptors.encode_u32(offset + 4,
			slot_id * TASK_GROUP_SIZE * MAX_MESHLET_TRIANGLES + local_id * MAX_MESHLET_TRIANGLES)
		descriptors.encode_u32(offset + 8, vids.size())
		descriptors.encode_u32(offset + 12, triangle_count)
		var center: Vector3 = meshlet["bounds_center"]
		var axis: Vector3 = meshlet["cone_axis"]
		var radius: float = float(meshlet["bounds_radius"])
		var cutoff: float = float(meshlet["cone_cutoff"])
		if not center.is_finite() or not axis.is_finite() or \
				not is_finite(radius) or not is_finite(cutoff):
			return {"error": "nonfinite meshlet bounds"}
		for j in 3:
			descriptors.encode_float(offset + 16 + j * 4, center[j])
			descriptors.encode_float(offset + 32 + j * 4, axis[j])
		descriptors.encode_float(offset + 28, radius)
		descriptors.encode_float(offset + 44, cutoff)
	return {
		"error": "", "positions": positions, "vertex_ids": vertex_ids,
		"triangles": triangles, "descriptors": descriptors,
		"page_id": page_id, "slot_id": slot_id, "meshlet_count": count,
	}


## Decodes one 48 byte meshlet descriptor (inverse of the packing above, used by tests).
static func unpack_descriptor(descriptors: PackedByteArray, index: int) -> Dictionary:
	var o: int = index * DESCRIPTOR_STRIDE
	return {
		"vertex_offset": descriptors.decode_u32(o),
		"triangle_offset": descriptors.decode_u32(o + 4),
		"vertex_count": descriptors.decode_u32(o + 8),
		"triangle_count": descriptors.decode_u32(o + 12),
		"center": Vector3(descriptors.decode_float(o + 16), descriptors.decode_float(o + 20), descriptors.decode_float(o + 24)),
		"radius": descriptors.decode_float(o + 28),
		"cone_axis": Vector3(descriptors.decode_float(o + 32), descriptors.decode_float(o + 36), descriptors.decode_float(o + 40)),
		"cone_cutoff": descriptors.decode_float(o + 44),
	}


## Packs the per-frame uniform block (see the layout in the header comment).
static func pack_frame_data(view_proj: Projection, model_xform: Transform3D, planes: Array, camera_pos: Vector3, count: int, flags: int) -> PackedByteArray:
	var data := PackedByteArray()
	data.resize(FRAME_DATA_SIZE)
	var o: int = 0
	for col in 4:
		var c: Vector4 = view_proj[col]
		data.encode_float(o, c.x)
		data.encode_float(o + 4, c.y)
		data.encode_float(o + 8, c.z)
		data.encode_float(o + 12, c.w)
		o += 16
	var b: Basis = model_xform.basis
	for axis_vec in [b.x, b.y, b.z]:
		var v: Vector3 = axis_vec
		data.encode_float(o, v.x)
		data.encode_float(o + 4, v.y)
		data.encode_float(o + 8, v.z)
		data.encode_float(o + 12, 0.0)
		o += 16
	var org: Vector3 = model_xform.origin
	data.encode_float(o, org.x)
	data.encode_float(o + 4, org.y)
	data.encode_float(o + 8, org.z)
	data.encode_float(o + 12, 1.0)
	o += 16
	for k in 6:
		if k < planes.size():
			var pl: Plane = planes[k]
			data.encode_float(o, pl.normal.x)
			data.encode_float(o + 4, pl.normal.y)
			data.encode_float(o + 8, pl.normal.z)
			data.encode_float(o + 12, pl.d)
		else:
			# Missing planes never cull: a far-away plane facing outwards.
			data.encode_float(o, 0.0)
			data.encode_float(o + 4, 0.0)
			data.encode_float(o + 8, 1.0)
			data.encode_float(o + 12, 1.0e30)
		o += 16
	data.encode_float(o, camera_pos.x)
	data.encode_float(o + 4, camera_pos.y)
	data.encode_float(o + 8, camera_pos.z)
	data.encode_float(o + 12, 1.0)
	o += 16
	data.encode_u32(o, count)
	data.encode_u32(o + 4, flags)
	data.encode_u32(o + 8, 0)
	data.encode_u32(o + 12, 0)
	return data


## Splits a ".glsl" file written for RDShaderFile ("#[task]", "#[mesh]", "#[fragment]" section
## markers) into {section name: source}. RDShaderFile parsing is not exposed to scripts.
static func split_shader_sections(text: String) -> Dictionary:
	var sections: Dictionary = {}
	var current: String = ""
	var body: PackedStringArray = PackedStringArray()
	for line in text.split("\n"):
		var stripped: String = line.strip_edges()
		if stripped.begins_with("#[") and stripped.ends_with("]"):
			if current != "":
				sections[current] = "\n".join(body)
			current = stripped.substr(2, stripped.length() - 3).strip_edges()
			body = PackedStringArray()
		elif current != "":
			body.append(line)
	if current != "":
		sections[current] = "\n".join(body)
	return sections


# ---- setup ------------------------------------------------------------------------------------

## Builds meshlets from an indexed triangle list and packs them. Returns false on failure
## (see last_error).
func setup_from_mesh(vertices: PackedVector3Array, indices: PackedInt32Array) -> bool:
	return setup(vertices, Meshlets.build_meshlets(vertices, indices, MAX_MESHLET_VERTICES, MAX_MESHLET_TRIANGLES))


## Uses already built meshlets (for example the cut selected from a ClusterLod hierarchy).
func setup(vertices: PackedVector3Array, meshlets: Array) -> bool:
	release()
	last_error = ""
	var result: Dictionary = inspect_streamable_meshlets(vertices, meshlets) if gpu_streamed_source_only else pack_meshlets(vertices, meshlets)
	if result.is_empty() or String(result.get("error", "")) != "":
		last_error = String(result.get("error", "packing failed"))
		_packed = {}
		meshlet_count = 0
		vertex_count = 0
		return false
	_vertices = vertices
	_meshlets = meshlets
	_packed = result
	meshlet_count = int(result["meshlet_count"])
	vertex_count = int(result["vertex_count"])
	_page_bounds = PagePolicy.build_bounds(meshlets)
	return true


func get_packed() -> Dictionary:
	return _packed


func page_count() -> int:
	return _page_bounds.size()


func get_page_stats() -> Dictionary:
	return {"total_pages": page_count(), "resident_pages": PagePolicy.resident_count(_slot_pages),
		"slot_count": _slot_pages.size(), "bytes_per_slot": PagePolicy.PAGE_BYTES,
		"gpu_capacity_bytes": _slot_pages.size() * PagePolicy.PAGE_BYTES,
		"last_page_uploads": last_page_uploads, "slots": _slot_pages.duplicate()}


func mesh_shader_supported() -> bool:
	if force_fallback:
		return false
	var rd: RenderingDevice = RenderingServer.get_rendering_device()
	return rd != null and rd.has_feature(FEATURE_MESH_SHADER as RenderingDevice.Features)


func choose_path() -> int:
	if _packed.is_empty():
		return DrawPath.NONE
	if mesh_shader_supported() and not _gpu_failed:
		return DrawPath.MESH_SHADER
	return DrawPath.FALLBACK


## Makes the renderer visible under camera/parent and returns the DrawPath used.
## Mesh shader path: adds a CompositorEffect to camera.compositor (an existing Compositor is kept).
## Fallback path: adds a MeshInstance3D holding the visible meshlets as a child of parent.
func attach(parent: Node3D, camera: Camera3D) -> int:
	last_path = choose_path()
	if last_path == DrawPath.MESH_SHADER:
		var effect: CompositorEffect = create_compositor_effect()
		if effect != null and camera != null:
			var comp: Compositor = camera.compositor
			if comp == null:
				comp = Compositor.new()
				camera.compositor = comp
			var effects: Array[CompositorEffect] = comp.compositor_effects
			effects.append(effect)
			comp.compositor_effects = effects
			return last_path
		last_path = DrawPath.FALLBACK
	if last_path == DrawPath.FALLBACK and parent != null:
		var inst: MeshInstance3D = create_fallback_instance()
		if inst != null:
			parent.add_child(inst)
	return last_path


func create_compositor_effect() -> CompositorEffect:
	var script: GDScript = load(EFFECT_SCRIPT_PATH)
	if script == null:
		return null
	var effect: CompositorEffect = script.new()
	effect.set("renderer", self)
	return effect


# ---- CPU reference culling + fallback --------------------------------------------------------

## Updates the culling inputs used by the CPU path (planes in Camera3D.get_frustum() form).
func set_view(camera_pos: Vector3, frustum_planes: Array) -> void:
	_camera_pos = camera_pos
	_planes = frustum_planes


## CPU port of the task shader visibility test for meshlet `index` (world space, uniform scale).
func is_meshlet_visible(index: int, camera_pos: Vector3, planes: Array, flags: int = -1) -> bool:
	var use_flags: int = cull_flags if flags < 0 else flags
	var m: Dictionary = _meshlets[index]
	var scale: float = model.basis.x.length()
	var center: Vector3 = model * (m["bounds_center"] as Vector3)
	var radius: float = float(m["bounds_radius"]) * scale
	if (use_flags & FLAG_FRUSTUM_CULL) != 0:
		for p_v in planes:
			var pl: Plane = p_v
			if pl.normal.dot(center) - pl.d > radius:
				return false
	var cutoff: float = float(m["cone_cutoff"])
	if (use_flags & FLAG_CONE_CULL) != 0 and cutoff < 1.0:
		var axis: Vector3 = (model.basis * (m["cone_axis"] as Vector3)).normalized()
		var to_center: Vector3 = center - camera_pos
		if to_center.dot(axis) >= cutoff * to_center.length() + radius:
			return false
	return true


func visible_meshlets(camera_pos: Vector3, planes: Array, flags: int = -1) -> PackedInt32Array:
	var out := PackedInt32Array()
	for i in _meshlets.size():
		if is_meshlet_visible(i, camera_pos, planes, flags):
			out.append(i)
	return out


## Builds an ArrayMesh (model space) from the selected meshlets; all meshlets when `selection`
## is empty and `use_selection` is false.
@warning_ignore("integer_division")
func build_array_mesh(selection: PackedInt32Array = PackedInt32Array(), use_selection: bool = false) -> ArrayMesh:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var idx := PackedInt32Array()
	var ids: PackedInt32Array = selection
	if not use_selection:
		ids = PackedInt32Array()
		for i in _meshlets.size():
			ids.append(i)
	for mi in ids:
		var m: Dictionary = _meshlets[mi]
		var vids: PackedInt32Array = m["vertex_ids"]
		var local: PackedInt32Array = m["indices"]
		var base: int = verts.size()
		for vid in vids:
			verts.append(_vertices[vid])
			normals.append(Vector3.ZERO)
		for t in local.size() / 3:
			var a: int = base + local[t * 3]
			var b: int = base + local[t * 3 + 1]
			var c: int = base + local[t * 3 + 2]
			# Godot winding: front faces are clockwise, geometric normal is (c - a) x (b - a).
			var n: Vector3 = (verts[c] - verts[a]).cross(verts[b] - verts[a])
			normals[a] += n
			normals[b] += n
			normals[c] += n
			idx.append(a)
			idx.append(b)
			idx.append(c)
	var mesh := ArrayMesh.new()
	if verts.is_empty():
		return mesh
	for i in normals.size():
		normals[i] = normals[i].normalized()
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = idx
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## MeshInstance3D with the visible meshlets (all of them without a view), transform = model.
func create_fallback_instance() -> MeshInstance3D:
	var inst := MeshInstance3D.new()
	if _planes.is_empty():
		inst.mesh = build_array_mesh()
	else:
		inst.mesh = build_array_mesh(visible_meshlets(_camera_pos, _planes), true)
	inst.transform = model
	return inst


## MultiMeshInstance3D drawing every meshlet of this renderer once per transform.
func create_multimesh_instance(transforms: Array[Transform3D]) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = build_array_mesh()
	mm.instance_count = transforms.size()
	for i in transforms.size():
		mm.set_instance_transform(i, transforms[i])
	var inst := MultiMeshInstance3D.new()
	inst.multimesh = mm
	return inst


# ---- mesh shader path (UNVERIFIED on hardware) -------------------------------------------------

## Called from the CompositorEffect on the render thread. Draws all meshlets into the scene
## color + depth buffers after the opaque pass.
func record_draw(render_data: RenderData) -> void:
	if _packed.is_empty() or _page_bounds.is_empty() or _gpu_failed or force_fallback:
		return
	var rd: RenderingDevice = RenderingServer.get_rendering_device()
	if rd == null or not rd.has_feature(FEATURE_MESH_SHADER as RenderingDevice.Features):
		return
	var buffers: RenderSceneBuffersRD = render_data.get_render_scene_buffers() as RenderSceneBuffersRD
	var scene_data: RenderSceneData = render_data.get_render_scene_data()
	if buffers == null or scene_data == null:
		return
	_rd = rd
	var color: RID = buffers.get_color_layer(0)
	var depth: RID = buffers.get_depth_layer(0)
	if not _ensure_gpu(color, depth):
		_gpu_failed = true
		return
	var cam: Transform3D = scene_data.get_cam_transform()
	if not _stream_gpu_pages(cam.origin):
		_gpu_failed = true
		return
	var view_proj: Projection = scene_data.get_cam_projection() * Projection(cam.affine_inverse())
	# Task ids address fixed resident slots, not original CPU meshlet ids.
	var frame: PackedByteArray = pack_frame_data(view_proj, model, _planes, cam.origin,
		_slot_pages.size() * TASK_GROUP_SIZE, cull_flags)
	rd.buffer_update(_frame_buffer, 0, frame.size(), frame)
	var draw_list: int = rd.draw_list_begin(_framebuffer, RenderingDevice.DRAW_DEFAULT_ALL)
	rd.draw_list_bind_render_pipeline(draw_list, _pipeline)
	rd.draw_list_bind_uniform_set(draw_list, _uniform_set, 0)
	rd.call("draw_list_draw_mesh_tasks", draw_list, _slot_pages.size(), 1, 1)
	rd.draw_list_end()


## Refill at most max_page_uploads_per_frame fixed GPU slots. All four
## payload buffers remain allocated until release; switching logical pages
## changes only these small slot regions, never the whole meshlet hierarchy.
## This runs on the rendering thread before draw_list_begin; no readback.
func _stream_gpu_pages(camera_position: Vector3) -> bool:
	last_page_uploads = 0
	if _slot_pages.is_empty():
		return true
	var wanted: PackedInt32Array = PagePolicy.wanted_pages(
		_page_bounds, camera_position, model, _slot_pages.size(), _planes)
	var transfers: Dictionary = PagePolicy.plan(
		_slot_pages, wanted, maxi(max_page_uploads_per_frame, 1))
	var uploads: Array = transfers["uploads"]
	for item in uploads:
		var slot: int = int(item["slot"])
		var page: int = int(item["page"])
		var packed: Dictionary = pack_resident_page(_vertices, _meshlets, page, slot)
		if String(packed.get("error", "")) != "":
			last_error = "meshlet page packing failed: " + String(packed["error"])
			return false
		var streams: Array = [
			[packed["positions"], PagePolicy.POSITIONS_BYTES],
			[packed["vertex_ids"], PagePolicy.VERTEX_IDS_BYTES],
			[packed["triangles"], PagePolicy.TRIANGLES_BYTES],
			[packed["descriptors"], PagePolicy.DESCRIPTORS_BYTES],
		]
		for index in 4:
			var bytes: PackedByteArray = streams[index][0]
			var stride: int = int(streams[index][1])
			if _rd.buffer_update(_buffers[index], slot * stride, bytes.size(), bytes) != OK:
				last_error = "uploading meshlet page %d to GPU slot %d failed" % [page, slot]
				return false
		last_page_uploads += 1
	_slot_pages = transfers["slots"]
	return true


func _storage(binding: int, rid: RID) -> RDUniform:
	var u := RDUniform.new()
	u.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	u.binding = binding
	u.add_id(rid)
	return u


func _ensure_gpu(color: RID, depth: RID) -> bool:
	if _framebuffer.is_valid() and (color != _fb_color or depth != _fb_depth):
		_free_if_valid(_uniform_set)
		_free_if_valid(_pipeline)
		_free_if_valid(_framebuffer)
		_uniform_set = RID()
		_pipeline = RID()
		_framebuffer = RID()
	if not _shader.is_valid() and not _create_shader():
		return false
	if _buffers.is_empty():
		# Bound the allocations by resident slots, not total scene meshlet count.
		# Pages are uploaded on demand, and only resident payload is on GPU.
		var slots: int = mini(_page_bounds.size(), clampi(max_resident_pages, 1, 256))
		_slot_pages.resize(slots)
		_slot_pages.fill(-1)
		_buffers.append(_rd.storage_buffer_create(maxi(slots * PagePolicy.POSITIONS_BYTES, 16)))
		_buffers.append(_rd.storage_buffer_create(maxi(slots * PagePolicy.VERTEX_IDS_BYTES, 16)))
		_buffers.append(_rd.storage_buffer_create(maxi(slots * PagePolicy.TRIANGLES_BYTES, 16)))
		var empty_descriptors := PackedByteArray()
		empty_descriptors.resize(maxi(slots * PagePolicy.DESCRIPTORS_BYTES, 16))
		_buffers.append(_rd.storage_buffer_create(empty_descriptors.size(), empty_descriptors))
		_frame_buffer = _rd.uniform_buffer_create(FRAME_DATA_SIZE)
		for buffer in _buffers:
			if not buffer.is_valid():
				last_error = "GPU meshlet page buffer allocation failed"
				return false
		if not _frame_buffer.is_valid():
			last_error = "GPU meshlet frame uniform allocation failed"
			return false
	if not _framebuffer.is_valid():
		var attachments: Array[RID] = [color, depth]
		_framebuffer = _rd.framebuffer_create(attachments)
		_fb_color = color
		_fb_depth = depth
	if not _framebuffer.is_valid():
		return false
	if not _pipeline.is_valid():
		var raster := RDPipelineRasterizationState.new() # Culling off: winding depends on the projection flip.
		var multisample := RDPipelineMultisampleState.new()
		var depth_state := RDPipelineDepthStencilState.new()
		depth_state.enable_depth_test = true
		depth_state.enable_depth_write = true
		depth_state.depth_compare_operator = RenderingDevice.COMPARE_OP_GREATER_OR_EQUAL # Reverse-Z.
		var blend := RDPipelineColorBlendState.new()
		blend.attachments.push_back(RDPipelineColorBlendStateAttachment.new())
		var fb_format: int = _rd.framebuffer_get_format(_framebuffer)
		_pipeline = _rd.render_pipeline_create(_shader, fb_format, RenderingDevice.INVALID_ID, RenderingDevice.RENDER_PRIMITIVE_TRIANGLES, raster, multisample, depth_state, blend)
	if not _pipeline.is_valid():
		return false
	if not _uniform_set.is_valid():
		var uniforms: Array[RDUniform] = []
		for k in 4:
			uniforms.append(_storage(k, _buffers[k]))
		var ubo := RDUniform.new()
		ubo.uniform_type = RenderingDevice.UNIFORM_TYPE_UNIFORM_BUFFER
		ubo.binding = 4
		ubo.add_id(_frame_buffer)
		uniforms.append(ubo)
		_uniform_set = _rd.uniform_set_create(uniforms, _shader, 0)
	return _uniform_set.is_valid()


func _create_shader() -> bool:
	var task_text: String = _read_text(TASK_SHADER_PATH)
	var mesh_text: String = _read_text(MESH_SHADER_PATH)
	if task_text.is_empty() or mesh_text.is_empty():
		last_error = "meshlet shaders are missing"
		return false
	var task_sections: Dictionary = split_shader_sections(task_text)
	var mesh_sections: Dictionary = split_shader_sections(mesh_text)
	var src := RDShaderSource.new()
	src.language = RenderingDevice.SHADER_LANGUAGE_GLSL
	src.set("source_task", String(task_sections.get("task", "")))
	src.set("source_mesh", String(mesh_sections.get("mesh", "")))
	src.source_fragment = String(mesh_sections.get("fragment", ""))
	var spirv: RDShaderSPIRV = _rd.shader_compile_spirv_from_source(src)
	if spirv == null or _has_compile_error(spirv):
		last_error = "meshlet shader compile error"
		if spirv != null:
			last_error += ": %s %s %s" % [spirv.get("compile_error_task"), spirv.get("compile_error_mesh"), spirv.compile_error_fragment]
		return false
	_shader = _rd.shader_create_from_spirv(spirv)
	return _shader.is_valid()


static func _has_compile_error(spirv: RDShaderSPIRV) -> bool:
	return String(spirv.get("compile_error_task")) != "" or String(spirv.get("compile_error_mesh")) != "" or spirv.compile_error_fragment != ""


static func _read_text(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	return f.get_as_text()


func _free_if_valid(rid: RID) -> void:
	if rid.is_valid() and _rd != null:
		_rd.free_rid(rid)


## Frees all GPU resources (call on the render thread, or when the effect is removed).
func release() -> void:
	if _rd != null:
		_free_if_valid(_uniform_set)
		_free_if_valid(_pipeline)
		_free_if_valid(_framebuffer)
		_free_if_valid(_shader)
		_free_if_valid(_frame_buffer)
		for b in _buffers:
			_free_if_valid(b)
	_uniform_set = RID()
	_pipeline = RID()
	_framebuffer = RID()
	_shader = RID()
	_frame_buffer = RID()
	_buffers.clear()
	_slot_pages.clear()
	last_page_uploads = 0
	_gpu_failed = false
