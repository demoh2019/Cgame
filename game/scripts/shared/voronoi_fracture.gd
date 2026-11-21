extends RefCounted
## Voronoi fracture of a box into convex cells (Geometry Collection / Chaos style).
##
## Method: each cell is the intersection of the box's six half-spaces with one
## perpendicular-bisector half-space per other site (convex polyhedron clipping).
## This is the classic Voronoi-cell construction (Aurenhammer, "Voronoi diagrams",
## ACM Computing Surveys 1991); vertices come from Godot's own plane intersection
## (Geometry3D.compute_convex_mesh_points) and the hull is triangulated by a small
## original brute-force routine. No third-party code is copied.

const EPS := 1e-4


## One convex cell per site, as hull points. The box is centred at the origin.
## A site whose cell is empty (coincident with another) yields an empty array.
static func fracture_box(size: Vector3, sites: PackedVector3Array) -> Array:
	var half := size * 0.5
	var base: Array[Plane] = [
		Plane(Vector3.RIGHT, half.x), Plane(Vector3.LEFT, half.x),
		Plane(Vector3.UP, half.y), Plane(Vector3.DOWN, half.y),
		Plane(Vector3.BACK, half.z), Plane(Vector3.FORWARD, half.z),
	]
	var cells: Array = []
	for i in sites.size():
		var planes: Array[Plane] = base.duplicate()
		var si: Vector3 = sites[i]
		for j in sites.size():
			if j == i:
				continue
			var d: Vector3 = sites[j] - si
			var len := d.length()
			if len < 1e-6:
				continue
			var n: Vector3 = d / len
			var mid: Vector3 = (si + sites[j]) * 0.5
			planes.append(Plane(n, n.dot(mid)))
		cells.append(_dedupe(Geometry3D.compute_convex_mesh_points(planes)))
	return cells


## Sites inside the box (centred at origin); clustered near `impact` when given.
static func random_sites(size: Vector3, count: int, seed: int, impact: Vector3 = Vector3.INF, impact_bias: float = 0.0) -> PackedVector3Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var half := size * 0.5
	var out := PackedVector3Array()
	var clustered := impact.is_finite() and impact_bias > 0.0
	for i in count:
		var p := Vector3(rng.randf_range(-half.x, half.x), rng.randf_range(-half.y, half.y), rng.randf_range(-half.z, half.z))
		if clustered:
			# Pull toward the impact; sites nearest the hit get the strongest pull.
			var pull: float = clampf(impact_bias, 0.0, 1.0) * rng.randf_range(0.5, 1.0)
			p = p.lerp(impact, pull)
			p = p.clamp(-half, half)
		out.append(p)
	return out


static func cell_volume(points: PackedVector3Array) -> float:
	if points.size() < 4:
		return 0.0
	var c := centroid(points)
	var tris := hull_triangles(points)
	var vol := 0.0
	var k := 0
	while k + 2 < tris.size():
		vol += absf((tris[k] - c).dot((tris[k + 1] - c).cross(tris[k + 2] - c)))
		k += 3
	return vol / 6.0


static func centroid(points: PackedVector3Array) -> Vector3:
	if points.is_empty():
		return Vector3.ZERO
	var c := Vector3.ZERO
	for p in points:
		c += p
	return c / float(points.size())


## Triangulated convex hull (flat triangle list, counter-clockwise seen from outside).
## Brute force over point triples: fine for the small cells fracturing produces.
static func hull_triangles(points: PackedVector3Array) -> PackedVector3Array:
	var out := PackedVector3Array()
	var n := points.size()
	if n < 4:
		return out
	var c := centroid(points)
	var covered: Dictionary = {}
	for i in n:
		for j in range(i + 1, n):
			for k in range(j + 1, n):
				if covered.has(_tri_key(i, j, k, n)):
					continue
				var normal: Vector3 = (points[j] - points[i]).cross(points[k] - points[i])
				if normal.length() < 1e-9:
					continue
				normal = normal.normalized()
				var d := normal.dot(points[i])
				var pos := 0
				var neg := 0
				var face: Array[int] = []
				for m in n:
					var s := normal.dot(points[m]) - d
					if s > EPS:
						pos += 1
					elif s < -EPS:
						neg += 1
					else:
						face.append(m)
				if pos > 0 and neg > 0:
					continue
				for a in face:
					for b in face:
						for e in face:
							if a < b and b < e:
								covered[_tri_key(a, b, e, n)] = true
				if pos > 0:
					normal = -normal
				_fan(points, face, normal, out)
	return out


static func _tri_key(i: int, j: int, k: int, n: int) -> int:
	return (i * n + j) * n + k


static func _fan(points: PackedVector3Array, face: Array[int], normal: Vector3, out: PackedVector3Array) -> void:
	var fc := Vector3.ZERO
	for idx in face:
		fc += points[idx]
	fc /= float(face.size())
	var u: Vector3 = (points[face[0]] - fc).normalized()
	var v: Vector3 = normal.cross(u)
	var order: Array = []
	for idx in face:
		var r: Vector3 = points[idx] - fc
		order.append([atan2(r.dot(v), r.dot(u)), idx])
	order.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	for t in range(1, order.size() - 1):
		out.append(points[order[0][1] as int])
		out.append(points[order[t][1] as int])
		out.append(points[order[t + 1][1] as int])


static func _dedupe(points: PackedVector3Array) -> PackedVector3Array:
	var out := PackedVector3Array()
	for p in points:
		var dup := false
		for q in out:
			if p.distance_squared_to(q) < 1e-8:
				dup = true
				break
		if not dup:
			out.append(p)
	return out
