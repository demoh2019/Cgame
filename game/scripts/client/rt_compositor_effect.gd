extends CompositorEffect
## Render-thread half of the hardware ray-traced shadows / ambient occlusion.
##
## Owns all GPU state: per-mesh-surface BLAS (budgeted builds, LRU eviction), one
## TLAS rebuilt whenever a new instance snapshot arrives, and the compute passes
## rt_shadows.glsl, rt_ao.glsl (GL_EXT_ray_query against the TLAS, using the
## scene depth buffer and normals reconstructed from it) and rt_denoise.glsl
## (spatial + temporal filter, composite onto the opaque colour buffer).
## Runs at POST_OPAQUE, so transparent surfaces are drawn after the effect.
##
## Silent fallback: if the device has no SUPPORTS_RAY_QUERY, a shader fails to
## compile, or any resource creation fails, the effect disables itself.
## Original work for Cgame (Khronos GL_EXT_ray_query / VK_KHR_ray_query public specs).

const SHADER_DIR := "res://shaders/compute/"
const COMMON_INCLUDE := "#include \"res://shaders/compute/rt_common.inc\""
const CONTEXT := &"rt_effects"
const PARAMS_SIZE := 256
const MAX_BLAS := 512
## Frames without use before a BLAS may be evicted when over MAX_BLAS.
const EVICT_AGE := 120

var _mutex := Mutex.new()
var _cfg: Dictionary = {}
var _pending_instances: Array = []
var _pending_geometry: Dictionary = {}
var _have_snapshot: bool = false
var _sun_dir: Vector3 = Vector3.UP
var _sun_radius: float = 0.0047
var _evicted: Array = []

# Render-thread state.
var _rd: RenderingDevice
var _failed: bool = false
var _active: bool = false
var _shaders: Dictionary = {}  # pass name -> RID
var _pipelines: Dictionary = {}
var _nearest: RID
var _linear: RID
var _params_buffer: RID
var _tlas: RID
var _tlas_capacity: int = 0
var _tlas_instance_count: int = 0
var _blas: Dictionary = {}  # key -> {blas, vbuf, ibuf, built, last_used}
var _build_queue: Array = []  # keys awaiting a BLAS build (uploaded, not built)
var _instances: Array = []  # latest instance list [{key, transform}]
var _instances_dirty: bool = false
var _frame: int = 0
var _hist_flip: bool = false
var _prev_view_proj: Projection = Projection.IDENTITY
var _have_prev: bool = false
var _tex_sig: Array = []


func _init() -> void:
	effect_callback_type = EFFECT_CALLBACK_TYPE_POST_OPAQUE
	access_resolved_color = false
	access_resolved_depth = false
	needs_motion_vectors = false
	needs_normal_roughness = false


## Pure helpers (static so they can be unit tested without a GPU).

@warning_ignore("integer_division")
static func group_count(pixels: int, group_size: int = 8) -> int:
	return (pixels + group_size - 1) / group_size


## Number of BLAS builds to start this frame (`queued` waiting, `budget` allowed).
static func builds_this_frame(queued: int, budget: int) -> int:
	return maxi(mini(queued, budget), 0)


## Keys to evict: unused for EVICT_AGE frames, oldest first, only while `count`
## exceeds `limit`. `last_used` maps key -> frame index.
static func eviction_candidates(last_used: Dictionary, frame: int, count: int, limit: int) -> Array:
	var over: int = count - limit
	if over <= 0:
		return []
	var aged: Array[Dictionary] = []
	for k in last_used:
		var lu: int = last_used[k]
		if frame - lu >= EVICT_AGE:
			aged.append({"key": k, "lu": lu})
	aged.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var la: int = a["lu"]
		var lb: int = b["lu"]
		return la < lb)
	var out: Array = []
	for a in aged:
		if out.size() >= over:
			break
		out.append(a["key"])
	return out


## Column-major mat4 as 16 floats appended to `out`.
static func _push_mat(out: PackedFloat32Array, p: Projection) -> void:
	for col: Vector4 in [p.x, p.y, p.z, p.w]:
		out.append(col.x)
		out.append(col.y)
		out.append(col.z)
		out.append(col.w)


## std140 layout of RtParams in rt_common.inc (256 bytes).
static func pack_params(inv_proj: Projection, cam_to_world: Transform3D, prev_view_proj: Projection,
		sun_dir: Vector3, sun_radius: float, size: Vector2i, frame: int, ao_rays: int, cfg: Dictionary) -> PackedByteArray:
	var f := PackedFloat32Array()
	_push_mat(f, inv_proj)
	_push_mat(f, Projection(cam_to_world))
	_push_mat(f, prev_view_proj)
	f.append_array(PackedFloat32Array([sun_dir.x, sun_dir.y, sun_dir.z, sun_radius]))
	f.append_array(PackedFloat32Array([float(size.x), float(size.y), float(frame), float(ao_rays)]))
	f.append_array(PackedFloat32Array([float(cfg.get("shadow_tmax", 80.0)), float(cfg.get("ao_tmax", 1.75)), 0.04, 0.0]))
	var ss: float = float(cfg.get("shadow_strength", 1.0)) if bool(cfg.get("shadows", true)) else 0.0
	var aos: float = float(cfg.get("ao_strength", 0.85)) if bool(cfg.get("ao", true)) else 0.0
	f.append_array(PackedFloat32Array([ss, aos, float(cfg.get("temporal_blend", 0.9)), 0.0]))
	return f.to_byte_array()


static func shader_path(pass_name: String) -> String:
	return SHADER_DIR + pass_name + ".glsl"


## Source of a pass with the #[compute] header removed and the common include
## inlined (RDShaderSource does not resolve res:// includes).
static func prepare_source(pass_source: String, common_source: String) -> String:
	var src: String = pass_source.replace("#[compute]\n", "")
	return src.replace(COMMON_INCLUDE, common_source)


## Main-thread API.

func configure(cfg: Dictionary) -> void:
	_mutex.lock()
	_cfg = cfg.duplicate()
	_mutex.unlock()


## Hands a snapshot to the render thread. `instances`: [{key:int, transform:Transform3D}],
## `geometry`: {key: {vertices: PackedByteArray, indices: PackedByteArray,
## vertex_count: int, index_count: int}} for meshes the render thread has not seen.
func submit(instances: Array, geometry: Dictionary, sun_dir: Vector3, sun_radius: float) -> void:
	_mutex.lock()
	_pending_instances = instances
	_pending_geometry.merge(geometry, true)
	_have_snapshot = true
	_sun_dir = sun_dir
	_sun_radius = sun_radius
	_mutex.unlock()


## BLAS keys the render thread dropped; the caller must re-submit their geometry.
func take_evicted_keys() -> Array:
	_mutex.lock()
	var out: Array = _evicted
	_evicted = []
	_mutex.unlock()
	return out


func is_active() -> bool:
	return _active


## Render thread.

func _render_callback(p_callback_type: int, p_render_data: RenderData) -> void:
	if _failed or p_callback_type != EFFECT_CALLBACK_TYPE_POST_OPAQUE or p_render_data == null:
		return
	if _rd == null:
		_setup()
		if _failed:
			return
	var buffers: RenderSceneBuffersRD = p_render_data.get_render_scene_buffers() as RenderSceneBuffersRD
	var scene_data: RenderSceneDataRD = p_render_data.get_render_scene_data() as RenderSceneDataRD
	if buffers == null or scene_data == null:
		return
	_frame += 1
	_ingest()
	_build_budgeted()
	if _instances_dirty:
		_rebuild_tlas()
	if not _tlas.is_valid() or _tlas_instance_count == 0:
		_active = false
		return
	_trace_and_composite(buffers, scene_data)
	_active = true


func _setup() -> void:
	_rd = RenderingServer.get_rendering_device()
	if _rd == null or not _rd.has_feature(RenderingDevice.SUPPORTS_RAY_QUERY):
		_fail("ray query not supported")
		return
	var common: String = FileAccess.get_file_as_string(SHADER_DIR + "rt_common.inc")
	if common.is_empty():
		_fail("rt_common.inc missing")
		return
	for pass_name in ["rt_shadows", "rt_ao", "rt_denoise"]:
		var text: String = FileAccess.get_file_as_string(shader_path(pass_name))
		if text.is_empty():
			_fail("%s.glsl missing" % pass_name)
			return
		var source := RDShaderSource.new()
		source.language = RenderingDevice.SHADER_LANGUAGE_GLSL
		source.source_compute = prepare_source(text, common)
		var spirv: RDShaderSPIRV = _rd.shader_compile_spirv_from_source(source)
		if spirv == null or not spirv.compile_error_compute.is_empty():
			_fail("%s compile error: %s" % [pass_name, spirv.compile_error_compute if spirv != null else "null"])
			return
		var shader: RID = _rd.shader_create_from_spirv(spirv, pass_name)
		if not shader.is_valid():
			_fail("%s shader create failed" % pass_name)
			return
		_shaders[pass_name] = shader
		_pipelines[pass_name] = _rd.compute_pipeline_create(shader)
	var ss := RDSamplerState.new()
	ss.min_filter = RenderingDevice.SAMPLER_FILTER_NEAREST
	ss.mag_filter = RenderingDevice.SAMPLER_FILTER_NEAREST
	_nearest = _rd.sampler_create(ss)
	var sl := RDSamplerState.new()
	sl.min_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
	sl.mag_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
	sl.repeat_u = RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE
	sl.repeat_v = RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE
	_linear = _rd.sampler_create(sl)
	_params_buffer = _rd.uniform_buffer_create(PARAMS_SIZE)
	if not _params_buffer.is_valid():
		_fail("uniform buffer create failed")


func _fail(reason: String) -> void:
	_failed = true
	_active = false
	if reason != "ray query not supported":
		push_warning("rt_compositor_effect: disabled (%s)" % reason)


func _ingest() -> void:
	_mutex.lock()
	var geometry: Dictionary = _pending_geometry
	_pending_geometry = {}
	if _have_snapshot:
		_instances = _pending_instances
		_instances_dirty = true
		_have_snapshot = false
	_mutex.unlock()
	for key in geometry:
		if _blas.has(key):
			continue
		var g: Dictionary = geometry[key]
		_create_blas(key, g)


func _create_blas(key: int, g: Dictionary) -> void:
	var vbytes: PackedByteArray = g["vertices"]
	var ibytes: PackedByteArray = g["indices"]
	var vcount: int = g["vertex_count"]
	var icount: int = g["index_count"]
	var vbuf: RID = _rd.vertex_buffer_create(vbytes.size(), vbytes,
			RenderingDevice.BUFFER_CREATION_ACCELERATION_STRUCTURE_BUILD_INPUT_READ_ONLY_BIT)
	var ibuf: RID = _rd.index_buffer_create(icount, RenderingDevice.INDEX_BUFFER_FORMAT_UINT32, ibytes, false,
			RenderingDevice.BUFFER_CREATION_ACCELERATION_STRUCTURE_BUILD_INPUT_READ_ONLY_BIT)
	if not vbuf.is_valid() or not ibuf.is_valid():
		return
	var geo := RDAccelerationStructureGeometry.new()
	geo.flags = RenderingDevice.ACCELERATION_STRUCTURE_GEOMETRY_OPAQUE_BIT
	geo.vertex_buffer = vbuf
	geo.vertex_offset = 0
	geo.vertex_stride = 12
	geo.vertex_count = vcount
	geo.vertex_format = RenderingDevice.DATA_FORMAT_R32G32B32_SFLOAT
	geo.index_buffer = ibuf
	geo.index_offset = 0
	geo.index_count = icount
	var geometries: Array[RDAccelerationStructureGeometry] = [geo]
	var blas: RID = _rd.blas_create(geometries, RenderingDevice.ACCELERATION_STRUCTURE_PREFER_FAST_TRACE_BIT)
	if not blas.is_valid():
		_rd.free_rid(ibuf)
		_rd.free_rid(vbuf)
		return
	_blas[key] = {"blas": blas, "vbuf": vbuf, "ibuf": ibuf, "built": false, "last_used": _frame}
	_build_queue.append(key)


func _build_budgeted() -> void:
	var n: int = builds_this_frame(_build_queue.size(), int(_cfg.get("blas_builds_per_frame", 2)))
	for i in n:
		var key: int = _build_queue.pop_front()
		if not _blas.has(key):
			continue
		var entry: Dictionary = _blas[key]
		var blas: RID = entry["blas"]
		if _rd.blas_build(blas) == OK:
			entry["built"] = true
			_instances_dirty = true
	# Eviction happens only over the cap and only for long-unused entries.
	var last_used: Dictionary = {}
	for k in _blas:
		var e: Dictionary = _blas[k]
		last_used[k] = e["last_used"]
	var victims: Array = eviction_candidates(last_used, _frame, _blas.size(), MAX_BLAS)
	if victims.is_empty():
		return
	for k in victims:
		_free_blas(k)
	_mutex.lock()
	_evicted.append_array(victims)
	_mutex.unlock()
	_instances_dirty = true


func _free_blas(key: int) -> void:
	var entry: Dictionary = _blas[key]
	_rd.free_rid(entry["blas"])
	_rd.free_rid(entry["ibuf"])
	_rd.free_rid(entry["vbuf"])
	_blas.erase(key)
	_build_queue.erase(key)


func _rebuild_tlas() -> void:
	_instances_dirty = false
	var list: Array[RDAccelerationStructureInstance] = []
	var cap: int = int(_cfg.get("max_instances", 256)) * 4  # surfaces, not nodes
	for inst in _instances:
		if list.size() >= cap:
			break
		var key: int = inst["key"]
		if not _blas.has(key):
			continue
		var entry: Dictionary = _blas[key]
		if not bool(entry["built"]):
			continue
		entry["last_used"] = _frame
		var ri := RDAccelerationStructureInstance.new()
		ri.transform = inst["transform"]
		ri.id = list.size()
		ri.mask = 0xFF
		ri.hit_sbt_range = 0
		ri.flags = RenderingDevice.ACCELERATION_STRUCTURE_INSTANCE_FORCE_OPAQUE_BIT | RenderingDevice.ACCELERATION_STRUCTURE_INSTANCE_TRIANGLE_FACING_CULL_DISABLE_BIT
		ri.blas = entry["blas"]
		list.append(ri)
	_tlas_instance_count = list.size()
	if list.is_empty():
		return
	if not _tlas.is_valid() or _tlas_capacity < list.size():
		if _tlas.is_valid():
			_rd.free_rid(_tlas)
		_tlas_capacity = maxi(cap, list.size())
		_tlas = _rd.tlas_create(_tlas_capacity, RenderingDevice.ACCELERATION_STRUCTURE_PREFER_FAST_TRACE_BIT)
		if not _tlas.is_valid():
			_fail("tlas create failed")
			return
	if _rd.tlas_build(_tlas, list) != OK:
		_tlas_instance_count = 0


func _uniform(type: int, binding: int, ids: Array) -> RDUniform:
	var u := RDUniform.new()
	u.uniform_type = type
	u.binding = binding
	for id in ids:
		u.add_id(id)
	return u


func _make_tex(buffers: RenderSceneBuffersRD, tex_name: StringName, format: int, size: Vector2i) -> RID:
	var usage: int = RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT | RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT
	return buffers.create_texture(CONTEXT, tex_name, format, usage, RenderingDevice.TEXTURE_SAMPLES_1, size, 1, 1, false, false)


func _dispatch(pass_name: String, uniforms: Array[RDUniform], groups_x: int, groups_y: int) -> void:
	var shader: RID = _shaders[pass_name]
	var set_rid: RID = UniformSetCacheRD.get_cache(shader, 0, uniforms)
	var list: int = _rd.compute_list_begin()
	_rd.compute_list_bind_compute_pipeline(list, _pipelines[pass_name])
	_rd.compute_list_bind_uniform_set(list, set_rid, 0)
	_rd.compute_list_dispatch(list, groups_x, groups_y, 1)
	_rd.compute_list_end()


func _trace_and_composite(buffers: RenderSceneBuffersRD, scene_data: RenderSceneDataRD) -> void:
	var size: Vector2i = buffers.get_internal_size()
	if size.x <= 0 or size.y <= 0:
		return
	var depth: RID = buffers.get_depth_texture()
	var color: RID = buffers.get_color_layer(0)
	var raw_shadow: RID = _make_tex(buffers, &"raw_shadow", RenderingDevice.DATA_FORMAT_R16_SFLOAT, size)
	var raw_ao: RID = _make_tex(buffers, &"raw_ao", RenderingDevice.DATA_FORMAT_R16_SFLOAT, size)
	var hist_a: RID = _make_tex(buffers, &"hist_a", RenderingDevice.DATA_FORMAT_R16G16_SFLOAT, size)
	var hist_b: RID = _make_tex(buffers, &"hist_b", RenderingDevice.DATA_FORMAT_R16G16_SFLOAT, size)
	if not (depth.is_valid() and color.is_valid() and raw_shadow.is_valid() and raw_ao.is_valid() and hist_a.is_valid() and hist_b.is_valid()):
		return
	# Freshly (re)created textures hold garbage: seed them with "fully visible".
	var sig: Array = [raw_shadow, raw_ao, hist_a, hist_b]
	if sig != _tex_sig:
		_tex_sig = sig
		for t in sig:
			_rd.texture_clear(t, Color(1, 1, 1, 1), 0, 1, 0, 1)
		_have_prev = false

	var cam_proj: Projection = scene_data.get_cam_projection()
	var cam_xf: Transform3D = scene_data.get_cam_transform()
	_mutex.lock()
	var cfg: Dictionary = _cfg.duplicate()
	var sun_dir: Vector3 = _sun_dir
	var sun_radius: float = _sun_radius
	_mutex.unlock()
	var prev: Projection = _prev_view_proj if _have_prev else cam_proj * Projection(cam_xf.affine_inverse())
	var ao_rays: int = int(cfg.get("ao_rays", 1))
	var params: PackedByteArray = pack_params(cam_proj.inverse(), cam_xf, prev, sun_dir, sun_radius, size,
			_frame if _have_prev else 0, ao_rays, cfg)
	_rd.buffer_update(_params_buffer, 0, params.size(), params)

	var gx: int = group_count(size.x)
	var gy: int = group_count(size.y)
	var depth_u: RDUniform = _uniform(RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE, 1, [_nearest, depth])
	var params_u: RDUniform = _uniform(RenderingDevice.UNIFORM_TYPE_UNIFORM_BUFFER, 3, [_params_buffer])
	if bool(cfg.get("shadows", true)):
		var tlas_u: RDUniform = _uniform(RenderingDevice.UNIFORM_TYPE_ACCELERATION_STRUCTURE, 0, [_tlas])
		_dispatch("rt_shadows", [tlas_u, depth_u, _uniform(RenderingDevice.UNIFORM_TYPE_IMAGE, 2, [raw_shadow]), params_u], gx, gy)
	if bool(cfg.get("ao", true)):
		var tlas_u2: RDUniform = _uniform(RenderingDevice.UNIFORM_TYPE_ACCELERATION_STRUCTURE, 0, [_tlas])
		_dispatch("rt_ao", [tlas_u2, depth_u, _uniform(RenderingDevice.UNIFORM_TYPE_IMAGE, 2, [raw_ao]), params_u], gx, gy)

	var hist_in: RID = hist_a if _hist_flip else hist_b
	var hist_out: RID = hist_b if _hist_flip else hist_a
	_dispatch("rt_denoise", [
		_uniform(RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE, 0, [_nearest, depth]),
		_uniform(RenderingDevice.UNIFORM_TYPE_IMAGE, 1, [raw_shadow]),
		_uniform(RenderingDevice.UNIFORM_TYPE_IMAGE, 2, [raw_ao]),
		params_u,
		_uniform(RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE, 4, [_linear, hist_in]),
		_uniform(RenderingDevice.UNIFORM_TYPE_IMAGE, 5, [hist_out]),
		_uniform(RenderingDevice.UNIFORM_TYPE_IMAGE, 6, [color]),
	], gx, gy)
	_hist_flip = not _hist_flip
	_prev_view_proj = cam_proj * Projection(cam_xf.affine_inverse())
	_have_prev = true


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and _rd != null:
		for key in _blas.keys():
			_free_blas(key)
		for rid in [_tlas, _params_buffer, _nearest, _linear]:
			if rid.is_valid():
				_rd.free_rid(rid)
		for rid in _pipelines.values():
			_rd.free_rid(rid)
		for rid in _shaders.values():
			_rd.free_rid(rid)
