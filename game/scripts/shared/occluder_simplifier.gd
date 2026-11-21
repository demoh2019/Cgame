extends RefCounted
## Builds cheap occluder geometry for OcclusionRaster and ranks candidates by screen-space value.
## Original code; concepts from Intel MOC (Apache-2.0) and Frostbite/Killzone-style occluder selection.


## 12 triangles (36 vertices) of an axis-aligned box.
static func box_occluder(aabb: AABB) -> PackedVector3Array:
	var p: Vector3 = aabb.position
	var s: Vector3 = aabb.size
	var c: Array[Vector3] = []
	for i in 8:
		c.append(Vector3(
			p.x + (s.x if (i & 1) != 0 else 0.0),
			p.y + (s.y if (i & 2) != 0 else 0.0),
			p.z + (s.z if (i & 4) != 0 else 0.0)))
	# Each face as two triangles: corner index quads.
	var quads: Array[PackedInt32Array] = [
		PackedInt32Array([0, 1, 3, 2]),
		PackedInt32Array([4, 5, 7, 6]),
		PackedInt32Array([0, 1, 5, 4]),
		PackedInt32Array([2, 3, 7, 6]),
		PackedInt32Array([0, 2, 6, 4]),
		PackedInt32Array([1, 3, 7, 5]),
	]
	var out: PackedVector3Array = PackedVector3Array()
	for q in quads:
		out.append(c[q[0]])
		out.append(c[q[1]])
		out.append(c[q[2]])
		out.append(c[q[0]])
		out.append(c[q[2]])
		out.append(c[q[3]])
	return out


## Keeps the max_tris largest triangles of the mesh (large flat faces make the best occluders).
static func from_mesh(mesh: Mesh, max_tris: int) -> PackedVector3Array:
	var out: PackedVector3Array = PackedVector3Array()
	if mesh == null or max_tris <= 0:
		return out
	var faces: PackedVector3Array = mesh.get_faces()
	var count: int = faces.size() / 3
	if count <= max_tris:
		return faces
	var areas: PackedFloat32Array = PackedFloat32Array()
	areas.resize(count)
	var order: Array[int] = []
	for i in count:
		areas[i] = (faces[i * 3 + 1] - faces[i * 3]).cross(faces[i * 3 + 2] - faces[i * 3]).length()
		order.append(i)
	order.sort_custom(func(a: int, b: int) -> bool: return areas[a] > areas[b])
	for k in max_tris:
		var t: int = order[k]
		out.append(faces[t * 3])
		out.append(faces[t * 3 + 1])
		out.append(faces[t * 3 + 2])
	return out


## Ranks candidates (AABB, or Dictionary with an "aabb" key) by approximate projected area
## (largest face area / distance^2) and returns up to `budget` of them, best first.
static func select_occluders(candidates: Array, camera_pos: Vector3, budget: int) -> Array:
	var scored: Array = []
	for cand in candidates:
		var box: AABB = AABB()
		if cand is AABB:
			box = cand
		elif cand is Dictionary:
			var d: Dictionary = cand
			if not d.has("aabb"):
				continue
			box = d["aabb"]
		else:
			continue
		scored.append([score(box, camera_pos), cand])
	scored.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) > float(b[0]))
	var out: Array = []
	for i in mini(budget, scored.size()):
		var entry: Array = scored[i]
		out.append(entry[1])
	return out


static func score(box: AABB, camera_pos: Vector3) -> float:
	var s: Vector3 = box.size
	var face: float = maxf(s.x * s.y, maxf(s.y * s.z, s.x * s.z))
	var dist_sq: float = maxf(box.get_center().distance_squared_to(camera_pos), 1.0)
	return face / dist_sq
