extends RefCounted
## Low-poly meshes built in code, so the game needs no imported art. Each is a single vertex-coloured
## surface, which lets a MultiMesh draw thousands of them in one call.

static var _cache: Dictionary = {}


static func get_mesh(name: String) -> Mesh:
	if not _cache.has(name):
		match name:
			"tree": _cache[name] = _build_tree()
			"rock": _cache[name] = _build_rock()
			"ore": _cache[name] = _build_ore()
			"bush": _cache[name] = _build_bush()
			"berry": _cache[name] = _build_berry()
			"crate": _cache[name] = _build_crate()
			"bag": _cache[name] = _build_bag()
			"wall": _cache[name] = _build_wall()
			"body": _cache[name] = _build_body()
			_: push_error("unknown mesh " + name)
	return _cache[name]


static func material() -> StandardMaterial3D:
	if not _cache.has("material"):
		var m := StandardMaterial3D.new()
		m.vertex_color_use_as_albedo = true
		m.roughness = 0.95
		_cache["material"] = m
	return _cache["material"]


static func _combine(parts: Array) -> ArrayMesh:
	# parts: [[mesh, transform, color], ...]
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for part in parts:
		var mesh: Mesh = part[0]
		var transform: Transform3D = part[1]
		var color: Color = part[2]
		var arrays := mesh.surface_get_arrays(0)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		for index in indices:
			surface.set_color(color)
			surface.set_normal((transform.basis * normals[index]).normalized())
			surface.add_vertex(transform * vertices[index])
	var result := surface.commit()
	result.surface_set_material(0, material())
	return result


static func _cyl(top: float, bottom: float, height: float, sides: int = 6) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = top
	m.bottom_radius = bottom
	m.height = height
	m.radial_segments = sides
	m.rings = 1
	return m


static func _sphere(radius: float, squash: float = 1.0) -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = radius
	m.height = radius * 2.0 * squash
	m.radial_segments = 7
	m.rings = 4
	return m


static func _box(size: Vector3) -> BoxMesh:
	var m := BoxMesh.new()
	m.size = size
	return m


static func _build_tree() -> ArrayMesh:
	return _combine([
		[_cyl(0.16, 0.24, 2.0), Transform3D(Basis(), Vector3(0, 1.0, 0)), Color(0.42, 0.28, 0.16)],
		[_cyl(0.0, 1.3, 2.4, 7), Transform3D(Basis(), Vector3(0, 3.0, 0)), Color(0.14, 0.38, 0.17)],
		[_cyl(0.0, 1.0, 1.8, 7), Transform3D(Basis(), Vector3(0, 4.2, 0)), Color(0.18, 0.45, 0.2)],
	])


static func _build_rock() -> ArrayMesh:
	return _combine([
		[_sphere(0.9, 0.75), Transform3D(Basis().scaled(Vector3(1.1, 1.0, 0.9)), Vector3(0, 0.45, 0)), Color(0.52, 0.52, 0.54)],
		[_sphere(0.5, 0.8), Transform3D(Basis(), Vector3(0.6, 0.25, 0.3)), Color(0.45, 0.45, 0.48)],
	])


static func _build_ore() -> ArrayMesh:
	return _combine([
		[_sphere(0.85, 0.8), Transform3D(Basis(), Vector3(0, 0.42, 0)), Color(0.38, 0.36, 0.38)],
		[_box(Vector3(0.28, 0.5, 0.28)), Transform3D(Basis(Vector3(0, 0, 1), 0.5), Vector3(0.3, 0.85, 0.1)), Color(0.85, 0.62, 0.25)],
		[_box(Vector3(0.22, 0.4, 0.22)), Transform3D(Basis(Vector3(1, 0, 0), -0.4), Vector3(-0.35, 0.8, -0.2)), Color(0.9, 0.7, 0.3)],
	])


static func _build_bush() -> ArrayMesh:
	return _combine([
		[_sphere(0.5, 0.8), Transform3D(Basis(), Vector3(0, 0.35, 0)), Color(0.25, 0.5, 0.22)],
		[_sphere(0.35, 0.8), Transform3D(Basis(), Vector3(0.35, 0.3, 0.1)), Color(0.3, 0.55, 0.24)],
	])


static func _build_berry() -> ArrayMesh:
	var parts: Array = [[_sphere(0.5, 0.8), Transform3D(Basis(), Vector3(0, 0.35, 0)), Color(0.2, 0.42, 0.2)]]
	for i in 6:
		var a := float(i) * TAU / 6.0
		parts.append([_sphere(0.09, 1.0), Transform3D(Basis(), Vector3(cos(a) * 0.42, 0.45 + 0.08 * (i % 2), sin(a) * 0.42)), Color(0.8, 0.1, 0.18)])
	return _combine(parts)


static func _build_crate() -> ArrayMesh:
	return _combine([
		[_box(Vector3(1.1, 0.9, 1.1)), Transform3D(Basis(), Vector3(0, 0.45, 0)), Color(0.5, 0.36, 0.2)],
		[_box(Vector3(1.16, 0.12, 1.16)), Transform3D(Basis(), Vector3(0, 0.9, 0)), Color(0.36, 0.26, 0.15)],
		[_box(Vector3(0.12, 0.95, 1.16)), Transform3D(Basis(), Vector3(0, 0.45, 0)), Color(0.36, 0.26, 0.15)],
	])


static func _build_bag() -> ArrayMesh:
	return _combine([
		[_sphere(0.34, 0.9), Transform3D(Basis(), Vector3(0, 0.28, 0)), Color(0.55, 0.38, 0.2)],
		[_cyl(0.1, 0.16, 0.22), Transform3D(Basis(), Vector3(0, 0.58, 0)), Color(0.4, 0.28, 0.15)],
		[_sphere(0.12, 1.0), Transform3D(Basis(), Vector3(0, 0.78, 0)), Color(0.95, 0.8, 0.2)],
	])


static func _build_wall() -> ArrayMesh:
	return _combine([
		[_box(Vector3(4.0, 2.6, 0.4)), Transform3D(Basis(), Vector3(0, 1.3, 0)), Color(0.44, 0.43, 0.42)],
		[_box(Vector3(1.4, 1.2, 0.46)), Transform3D(Basis(), Vector3(1.0, 3.0, 0)), Color(0.38, 0.37, 0.36)],
	])


static func _build_body() -> ArrayMesh:
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.38
	capsule.height = 1.75
	capsule.radial_segments = 8
	capsule.rings = 3
	var head := _sphere(0.22, 1.0)
	return _combine([
		[capsule, Transform3D(Basis(), Vector3(0, 0.9, 0)), Color(1, 1, 1)],
		[head, Transform3D(Basis(), Vector3(0, 1.85, 0)), Color(0.95, 0.8, 0.65)],
		[_box(Vector3(0.12, 0.12, 0.5)), Transform3D(Basis(), Vector3(0.0, 1.0, 0.45)), Color(0.3, 0.3, 0.32)],
	])
