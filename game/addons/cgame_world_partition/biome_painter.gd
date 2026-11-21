@tool
extends RefCounted
## Biome weight-map brush (up to 4 biomes -> RGBA splat image) with undo, plus a
## batch mesh simplifier (ImporterMesh.generate_lods = meshoptimizer, MIT, with a
## vertex-clustering fallback in the style of Rossignac-Borrel 1993, public idea).
## Original code written for this project.

const MAX_BIOMES := 4
const MAX_UNDO := 32

var width: int = 0
var height: int = 0
var biome_count: int = MAX_BIOMES
var _weights: PackedFloat32Array = PackedFloat32Array()
var _undo: Array[PackedFloat32Array] = []


func setup(w: int, h: int, biomes: int = MAX_BIOMES) -> void:
	width = maxi(w, 1)
	height = maxi(h, 1)
	biome_count = clampi(biomes, 1, MAX_BIOMES)
	_weights = PackedFloat32Array()
	_weights.resize(width * height * MAX_BIOMES)
	_weights.fill(0.0)
	for i in width * height:
		_weights[i * MAX_BIOMES] = 1.0
	_undo.clear()


func get_weight(x: int, y: int, biome: int) -> float:
	if x < 0 or y < 0 or x >= width or y >= height or biome < 0 or biome >= MAX_BIOMES:
		return 0.0
	return _weights[(y * width + x) * MAX_BIOMES + biome]


## Soft round brush. Raises `biome` by strength*falloff and rescales the other
## biomes so the weights of every touched texel still sum to 1. Returns texels touched.
func paint(center: Vector2, radius: float, biome: int, strength: float) -> int:
	if biome < 0 or biome >= biome_count or radius <= 0.0 or strength <= 0.0 or _weights.is_empty():
		return 0
	_push_undo()
	var touched := 0
	var x0: int = maxi(floori(center.x - radius), 0)
	var x1: int = mini(ceili(center.x + radius), width - 1)
	var y0: int = maxi(floori(center.y - radius), 0)
	var y1: int = mini(ceili(center.y + radius), height - 1)
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var d: float = Vector2(float(x) + 0.5, float(y) + 0.5).distance_to(center)
			if d > radius:
				continue
			var amount: float = strength * (1.0 - d / radius)
			if amount <= 0.0:
				continue
			_raise(((y * width) + x) * MAX_BIOMES, biome, amount)
			touched += 1
	return touched


func _raise(base: int, biome: int, amount: float) -> void:
	var target: float = minf(_weights[base + biome] + amount, 1.0)
	var others := 0.0
	for b in biome_count:
		if b != biome:
			others += _weights[base + b]
	if others <= 0.000001:
		_weights[base + biome] = 1.0
		return
	var scale: float = (1.0 - target) / others
	for b in biome_count:
		if b != biome:
			_weights[base + b] *= scale
	_weights[base + biome] = target


func _push_undo() -> void:
	_undo.append(_weights.duplicate())
	if _undo.size() > MAX_UNDO:
		_undo.pop_front()


func can_undo() -> bool:
	return not _undo.is_empty()


func undo() -> bool:
	if _undo.is_empty():
		return false
	_weights = _undo.pop_back()
	return true


## RGBA8 splat map; channel i = weight of biome i (unused channels stay 0).
func to_image() -> Image:
	var img := Image.create(width, height, false, Image.FORMAT_RGBA8)
	for y in height:
		for x in width:
			var i: int = (y * width + x) * MAX_BIOMES
			img.set_pixel(x, y, Color(_weights[i], _weights[i + 1], _weights[i + 2], _weights[i + 3]))
	return img


# Batch simplification ------------------------------------------------------------

static func triangle_count(mesh: Mesh) -> int:
	if mesh == null:
		return 0
	var total := 0
	for s in mesh.get_surface_count():
		var arrays: Array = mesh.surface_get_arrays(s)
		var idx: Variant = arrays[Mesh.ARRAY_INDEX]
		if idx != null and (idx as PackedInt32Array).size() > 0:
			total += (idx as PackedInt32Array).size() / 3
		else:
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			total += verts.size() / 3
	return total


## For each mesh and ratio (0..1 of source triangles) builds a LOD mesh.
## Result entries: {source_index, ratio, source_tris, tris, mesh, method}.
func batch_simplify(meshes: Array[Mesh], ratios: Array[float]) -> Array:
	var out: Array = []
	for mi in meshes.size():
		var src: Mesh = meshes[mi]
		if src == null:
			continue
		var src_tris: int = triangle_count(src)
		for r in ratios:
			var ratio: float = clampf(r, 0.01, 1.0)
			var target: int = maxi(int(float(src_tris) * ratio), 1)
			var method := "importer_lod"
			var lod: ArrayMesh = _lod_from_importer(src, target)
			if lod == null or triangle_count(lod) >= src_tris and ratio < 1.0:
				lod = _cluster_simplify(src, target)
				method = "vertex_clustering"
			out.append({
				"source_index": mi, "ratio": ratio, "source_tris": src_tris,
				"tris": triangle_count(lod), "mesh": lod, "method": method,
			})
	return out


func _lod_from_importer(src: Mesh, target: int) -> ArrayMesh:
	var im := ImporterMesh.new()
	for s in src.get_surface_count():
		im.add_surface(_prim(src, s), src.surface_get_arrays(s), [], {}, src.surface_get_material(s))
	im.generate_lods(25.0, 60.0, [])
	var result := ArrayMesh.new()
	for s in im.get_surface_count():
		var arrays: Array = im.get_surface_arrays(s)
		var full_idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		var best: PackedInt32Array = full_idx
		var best_tris: int = full_idx.size() / 3
		var smallest: PackedInt32Array = full_idx
		for l in im.get_surface_lod_count(s):
			var li: PackedInt32Array = im.get_surface_lod_indices(s, l)
			if li.size() > 0 and li.size() < smallest.size():
				smallest = li
			var tris: int = li.size() / 3
			if tris <= target and (best_tris > target or tris > best_tris):
				best = li
				best_tris = tris
		if best_tris > target:
			best = smallest
		if best.is_empty():
			return null
		arrays[Mesh.ARRAY_INDEX] = best
		result.add_surface_from_arrays(im.get_surface_primitive_type(s), arrays)
		result.surface_set_material(result.get_surface_count() - 1, im.get_surface_material(s))
	return result


## Uniform-grid vertex clustering; searches the grid resolution that gets closest to target.
func _cluster_simplify(src: Mesh, target: int) -> ArrayMesh:
	var lo := 2
	var hi := 256
	var best: ArrayMesh = null
	while lo <= hi:
		var mid: int = (lo + hi) / 2
		var candidate: ArrayMesh = _cluster_once(src, mid)
		if triangle_count(candidate) <= target:
			best = candidate
			lo = mid + 1
		else:
			hi = mid - 1
	if best == null:
		best = _cluster_once(src, 2)
	return best


func _cluster_once(src: Mesh, res: int) -> ArrayMesh:
	var aabb: AABB = src.get_aabb()
	var cell: Vector3 = aabb.size / float(res)
	cell = Vector3(maxf(cell.x, 0.00001), maxf(cell.y, 0.00001), maxf(cell.z, 0.00001))
	var result := ArrayMesh.new()
	for s in src.get_surface_count():
		if _prim(src, s) != Mesh.PRIMITIVE_TRIANGLES:
			continue
		var arrays: Array = src.surface_get_arrays(s)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var idx: PackedInt32Array = PackedInt32Array()
		if arrays[Mesh.ARRAY_INDEX] != null:
			idx = arrays[Mesh.ARRAY_INDEX]
		else:
			idx.resize(verts.size())
			for i in verts.size():
				idx[i] = i
		var remap: Dictionary = {}
		var sums: Array[Vector3] = []
		var counts: PackedInt32Array = PackedInt32Array()
		var vmap := PackedInt32Array()
		vmap.resize(verts.size())
		for i in verts.size():
			var rel: Vector3 = (verts[i] - aabb.position) / cell
			var key := Vector3i(floori(rel.x), floori(rel.y), floori(rel.z))
			if not remap.has(key):
				remap[key] = sums.size()
				sums.append(Vector3.ZERO)
				counts.append(0)
			var ci: int = remap[key]
			sums[ci] += verts[i]
			counts[ci] += 1
			vmap[i] = ci
		var new_verts := PackedVector3Array()
		for ci in sums.size():
			new_verts.append(sums[ci] / float(counts[ci]))
		var new_idx := PackedInt32Array()
		var t := 0
		while t + 2 < idx.size():
			var a: int = vmap[idx[t]]
			var b: int = vmap[idx[t + 1]]
			var c: int = vmap[idx[t + 2]]
			if a != b and b != c and a != c:
				new_idx.append_array(PackedInt32Array([a, b, c]))
			t += 3
		if new_idx.is_empty():
			continue
		var na: Array = []
		na.resize(Mesh.ARRAY_MAX)
		na[Mesh.ARRAY_VERTEX] = new_verts
		na[Mesh.ARRAY_INDEX] = new_idx
		result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, na)
		result.surface_set_material(result.get_surface_count() - 1, src.surface_get_material(s))
	return result


func _prim(mesh: Mesh, surface: int) -> Mesh.PrimitiveType:
	if mesh is ArrayMesh:
		return (mesh as ArrayMesh).surface_get_primitive_type(surface) as Mesh.PrimitiveType
	return Mesh.PRIMITIVE_TRIANGLES
