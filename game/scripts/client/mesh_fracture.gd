extends RefCounted
## Runtime mesh fracturing for destructible props: turns Voronoi cells into
## render meshes, convex collision shapes and physics debris, with fracture LOD.
## Original code; cell generation lives in res://scripts/shared/voronoi_fracture.gd.

const VoronoiFracture = preload("res://scripts/shared/voronoi_fracture.gd")

const DENSITY := 500.0


## Per cell: {"mesh": ArrayMesh, "shape": ConvexPolygonShape3D, "center", "volume"}.
## Mesh and shape are centred on `center` so a body can sit at that point.
static func build_fragments(cells: Array, material: Material = null) -> Array:
	var out: Array = []
	for cell in cells:
		var pts: PackedVector3Array = cell
		if pts.size() < 4:
			continue
		var c := VoronoiFracture.centroid(pts)
		var local := PackedVector3Array()
		for p in pts:
			local.append(p - c)
		var tris := VoronoiFracture.hull_triangles(local)
		if tris.is_empty():
			continue
		var verts := PackedVector3Array()
		var normals := PackedVector3Array()
		var k := 0
		while k + 2 < tris.size():
			var n: Vector3 = (tris[k + 1] - tris[k]).cross(tris[k + 2] - tris[k]).normalized()
			for m in 3:
				verts.append(tris[k + m])
				normals.append(n)
			k += 3
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_NORMAL] = normals
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		if material != null:
			mesh.surface_set_material(0, material)
		var shape := ConvexPolygonShape3D.new()
		shape.points = local
		out.append({"mesh": mesh, "shape": shape, "center": c, "volume": VoronoiFracture.cell_volume(pts)})
	return out


## Spawns one RigidBody3D per fragment under `parent`. `origin` is the prop's
## transform in parent space; `impulse_point` is in parent space too.
static func spawn_debris(parent: Node3D, origin: Transform3D, fragments: Array, impulse_point: Vector3, impulse: float, lifetime: float = 8.0) -> Array:
	var bodies: Array = []
	for f in fragments:
		var frag: Dictionary = f
		var center: Vector3 = frag["center"]
		var volume: float = frag["volume"]
		var body := RigidBody3D.new()
		body.mass = maxf(volume * DENSITY, 0.05)
		body.transform = origin * Transform3D(Basis.IDENTITY, center)
		var mi := MeshInstance3D.new()
		mi.mesh = frag["mesh"] as Mesh
		body.add_child(mi)
		var cs := CollisionShape3D.new()
		cs.shape = frag["shape"] as Shape3D
		body.add_child(cs)
		var away: Vector3 = body.transform.origin - impulse_point
		if away.length() < 1e-4:
			away = Vector3.UP
		body.linear_velocity = away.normalized() * impulse / body.mass
		var timer := Timer.new()
		timer.one_shot = true
		timer.wait_time = maxf(lifetime, 0.01)
		timer.autostart = true
		timer.timeout.connect(body.queue_free)
		body.add_child(timer)
		parent.add_child(body)
		bodies.append(body)
	return bodies


## Hierarchical fracture LOD: fewer pieces the farther the camera.
static func lod_count(distance: float) -> int:
	if distance < 10.0:
		return 24
	if distance < 25.0:
		return 12
	if distance < 50.0:
		return 6
	if distance < 100.0:
		return 3
	return 1
