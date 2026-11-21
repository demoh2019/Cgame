extends RefCounted
## Bounded HLOD: several close-range instanced stone variants become one
## merged, eight-triangle-per-stone proxy surface at far camera distances.
## Native Cgame builds the geometry; stock Godot uses the same fallback.
## Decorative only: never modifies collisions, gathering, RNG or source meshes.

const MAX_INPUT_INSTANCES := 8192
const MAX_PROXY_INSTANCES := 512
const MAX_COORDINATE := 10000000.0
const MAX_HALF_EXTENT := 10000.0
const MAX_BASIS_AXIS := 1000.0
const MIN_SOURCE_INSTANCES := 8
const PROXY_END_DISTANCE := 160.0
const SWITCH_CEILING := 53.0
const SWITCH_DEADBAND := 3.0
const FACES := [
	[0, 1, 2], [0, 2, 3], [0, 3, 4], [0, 4, 1],
	[5, 2, 1], [5, 3, 2], [5, 4, 3], [5, 1, 4]
]
static var _native_checked := false
static var _native: Object = null


static func _engine() -> Object:
	if not _native_checked:
		_native_checked = true
		if ClassDB.class_exists("PCGHLODProxyBuilder3D"):
			var obj: Object = ClassDB.instantiate("PCGHLODProxyBuilder3D")
			if obj != null and obj.has_method("build_octahedral_proxy"):
				_native = obj
	return _native


static func _validate(transforms: Array[Transform3D],
		centers: PackedVector3Array, half_extents: PackedVector3Array,
		max_proxy_instances: int) -> bool:
	var count: int = transforms.size()
	if count == 0 or count > MAX_INPUT_INSTANCES or count != centers.size() or \
			count != half_extents.size() or max_proxy_instances < 1 or \
			max_proxy_instances > MAX_PROXY_INSTANCES:
		return false
	for i in count:
		var t: Transform3D = transforms[i]
		var c: Vector3 = centers[i]
		var h: Vector3 = half_extents[i]
		if not t.is_finite() or not c.is_finite() or not h.is_finite() or \
				absf(t.origin.x) > MAX_COORDINATE or \
				absf(t.origin.y) > MAX_COORDINATE or \
				absf(t.origin.z) > MAX_COORDINATE or \
				absf(c.x) > MAX_HALF_EXTENT or absf(c.y) > MAX_HALF_EXTENT or \
				absf(c.z) > MAX_HALF_EXTENT or h.x <= 0.0 or h.y <= 0.0 or \
				h.z <= 0.0 or h.x > MAX_HALF_EXTENT or h.y > MAX_HALF_EXTENT or \
				h.z > MAX_HALF_EXTENT:
			return false
		for axis in [t.basis.x, t.basis.y, t.basis.z]:
			if axis.length() < 0.0001 or axis.length() > MAX_BASIS_AXIS:
				return false
	return true


static func _build_fallback(transforms: Array[Transform3D],
		centers: PackedVector3Array, half_extents: PackedVector3Array,
		max_proxy_instances: int) -> ArrayMesh:
	if not _validate(transforms, centers, half_extents, max_proxy_instances):
		return null
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var amount: int = mini(transforms.size(), max_proxy_instances)
	for sample in amount:
		var i: int = int(sample * transforms.size() / amount)
		var transform: Transform3D = transforms[i]
		var c: Vector3 = centers[i]
		var h: Vector3 = half_extents[i]
		var positions: Array[Vector3] = [
			transform * (c + Vector3(0, h.y, 0)),
			transform * (c + Vector3(h.x, 0, 0)),
			transform * (c + Vector3(0, 0, -h.z)),
			transform * (c + Vector3(-h.x, 0, 0)),
			transform * (c + Vector3(0, 0, h.z)),
			transform * (c + Vector3(0, -h.y, 0))
		]
		for face in FACES:
			var a: Vector3 = positions[face[0]]
			var b: Vector3 = positions[face[1]]
			var v: Vector3 = positions[face[2]]
			if not a.is_finite() or not b.is_finite() or not v.is_finite():
				return null
			var normal: Vector3 = (b - a).cross(v - a).normalized()
			if not normal.is_finite() or normal.length_squared() < 0.5:
				return null
			surface.set_normal(normal)
			surface.add_vertex(a)
			surface.set_normal(normal)
			surface.add_vertex(b)
			surface.set_normal(normal)
			surface.add_vertex(v)
	return surface.commit()


static func build_proxy_mesh(transforms: Array[Transform3D],
		centers: PackedVector3Array, half_extents: PackedVector3Array,
		max_proxy_instances: int = MAX_PROXY_INSTANCES,
		prefer_native: bool = true) -> ArrayMesh:
	if not _validate(transforms, centers, half_extents, max_proxy_instances):
		return null
	if prefer_native:
		var native: Object = _engine()
		if native != null:
			var mesh: ArrayMesh = native.call("build_octahedral_proxy",
				transforms, centers, half_extents, max_proxy_instances)
			if mesh != null and mesh.get_surface_count() == 1:
				return mesh
	return _build_fallback(transforms, centers, half_extents, max_proxy_instances)


static func attach_proxy(parent: Node3D, transforms: Array[Transform3D],
		centers: PackedVector3Array, half_extents: PackedVector3Array,
		max_proxy_instances: int = 384, prefer_native: bool = true) -> MeshInstance3D:
	if parent == null or transforms.size() < MIN_SOURCE_INSTANCES:
		return null
	var combined: ArrayMesh = build_proxy_mesh(transforms, centers,
		half_extents, max_proxy_instances, prefer_native)
	if combined == null:
		return null
	var node := MeshInstance3D.new()
	node.name = "PebbleHLODProxy"
	node.mesh = combined
	var stone_material := StandardMaterial3D.new()
	stone_material.albedo_color = Color(0.39, 0.39, 0.37)
	stone_material.roughness = 0.93
	node.material_override = stone_material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.visibility_range_end = PROXY_END_DISTANCE
	node.visible = false
	node.set_meta("aa_hlod_proxy", true)
	node.set_meta("aa_hlod_source_count", transforms.size())
	node.set_meta("aa_hlod_triangle_count", combined.get_faces().size() / 3)
	parent.add_child(node)
	return node


## Pure hysteretic switch: one proxy draw replaces ALL near stone batches
## from this chunk at long distance. Do not change render buffers or AI state.
static func should_use_proxy(distance: float, near_range: float,
		was_far: bool) -> bool:
	if not is_finite(distance) or not is_finite(near_range) or near_range <= 0.0:
		return false
	var cutoff: float = minf(SWITCH_CEILING, near_range * 0.85)
	return distance >= cutoff - SWITCH_DEADBAND if was_far else \
		distance >= cutoff + SWITCH_DEADBAND


static func switch_visible(near: Array[MultiMeshInstance3D],
		proxy: MeshInstance3D, distance: float, near_range: float,
		was_far: bool) -> bool:
	if proxy == null or not is_instance_valid(proxy):
		return false
	var is_far: bool = should_use_proxy(distance, near_range, was_far)
	if is_far != was_far:
		proxy.visible = is_far
		for batch in near:
			if batch != null and is_instance_valid(batch):
				batch.visible = not is_far
	return is_far
