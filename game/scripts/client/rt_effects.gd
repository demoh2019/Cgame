extends Node
## Hardware ray-traced shadows + ambient occlusion driver (main thread side).
##
## Uses the fork's RenderingDevice ray tracing API (blas_create / tlas_create /
## blas_build / tlas_build + GL_EXT_ray_query in compute shaders, gated by
## RenderingDevice.SUPPORTS_RAY_QUERY). This node:
##   - scans MeshInstance3D nodes under `scene_root`,
##   - picks the nearest N to the camera (budgeted),
##   - extracts triangle data for new meshes (budgeted per update),
##   - hands the snapshot to rt_compositor_effect.gd, which owns every GPU
##     resource and runs on the render thread (BLAS build budget, TLAS rebuild,
##     shadow / AO rays, denoise, composite).
## Without ray query support (Metal today, old GPUs, headless, Compatibility /
## Mobile renderers) attach() is a silent no-op and the raster path is untouched.
##
## Original work for Cgame. Ray query usage follows the public Khronos
## GL_EXT_ray_query / VK_KHR_ray_query specifications; no third-party code.

const RtEffect = preload("res://scripts/client/rt_compositor_effect.gd")

## Surfaces above this triangle count are skipped (too costly to extract/build).
const MAX_TRIANGLES_PER_SURFACE := 120000

var scene_root: Node
var camera: Camera3D
var sun: DirectionalLight3D
var quality: int = 2
## Turn the raster sun shadow off while RT shadows are really active.
var replace_raster_sun_shadows: bool = true

var _effect: RtEffect
var _settings: Dictionary = {}
var _meshes: Array[MeshInstance3D] = []
var _rescan_left: float = 0.0
var _frame: int = 0
var _known_keys: Dictionary = {}  # blas key -> true (geometry already handed over)
var _sun_shadow_was_enabled: bool = false
var _sun_shadow_saved: bool = false


## True when the device can build acceleration structures and run ray queries.
static func is_supported(rd: RenderingDevice) -> bool:
	return rd != null and rd.has_feature(RenderingDevice.SUPPORTS_RAY_QUERY)


## Quality tiers 0 (off) .. 3. Rays are 1 per pixel for shadows, `ao_rays` for AO.
static func settings(level: int, rendering_method: String = "forward_plus") -> Dictionary:
	var tier: int = clampi(level, 0, 3)
	var enabled: bool = tier >= 1 and rendering_method == "forward_plus"
	return {
		"enabled": enabled,
		"shadows": enabled,
		"ao": enabled and tier >= 2,
		"ao_rays": 2 if tier == 3 else 1,
		"max_distance": 60.0 if tier == 3 else (45.0 if tier == 2 else 30.0),
		"max_instances": 768 if tier == 3 else (512 if tier == 2 else 256),
		"blas_builds_per_frame": 4 if tier == 3 else 2,
		"extractions_per_update": 3 if tier == 3 else 2,
		"update_interval": 4 if tier == 1 else 3,
		"shadow_tmax": 120.0 if tier == 3 else 80.0,
		"ao_tmax": 2.5 if tier == 3 else 1.75,
		"shadow_strength": 1.0,
		"ao_strength": 0.85,
		"temporal_blend": 0.9,
	}


## Triangle data of one surface as {"ok", "vertices", "indices"} (indices are
## always present; generated 0..n-1 for non-indexed surfaces).
static func extract_triangles(mesh: Mesh, surface: int) -> Dictionary:
	var out: Dictionary = {"ok": false, "vertices": PackedVector3Array(), "indices": PackedInt32Array()}
	if mesh == null or surface < 0 or surface >= mesh.get_surface_count():
		return out
	# Only ArrayMesh reports a primitive type; primitive meshes are always triangles.
	if mesh is ArrayMesh and (mesh as ArrayMesh).surface_get_primitive_type(surface) != Mesh.PRIMITIVE_TRIANGLES:
		return out
	var arrays: Array = mesh.surface_get_arrays(surface)
	if arrays.size() <= Mesh.ARRAY_VERTEX:
		return out
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	if verts.size() < 3:
		return out
	var indices: PackedInt32Array
	if arrays.size() > Mesh.ARRAY_INDEX and arrays[Mesh.ARRAY_INDEX] != null:
		indices = arrays[Mesh.ARRAY_INDEX]
	if indices.is_empty():
		indices.resize(verts.size())
		for i in verts.size():
			indices[i] = i
	if indices.size() % 3 != 0 or indices.size() > MAX_TRIANGLES_PER_SURFACE * 3:
		return out
	out["ok"] = true
	out["vertices"] = verts
	out["indices"] = indices
	return out


## Tightly packed R32G32B32_SFLOAT position stream for a BLAS vertex buffer.
static func pack_positions(verts: PackedVector3Array) -> PackedByteArray:
	var floats := PackedFloat32Array()
	floats.resize(verts.size() * 3)
	var o: int = 0
	for v in verts:
		floats[o] = v.x
		floats[o + 1] = v.y
		floats[o + 2] = v.z
		o += 3
	return floats.to_byte_array()


## 32-bit index stream for a BLAS index buffer.
static func pack_indices(indices: PackedInt32Array) -> PackedByteArray:
	return indices.to_byte_array()


## Stable key of one mesh surface (the BLAS is shared by all instances of it).
static func blas_key(mesh: Mesh, surface: int) -> int:
	return mesh.get_instance_id() * 64 + surface


## The nearest `max_count` candidates within `max_distance` of `origin`.
## Candidates are {"position": Vector3, "radius": float, ...}; the surface
## distance (centre distance minus radius) orders them, ties keep input order.
static func select_nearest(candidates: Array[Dictionary], origin: Vector3, max_distance: float, max_count: int) -> Array[Dictionary]:
	var scored: Array[Dictionary] = []
	for i in candidates.size():
		var c: Dictionary = candidates[i]
		var pos: Vector3 = c["position"]
		var radius: float = c["radius"]
		var d: float = maxf(origin.distance_to(pos) - radius, 0.0)
		if d > max_distance:
			continue
		scored.append({"d": d, "i": i})
	scored.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var da: float = a["d"]
		var db: float = b["d"]
		if da == db:
			var ia: int = a["i"]
			var ib: int = b["i"]
			return ia < ib
		return da < db)
	var out: Array[Dictionary] = []
	for s in scored:
		if out.size() >= max_count:
			break
		var idx: int = s["i"]
		out.append(candidates[idx])
	return out


## How many of `pending` expensive operations may run this frame.
static func budget_take(pending: int, per_frame: int) -> int:
	return maxi(mini(pending, per_frame), 0)


static func _max_scale(b: Basis) -> float:
	var s: Vector3 = b.get_scale().abs()
	return maxf(maxf(s.x, s.y), s.z)


## Direction TOWARDS the sun for a directional light (lights shine along -Z).
static func sun_direction(light: DirectionalLight3D) -> Vector3:
	return light.global_transform.basis.z.normalized()


## Angular radius (radians) of the sun disc used for the soft penumbra.
static func sun_angular_radius(light: DirectionalLight3D) -> float:
	return maxf(deg_to_rad(light.light_angular_distance) * 0.5, 0.004)


## Creates the effect on `cam`'s compositor when the device supports it.
## Returns false (and does nothing) otherwise.
func attach(cam: Camera3D, root: Node, sun_light: DirectionalLight3D, rendering_method: String = "forward_plus") -> bool:
	detach()
	_settings = settings(quality, rendering_method)
	if not bool(_settings["enabled"]):
		return false
	if not is_supported(RenderingServer.get_rendering_device()):
		return false
	camera = cam
	scene_root = root
	sun = sun_light
	_effect = RtEffect.new()
	_effect.configure(_settings)
	var comp: Compositor = cam.compositor
	if comp == null:
		comp = Compositor.new()
		cam.compositor = comp
	var effects: Array[CompositorEffect] = comp.compositor_effects.duplicate()
	effects.append(_effect)
	comp.compositor_effects = effects
	_rescan_left = 0.0
	set_process(true)
	return true


func detach() -> void:
	set_process(false)
	_restore_sun_shadow()
	if _effect != null and camera != null and is_instance_valid(camera) and camera.compositor != null:
		var effects: Array[CompositorEffect] = camera.compositor.compositor_effects.duplicate()
		effects.erase(_effect)
		camera.compositor.compositor_effects = effects
	_effect = null
	_known_keys.clear()
	_meshes.clear()


func is_active() -> bool:
	return _effect != null and _effect.is_active()


func _ready() -> void:
	set_process(false)


func _exit_tree() -> void:
	detach()


func _process(delta: float) -> void:
	if _effect == null or camera == null or not is_instance_valid(camera):
		return
	_frame += 1
	for evicted in _effect.take_evicted_keys():
		_known_keys.erase(evicted)
	_rescan_left -= delta
	if _rescan_left <= 0.0:
		_rescan_left = 2.0
		_rescan()
	if _frame % int(_settings["update_interval"]) != 0:
		return
	_push_snapshot()
	_update_sun_shadow()


func _rescan() -> void:
	_meshes.clear()
	if scene_root == null or not is_instance_valid(scene_root):
		return
	var stack: Array[Node] = [scene_root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D:
			var mi: MeshInstance3D = n
			if mi.mesh != null and mi.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
				_meshes.append(mi)
		for c in n.get_children():
			stack.append(c)


func _push_snapshot() -> void:
	var cam_pos: Vector3 = camera.global_transform.origin
	var candidates: Array[Dictionary] = []
	for mi in _meshes:
		if not is_instance_valid(mi) or not mi.is_visible_in_tree() or mi.mesh == null:
			continue
		var gt: Transform3D = mi.global_transform
		var aabb: AABB = mi.get_aabb()
		var radius: float = aabb.size.length() * 0.5 * maxf(_max_scale(gt.basis), 0.001)
		candidates.append({"position": gt * aabb.get_center(), "radius": radius, "node": mi})
	var chosen: Array[Dictionary] = select_nearest(candidates, cam_pos,
			float(_settings["max_distance"]), int(_settings["max_instances"]))

	var extraction_budget: int = int(_settings["extractions_per_update"])
	var new_geometry: Dictionary = {}
	var instances: Array = []
	for c in chosen:
		var mi: MeshInstance3D = c["node"]
		var mesh: Mesh = mi.mesh
		for s in mesh.get_surface_count():
			var key: int = blas_key(mesh, s)
			if not _known_keys.has(key):
				if extraction_budget <= 0:
					continue
				extraction_budget -= 1
				var tri: Dictionary = extract_triangles(mesh, s)
				var verts: PackedVector3Array = tri["vertices"]
				var idx: PackedInt32Array = tri["indices"]
				_known_keys[key] = true  # also marks failed surfaces so they are not retried
				if bool(tri["ok"]):
					new_geometry[key] = {
						"vertices": pack_positions(verts),
						"indices": pack_indices(idx),
						"vertex_count": verts.size(),
						"index_count": idx.size(),
					}
				else:
					continue
			instances.append({"key": key, "transform": mi.global_transform})
	var sun_dir: Vector3 = Vector3.UP
	var sun_radius: float = 0.0047
	if sun != null and is_instance_valid(sun):
		sun_dir = sun_direction(sun)
		sun_radius = sun_angular_radius(sun)
	_effect.submit(instances, new_geometry, sun_dir, sun_radius)


func _update_sun_shadow() -> void:
	if not replace_raster_sun_shadows or sun == null or not is_instance_valid(sun):
		return
	if is_active() and bool(_settings["shadows"]):
		if not _sun_shadow_saved:
			_sun_shadow_was_enabled = sun.shadow_enabled
			_sun_shadow_saved = true
		sun.shadow_enabled = false
	else:
		_restore_sun_shadow()


func _restore_sun_shadow() -> void:
	if _sun_shadow_saved and sun != null and is_instance_valid(sun):
		sun.shadow_enabled = _sun_shadow_was_enabled
	_sun_shadow_saved = false
