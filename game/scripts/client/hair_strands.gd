extends RefCounted
## Strand-based hair: guide-strand physics, interpolated render strands, capsule collision,
## LOD, culling and camera-facing ribbon mesh building.
##
## Techniques (algorithms re-implemented from the papers/descriptions, no code copied):
## - Dynamic Follow-The-Leader (DFTL): Matthias Mueller, Tae-Yong Kim, Nuttapong Chentanez,
##   "Fast Simulation of Inextensible Hair and Fur", VRIPHYS 2012
##   (https://matthias-research.github.io/pages/publications/FTLHairFur.pdf). Paper, no license
##   implied; only the published idea is used.
## - Global shape matching, local length constraints, guide -> render strand interpolation and
##   capsule collision follow the concepts of AMD TressFX
##   (https://github.com/GPUOpen-Effects/TressFX, Copyright (c) AMD, MIT license).
## - Camera-facing ribbons expanded in the vertex shader (assets/shaders/hair_strand.gdshader).
##
## Layout: guide g owns points [g*points_per_guide, (g+1)*points_per_guide); point 0 is the pinned
## root. `rest` is in head space, `pos`/`prev` in world space (Verlet).

var segments: int = 0
var guide_count: int = 0
var points_per_guide: int = 0
var seg_len: float = 0.0

var rest := PackedVector3Array()
var pos := PackedVector3Array()
var prev := PackedVector3Array()
var neighbors := PackedInt32Array()  ## two nearest guides per guide, used for interpolation

var gravity := Vector3(0.0, -9.8, 0.0)
var wind := Vector3.ZERO
var damping: float = 0.98  ## per-frame (60 Hz) velocity retention
var stiffness: float = 0.08  ## global shape matching, per-frame (60 Hz) pull toward the rest pose
var stiffness_root_bias: float = 0.5  ## tip stiffness = stiffness * (1 - bias)
var ftl_damping: float = 0.9  ## fraction of the constraint correction removed from velocity
var iterations: int = 2
var collision_margin: float = 0.002
var strand_spread: float = 0.012  ## lateral jitter of interpolated strands (metres)
var max_per_guide: int = 8
var max_distance: float = 60.0

var _cap_a := PackedVector3Array()
var _cap_b := PackedVector3Array()
var _cap_r := PackedFloat32Array()
var _initialized: bool = false


## Builds straight guides along the root normals (in head space).
func grow_guides(root_points: PackedVector3Array, root_normals: PackedVector3Array, p_segments: int, length: float) -> void:
	guide_count = mini(root_points.size(), root_normals.size())
	segments = maxi(p_segments, 1)
	points_per_guide = segments + 1
	seg_len = length / float(segments)
	rest.resize(guide_count * points_per_guide)
	pos.resize(rest.size())
	prev.resize(rest.size())
	for g in guide_count:
		var n: Vector3 = root_normals[g].normalized()
		for i in points_per_guide:
			rest[g * points_per_guide + i] = root_points[g] + n * (seg_len * float(i))
	_build_neighbors()
	_initialized = false


func add_capsule(a: Vector3, b: Vector3, r: float) -> void:
	_cap_a.append(a)
	_cap_b.append(b)
	_cap_r.append(r)


func clear_capsules() -> void:
	_cap_a.clear()
	_cap_b.clear()
	_cap_r.clear()


## Snaps the whole hair to the rest pose under the given head transform (no velocity).
func reset(head_transform: Transform3D) -> void:
	for i in rest.size():
		var w: Vector3 = head_transform * rest[i]
		pos[i] = w
		prev[i] = w
	_initialized = true


func guide_points(g: int) -> PackedVector3Array:
	return pos.slice(g * points_per_guide, (g + 1) * points_per_guide)


func step(dt: float, head_transform: Transform3D) -> void:
	if guide_count == 0 or dt <= 0.0:
		return
	if not _initialized:
		reset(head_transform)
	var frames: float = dt * 60.0
	var damp: float = pow(damping, frames)
	var accel: Vector3 = gravity + wind
	var dt2: float = dt * dt
	var inv: Transform3D = head_transform.affine_inverse()
	var count: int = points_per_guide
	for g in guide_count:
		var base: int = g * count
		var root: Vector3 = head_transform * rest[base]
		pos[base] = root
		prev[base] = root
		# Verlet integration + global shape matching toward the (moving) rest pose.
		for i in range(1, count):
			var k: int = base + i
			var p: Vector3 = pos[k]
			var np: Vector3 = p + (p - prev[k]) * damp + accel * dt2
			prev[k] = p
			var t: float = float(i) / float(segments)
			var stiff: float = 1.0 - pow(1.0 - stiffness * (1.0 - stiffness_root_bias * t), frames)
			np += (head_transform * rest[k] - np) * stiff
			pos[k] = np
		# DFTL: each follower is pulled back to segment length from its leader, and the induced
		# velocity is damped so the chain does not whip.
		for _it in iterations:
			for i in range(1, count):
				var k2: int = base + i
				var d: Vector3 = pos[k2] - pos[k2 - 1]
				var l: float = d.length()
				if l > 0.000001:
					var corr: Vector3 = d * (seg_len / l) - d
					pos[k2] += corr
					prev[k2] += corr * ftl_damping
			_collide(base, head_transform, inv)


## Interpolated render strands: per_guide strands per guide, blended from the guide and its two
## nearest neighbours with seeded random weights and a lateral offset. Strand 0 of each guide is
## the guide itself.
func render_strands(per_guide: int, seed: int) -> Array:
	var out: Array = []
	if guide_count == 0 or per_guide <= 0:
		return out
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var count: int = points_per_guide
	for g in guide_count:
		var g1: int = neighbors[g * 2]
		var g2: int = neighbors[g * 2 + 1]
		for s in per_guide:
			var strand := PackedVector3Array()
			strand.resize(count)
			var w1: float = 0.0
			var w2: float = 0.0
			var off := Vector3.ZERO
			if s > 0:
				w1 = rng.randf() * 0.35
				w2 = rng.randf() * 0.35
				off = Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0)) * strand_spread
			var w0: float = 1.0 - w1 - w2
			for i in count:
				var t: float = float(i) / float(segments)
				var p: Vector3 = pos[g * count + i] * w0 + pos[g1 * count + i] * w1 + pos[g2 * count + i] * w2
				strand[i] = p + off * (0.25 + 0.75 * t) * minf(t * 4.0, 1.0)
			out.append(strand)
	return out


## Render strands per guide for a given screen coverage (0..1 of the viewport height-ish).
## 0 means too small to draw. Monotonic non-decreasing.
func lod_strand_count(screen_coverage: float) -> int:
	if screen_coverage <= 0.002:
		return 0
	var c: float = clampf(screen_coverage, 0.0, 1.0)
	return clampi(1 + roundi(float(max_per_guide - 1) * sqrt(c)), 1, max_per_guide)


## Visible guide indices. `view_frustum_planes` use Godot's Camera3D.get_frustum() convention:
## normals point outward, a point is inside when distance_to() <= 0 for every plane.
func cull(view_frustum_planes: Array[Plane], view_pos: Vector3) -> PackedInt32Array:
	var visible := PackedInt32Array()
	var count: int = points_per_guide
	for g in guide_count:
		var center := Vector3.ZERO
		for i in count:
			center += pos[g * count + i]
		center /= float(count)
		var radius: float = 0.0
		for i in count:
			radius = maxf(radius, center.distance_to(pos[g * count + i]))
		if center.distance_to(view_pos) - radius > max_distance:
			continue
		var inside := true
		for plane in view_frustum_planes:
			if plane.distance_to(center) > radius:
				inside = false
				break
		if inside:
			visible.append(g)
	return visible


## Ribbon mesh: every strand point becomes two vertices at the same position. Per vertex:
## NORMAL = strand tangent, UV = (side 0/1, t root->tip), COLOR = (half width, per-strand random,
## t, 1). The shader expands the ribbon toward the camera.
func build_mesh(strands: Array, width: float) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	for s in strands.size():
		var pts: PackedVector3Array = strands[s]
		var n: int = pts.size()
		if n < 2:
			continue
		var rnd: float = float((s * 2654435761) & 0xFFFF) / 65535.0
		var first: int = verts.size()
		for i in n:
			var a: Vector3 = pts[maxi(i - 1, 0)]
			var b: Vector3 = pts[mini(i + 1, n - 1)]
			var tan: Vector3 = (b - a).normalized()
			var t: float = float(i) / float(n - 1)
			for side in 2:
				verts.append(pts[i])
				norms.append(tan)
				uvs.append(Vector2(float(side), t))
				cols.append(Color(width * 0.5, rnd, t, 1.0))
		for i in n - 1:
			var v: int = first + i * 2
			idx.append_array(PackedInt32Array([v, v + 1, v + 2, v + 1, v + 3, v + 2]))
	if verts.is_empty():
		return mesh
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_INDEX] = idx
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _collide(base: int, head_transform: Transform3D, inv: Transform3D) -> void:
	if _cap_r.is_empty():
		return
	for i in range(1, points_per_guide):
		var k: int = base + i
		var local: Vector3 = inv * pos[k]
		var moved := false
		for c in _cap_r.size():
			var a: Vector3 = _cap_a[c]
			var ab: Vector3 = _cap_b[c] - a
			var denom: float = ab.length_squared()
			var t: float = 0.0
			if denom > 0.0000001:
				t = clampf((local - a).dot(ab) / denom, 0.0, 1.0)
			var q: Vector3 = a + ab * t
			var d: Vector3 = local - q
			var dl: float = d.length()
			var rr: float = _cap_r[c] + collision_margin
			if dl < rr:
				var n: Vector3 = d / dl if dl > 0.000001 else Vector3.UP
				local = q + n * rr
				moved = true
		if moved:
			var w: Vector3 = head_transform * local
			prev[k] = prev[k].lerp(w, 0.5)  # friction: kill part of the inward velocity
			pos[k] = w


func _build_neighbors() -> void:
	neighbors.resize(guide_count * 2)
	for g in guide_count:
		var best1: int = g
		var best2: int = g
		var d1: float = INF
		var d2: float = INF
		var r: Vector3 = rest[g * points_per_guide]
		for o in guide_count:
			if o == g:
				continue
			var d: float = r.distance_squared_to(rest[o * points_per_guide])
			if d < d1:
				d2 = d1
				best2 = best1
				d1 = d
				best1 = o
			elif d < d2:
				d2 = d
				best2 = o
		neighbors[g * 2] = best1
		neighbors[g * 2 + 1] = best2
