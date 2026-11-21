extends RefCounted
## Spline-based world authoring helpers for roads, rivers, bridges and landscape
## deformation. Inspired by Unreal Engine's Landscape Splines (deform terrain along
## a spline) and the road/river tooling of World Machine and Gaea.
## Heights are indexed y * width + x; world position of a cell is (x, y) * cell_size
## on the XZ plane (Vector3.x, Vector3.z), spline height is Vector3.y.


## Uniform Catmull-Rom through all control points (end points are duplicated).
## Result includes every control point exactly.
static func catmull_rom(points: PackedVector3Array, samples_per_segment: int) -> PackedVector3Array:
	var out := PackedVector3Array()
	var n: int = points.size()
	if n < 2:
		return points.duplicate()
	var samples: int = maxi(1, samples_per_segment)
	for i in n - 1:
		var p0: Vector3 = points[maxi(i - 1, 0)]
		var p1: Vector3 = points[i]
		var p2: Vector3 = points[i + 1]
		var p3: Vector3 = points[mini(i + 2, n - 1)]
		for s in samples:
			var t: float = float(s) / float(samples)
			var t2: float = t * t
			var t3: float = t2 * t
			out.append(0.5 * ((2.0 * p1) + (p2 - p0) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3))
	out.append(points[n - 1])
	return out


## Distance from `p` to the closest point of a polyline.
static func distance_to_polyline(p: Vector2, polyline: PackedVector2Array) -> float:
	if polyline.is_empty():
		return INF
	if polyline.size() == 1:
		return p.distance_to(polyline[0])
	var best: float = INF
	for i in polyline.size() - 1:
		var a: Vector2 = polyline[i]
		var ab: Vector2 = polyline[i + 1] - a
		var len2: float = ab.length_squared()
		var t: float = 0.0 if len2 <= 0.0 else clampf((p - a).dot(ab) / len2, 0.0, 1.0)
		best = minf(best, p.distance_to(a + ab * t))
	return best


## Deforms the heightmap around a spline. Returns a new array.
## mode: "flatten" blends terrain toward the spline height (road),
## "carve" lowers a channel 1.0 below the spline at its centre with smooth banks (river),
## "raise" only ever lifts terrain up to the spline height (embankment).
## Full effect within `half_width`, smooth falloff over the next `falloff` units.
static func deform(heights: PackedFloat32Array, width: int, height: int, cell_size: float, spline: PackedVector3Array, half_width: float, falloff: float, mode: String) -> PackedFloat32Array:
	var out: PackedFloat32Array = heights.duplicate()
	if spline.size() < 2 or heights.size() != width * height:
		return out
	var reach: float = half_width + maxf(falloff, 0.0)
	var depth: float = 1.0
	for y in height:
		for x in width:
			var p := Vector2(float(x) * cell_size, float(y) * cell_size)
			var near: Vector2 = _nearest(p, spline)  # (distance, spline height)
			if near.x > reach:
				continue
			var w: float = 1.0
			if near.x > half_width:
				w = 1.0 - smoothstep(0.0, 1.0, (near.x - half_width) / maxf(falloff, 0.0001))
			var i: int = y * width + x
			var h: float = heights[i]
			match mode:
				"flatten":
					out[i] = lerpf(h, near.y, w)
				"carve":
					var profile: float = 1.0 - smoothstep(0.0, reach, near.x)
					out[i] = lerpf(h, minf(h, near.y - depth * profile), w)
				"raise":
					out[i] = lerpf(h, maxf(h, near.y), w)
	return out


## Index ranges [start, end] (inclusive) of spline samples that float more than
## `clearance` above the terrain, i.e. where a bridge is required.
static func bridge_spans(heights: PackedFloat32Array, width: int, height: int, cell_size: float, spline: PackedVector3Array, clearance: float = 2.0) -> Array:
	var spans: Array = []
	var start: int = -1
	for i in spline.size():
		var s: Vector3 = spline[i]
		var gap: float = s.y - _sample_height(heights, width, height, cell_size, s.x, s.z)
		if gap > clearance:
			if start < 0:
				start = i
		elif start >= 0:
			spans.append({"start": start, "end": i - 1})
			start = -1
	if start >= 0:
		spans.append({"start": start, "end": spline.size() - 1})
	return spans


## Bilinear terrain height at world XZ, clamped to the grid.
static func _sample_height(heights: PackedFloat32Array, width: int, height: int, cell_size: float, wx: float, wz: float) -> float:
	var fx: float = clampf(wx / cell_size, 0.0, float(width - 1))
	var fy: float = clampf(wz / cell_size, 0.0, float(height - 1))
	var x0: int = mini(int(fx), width - 2)
	var y0: int = mini(int(fy), height - 2)
	var tx: float = fx - float(x0)
	var ty: float = fy - float(y0)
	var i: int = y0 * width + x0
	return lerpf(lerpf(heights[i], heights[i + 1], tx), lerpf(heights[i + width], heights[i + width + 1], tx), ty)


## Returns Vector2(distance, interpolated spline height) of the closest point on the XZ polyline.
static func _nearest(p: Vector2, spline: PackedVector3Array) -> Vector2:
	var best_d: float = INF
	var best_h: float = 0.0
	for i in spline.size() - 1:
		var a := Vector2(spline[i].x, spline[i].z)
		var b := Vector2(spline[i + 1].x, spline[i + 1].z)
		var ab: Vector2 = b - a
		var len2: float = ab.length_squared()
		var t: float = 0.0 if len2 <= 0.0 else clampf((p - a).dot(ab) / len2, 0.0, 1.0)
		var d: float = p.distance_to(a + ab * t)
		if d < best_d:
			best_d = d
			best_h = lerpf(spline[i].y, spline[i + 1].y, t)
	return Vector2(best_d, best_h)
