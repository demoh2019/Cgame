extends RefCounted
## GPU per-instance frustum + Hi-Z-lite occlusion culling that compacts visible instance indices
## (MultiMesh-style batches). Falls back to an exact CPU implementation of the same kernel when no
## local RenderingDevice exists (headless/dummy renderer); the CPU path is what the tests verify.
## The GPU path is UNVERIFIED until run on real hardware.
##
## Conventions: frustum planes are outward-facing (Camera3D.get_frustum()); a box is outside when
## some plane has dot(n, c) - d - dot(|n|, half) > 0. Hi-Z is a single low-res level of per-texel MAX
## occluder depth: {"view_proj": Projection, "width": int, "height": int, "depth": PackedFloat32Array,
## "bias": float}; depth01 = ndc.z * 0.5 + 0.5, uv = ndc.xy * 0.5 + 0.5, texel row 0 at ndc.y = -1.
## An instance is occluded when its nearest corner depth exceeds the farthest depth in every texel its
## screen rect covers. Boxes crossing the near plane or fully off screen are never occlusion-culled.
##
## Output order is ascending instance index (the device path sorts after readback). The device buffer
## carries an indirect-friendly header {count, 1, 1, 0} before the indices.
##
## Credit: compute pipeline pattern from the public Godot 4 RenderingDevice compute tutorial
## (concepts only). Frustum p-vertex test and max-depth Hi-Z are standard techniques. Original
## implementation, project license.

const SHADER_PATH: String = "res://shaders/compute/instance_cull.glsl"
const LOCAL_SIZE: int = 64
const HEADER_BYTES: int = 16

var force_cpu: bool = false
var last_path: String = "none"

var _rd: RenderingDevice = null
var _tried_device: bool = false
var _shader: RID = RID()
var _pipeline: RID = RID()


## Compute shader source text (starts with "#[compute]"), or "" if the file is missing.
func generate_compute_source() -> String:
	if not FileAccess.file_exists(SHADER_PATH):
		return ""
	var f: FileAccess = FileAccess.open(SHADER_PATH, FileAccess.READ)
	if f == null:
		return ""
	return f.get_as_text()


func device_available() -> bool:
	_try_device()
	return _rd != null


func _try_device() -> void:
	if _tried_device or force_cpu:
		return
	_tried_device = true
	_rd = RenderingServer.create_local_rendering_device()


## Culls AABBs against frustum planes (Array[AABB] or Array of AABB). Returns visible indices.
func cull(aabbs: Array, frustum_planes: Array, hiz: Dictionary = {}) -> PackedInt32Array:
	var centers: PackedVector3Array = PackedVector3Array()
	var halves: PackedVector3Array = PackedVector3Array()
	centers.resize(aabbs.size())
	halves.resize(aabbs.size())
	for i in aabbs.size():
		var box: AABB = aabbs[i]
		centers[i] = box.get_center()
		halves[i] = box.size * 0.5
	return cull_packed(centers, halves, frustum_planes, hiz)


## Culls bounding spheres (treated as cubes of half-extent r; conservative).
func cull_spheres(centers: PackedVector3Array, radii: PackedFloat32Array, frustum_planes: Array, hiz: Dictionary = {}) -> PackedInt32Array:
	var halves: PackedVector3Array = PackedVector3Array()
	halves.resize(centers.size())
	for i in centers.size():
		var r: float = radii[i] if i < radii.size() else 0.0
		halves[i] = Vector3(r, r, r)
	return cull_packed(centers, halves, frustum_planes, hiz)


## Core entry: parallel arrays of box centers and half-extents.
func cull_packed(centers: PackedVector3Array, halves: PackedVector3Array, frustum_planes: Array, hiz: Dictionary = {}) -> PackedInt32Array:
	_try_device()
	if _rd != null and not force_cpu and centers.size() > 0:
		var result: PackedInt32Array = _cull_gpu(centers, halves, frustum_planes, hiz)
		if not result.is_empty() or _last_gpu_ok:
			last_path = "gpu"
			return result
	last_path = "cpu"
	return cull_cpu(centers, halves, frustum_planes, hiz)


## Exact reference implementation of the compute kernel.
func cull_cpu(centers: PackedVector3Array, halves: PackedVector3Array, frustum_planes: Array, hiz: Dictionary = {}) -> PackedInt32Array:
	var out: PackedInt32Array = PackedInt32Array()
	var use_hiz: bool = not hiz.is_empty()
	for i in centers.size():
		var c: Vector3 = centers[i]
		var h: Vector3 = halves[i]
		if _outside_frustum(c, h, frustum_planes):
			continue
		if use_hiz and _occluded(c, h, hiz):
			continue
		out.append(i)
	return out


static func _outside_frustum(c: Vector3, h: Vector3, planes: Array) -> bool:
	for p_v in planes:
		var pl: Plane = p_v
		var n: Vector3 = pl.normal
		var d: float = n.dot(c) - pl.d - (absf(n.x) * h.x + absf(n.y) * h.y + absf(n.z) * h.z)
		if d > 0.0:
			return true
	return false


static func _occluded(c: Vector3, h: Vector3, hiz: Dictionary) -> bool:
	var vp: Projection = hiz["view_proj"]
	var wt: int = int(hiz["width"])
	var ht: int = int(hiz["height"])
	var depth: PackedFloat32Array = hiz["depth"]
	var bias: float = float(hiz.get("bias", 0.0))
	var mn: Vector2 = Vector2(1.0e9, 1.0e9)
	var mx: Vector2 = Vector2(-1.0e9, -1.0e9)
	var zmin: float = 1.0e9
	for k in 8:
		var corner: Vector3 = c + h * Vector3(1.0 if (k & 1) != 0 else -1.0, 1.0 if (k & 2) != 0 else -1.0, 1.0 if (k & 4) != 0 else -1.0)
		var clip: Vector4 = vp * Vector4(corner.x, corner.y, corner.z, 1.0)
		if clip.w <= 0.00001:
			return false
		var ndc: Vector3 = Vector3(clip.x, clip.y, clip.z) / clip.w
		var uv: Vector2 = Vector2(ndc.x, ndc.y) * 0.5 + Vector2(0.5, 0.5)
		mn = Vector2(minf(mn.x, uv.x), minf(mn.y, uv.y))
		mx = Vector2(maxf(mx.x, uv.x), maxf(mx.y, uv.y))
		zmin = minf(zmin, ndc.z * 0.5 + 0.5)
	if mx.x < 0.0 or mx.y < 0.0 or mn.x > 1.0 or mn.y > 1.0:
		return false
	var x0: int = clampi(int(floor(mn.x * float(wt))), 0, wt - 1)
	var y0: int = clampi(int(floor(mn.y * float(ht))), 0, ht - 1)
	var x1: int = clampi(int(floor(mx.x * float(wt))), 0, wt - 1)
	var y1: int = clampi(int(floor(mx.y * float(ht))), 0, ht - 1)
	var far_depth: float = 0.0
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			far_depth = maxf(far_depth, depth[y * wt + x])
	return zmin > far_depth + bias


# ---- device path (UNVERIFIED on hardware) ------------------------------------

var _last_gpu_ok: bool = false


func _ensure_pipeline() -> bool:
	if _pipeline.is_valid():
		return true
	var source: String = generate_compute_source()
	if source.is_empty():
		return false
	var src: RDShaderSource = RDShaderSource.new()
	src.language = RenderingDevice.SHADER_LANGUAGE_GLSL
	src.source_compute = source.trim_prefix("#[compute]\n")
	var spirv: RDShaderSPIRV = _rd.shader_compile_spirv_from_source(src)
	if spirv == null or spirv.compile_error_compute != "":
		return false
	_shader = _rd.shader_create_from_spirv(spirv)
	if not _shader.is_valid():
		return false
	_pipeline = _rd.compute_pipeline_create(_shader)
	return _pipeline.is_valid()


func _storage(binding: int, rid: RID) -> RDUniform:
	var u: RDUniform = RDUniform.new()
	u.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	u.binding = binding
	u.add_id(rid)
	return u


func _cull_gpu(centers: PackedVector3Array, halves: PackedVector3Array, planes: Array, hiz: Dictionary) -> PackedInt32Array:
	_last_gpu_ok = false
	if not _ensure_pipeline():
		return PackedInt32Array()
	var n: int = centers.size()
	var inst: PackedFloat32Array = PackedFloat32Array()
	inst.resize(n * 8)
	for i in n:
		inst[i * 8] = centers[i].x
		inst[i * 8 + 1] = centers[i].y
		inst[i * 8 + 2] = centers[i].z
		inst[i * 8 + 4] = halves[i].x
		inst[i * 8 + 5] = halves[i].y
		inst[i * 8 + 6] = halves[i].z
	var pl: PackedFloat32Array = PackedFloat32Array()
	pl.resize(maxi(planes.size(), 1) * 4)
	for k in planes.size():
		var p: Plane = planes[k]
		pl[k * 4] = p.normal.x
		pl[k * 4 + 1] = p.normal.y
		pl[k * 4 + 2] = p.normal.z
		pl[k * 4 + 3] = p.d
	var use_hiz: bool = not hiz.is_empty()
	var hz: PackedFloat32Array = PackedFloat32Array()
	if use_hiz:
		var vp: Projection = hiz["view_proj"]
		for col in 4:
			var column: Vector4 = vp[col]
			hz.append_array(PackedFloat32Array([column.x, column.y, column.z, column.w]))
		hz.append_array(PackedFloat32Array([float(hiz["width"]), float(hiz["height"]), float(hiz.get("bias", 0.0)), 0.0]))
		hz.append_array(hiz["depth"] as PackedFloat32Array)
	else:
		hz.resize(24)
	var out_bytes: int = HEADER_BYTES + n * 4
	var rids: Array[RID] = []
	var b_inst: RID = _rd.storage_buffer_create(inst.size() * 4, inst.to_byte_array())
	var b_planes: RID = _rd.storage_buffer_create(pl.size() * 4, pl.to_byte_array())
	var zero: PackedByteArray = PackedByteArray()
	zero.resize(out_bytes)
	zero.encode_u32(4, 1)
	zero.encode_u32(8, 1)
	var b_out: RID = _rd.storage_buffer_create(out_bytes, zero)
	var b_hiz: RID = _rd.storage_buffer_create(hz.size() * 4, hz.to_byte_array())
	rids.assign([b_inst, b_planes, b_out, b_hiz])
	var uset: RID = _rd.uniform_set_create([_storage(0, b_inst), _storage(1, b_planes), _storage(2, b_out), _storage(3, b_hiz)], _shader, 0)
	var push: PackedByteArray = PackedByteArray()
	push.resize(16)
	push.encode_u32(0, n)
	push.encode_u32(4, planes.size())
	push.encode_u32(8, 1 if use_hiz else 0)
	var list: int = _rd.compute_list_begin()
	_rd.compute_list_bind_compute_pipeline(list, _pipeline)
	_rd.compute_list_bind_uniform_set(list, uset, 0)
	_rd.compute_list_set_push_constant(list, push, push.size())
	_rd.compute_list_dispatch(list, ceili(float(n) / float(LOCAL_SIZE)), 1, 1)
	_rd.compute_list_end()
	_rd.submit()
	_rd.sync()
	var data: PackedByteArray = _rd.buffer_get_data(b_out)
	var visible_count: int = mini(int(data.decode_u32(0)), n)
	var result: PackedInt32Array = data.slice(HEADER_BYTES, HEADER_BYTES + visible_count * 4).to_int32_array()
	result.sort()
	_rd.free_rid(uset)
	for rid in rids:
		_rd.free_rid(rid)
	_last_gpu_ok = true
	return result


func shutdown() -> void:
	if _rd != null:
		if _pipeline.is_valid():
			_rd.free_rid(_pipeline)
		if _shader.is_valid():
			_rd.free_rid(_shader)
		_rd.free()
	_rd = null
	_pipeline = RID()
	_shader = RID()
	_tried_device = false

