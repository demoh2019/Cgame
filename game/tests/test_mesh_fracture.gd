extends RefCounted
## Voronoi box fracture, fragment meshes/shapes, debris spawning and fracture LOD.

const VoronoiFracture = preload("res://scripts/shared/voronoi_fracture.gd")
const MeshFracture = preload("res://scripts/client/mesh_fracture.gd")

const SIZE := Vector3(2.0, 1.0, 1.5)


func run(t) -> void:
	t.current = "voronoi volume"
	var sites := VoronoiFracture.random_sites(SIZE, 12, 7)
	var cells := VoronoiFracture.fracture_box(SIZE, sites)
	t.eq(cells.size(), 12, "one cell per site")
	var total := 0.0
	var inside := true
	var convex := true
	for cell in cells:
		var pts: PackedVector3Array = cell
		total += VoronoiFracture.cell_volume(pts)
		var half := SIZE * 0.5 + Vector3.ONE * 0.001
		for p in pts:
			if absf(p.x) > half.x or absf(p.y) > half.y or absf(p.z) > half.z:
				inside = false
		var c := VoronoiFracture.centroid(pts)
		var tris := VoronoiFracture.hull_triangles(pts)
		var k := 0
		while k + 2 < tris.size():
			var n := (tris[k + 1] - tris[k]).cross(tris[k + 2] - tris[k]).normalized()
			for p in pts:
				if n.dot(p - tris[k]) > 0.001:
					convex = false
			if n.dot(tris[k] - c) < 0.0:
				convex = false
			k += 3
	var box_vol := SIZE.x * SIZE.y * SIZE.z
	t.near(total / box_vol, 1.0, 0.01, "cell volumes sum to the box volume")
	t.check(inside, "cells stay inside the box")
	t.check(convex, "cells are convex with outward hulls")

	t.current = "voronoi sites"
	var again := VoronoiFracture.random_sites(SIZE, 12, 7)
	t.check(again == sites, "same seed gives same sites")
	t.check(VoronoiFracture.random_sites(SIZE, 12, 8) != sites, "different seed differs")
	var impact := Vector3(0.9, 0.4, 0.0)
	var plain := VoronoiFracture.random_sites(SIZE, 60, 3)
	var biased := VoronoiFracture.random_sites(SIZE, 60, 3, impact, 0.8)
	t.check(_mean_dist(biased, impact) < _mean_dist(plain, impact) * 0.7, "impact bias clusters sites near the hit")

	t.current = "fragments"
	var mat := StandardMaterial3D.new()
	var frags := MeshFracture.build_fragments(cells, mat)
	t.eq(frags.size(), 12, "fragment per cell")
	var meshes_ok := true
	var normals_ok := true
	var shapes_ok := true
	for f in frags:
		var d: Dictionary = f
		var mesh: ArrayMesh = d["mesh"]
		if mesh.get_surface_count() != 1:
			meshes_ok = false
			continue
		var arr: Array = mesh.surface_get_arrays(0)
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var nr: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
		if v.size() < 12 or v.size() != nr.size():
			meshes_ok = false
		for i in v.size():
			if nr[i].dot(v[i]) < -0.0001:
				normals_ok = false
		var shape: ConvexPolygonShape3D = d["shape"]
		if shape == null or shape.points.size() < 4:
			shapes_ok = false
		if float(d["volume"]) <= 0.0:
			shapes_ok = false
	t.check(meshes_ok, "fragment meshes are non-empty")
	t.check(normals_ok, "fragment normals point outward")
	t.check(shapes_ok, "convex shapes and volumes created")

	t.current = "debris"
	var parent := Node3D.new()
	var bodies := MeshFracture.spawn_debris(parent, Transform3D(Basis.IDENTITY, Vector3(0, 5, 0)), frags, Vector3(0, 5, 0), 20.0, 2.0)
	t.eq(bodies.size(), 12, "one body per fragment")
	t.eq(parent.get_child_count(), 12, "bodies parented")
	var body: RigidBody3D = bodies[0]
	t.check(body.mass > 0.0, "mass from volume")
	t.check(body.linear_velocity.length() > 0.0, "impulse applied")
	parent.free()

	t.current = "fracture lod"
	t.check(MeshFracture.lod_count(5.0) > MeshFracture.lod_count(30.0), "near > mid")
	t.check(MeshFracture.lod_count(30.0) > MeshFracture.lod_count(80.0), "mid > far")
	t.check(MeshFracture.lod_count(80.0) > MeshFracture.lod_count(500.0), "far > very far")
	t.check(MeshFracture.lod_count(1000.0) >= 1, "at least one piece")


func _mean_dist(pts: PackedVector3Array, p: Vector3) -> float:
	var s := 0.0
	for q in pts:
		s += q.distance_to(p)
	return s / float(pts.size())
