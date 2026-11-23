extends RefCounted
## Seeded city footprints, lots and street paths, shared by authoritative generation and road painting.
## Offsets are relative to the city centre; rotation is applied only at the output boundary.

const TYPES := ["grid", "radial", "oval", "hexagonal", "organic", "linear", "triangular", "crescent"]


static func layout_for_seed(seed: int) -> String:
	return TYPES[posmod(seed, TYPES.size())]


static func rotation_for_seed(seed: int) -> float:
	return float(posmod(seed, 360)) * TAU / 360.0


static func contains(offset: Vector2, layout: String, radius: float, rotation: float = 0.0) -> bool:
	if radius <= 0.0 or not offset.is_finite():
		return false
	var p: Vector2 = offset.rotated(-rotation)
	var x: float = absf(p.x)
	var y: float = absf(p.y)
	match layout:
		"grid":
			return maxf(x, y) <= radius * 0.63
		"radial":
			return p.length() <= radius * 0.82
		"oval":
			var a: float = radius * 0.82
			var b: float = radius * 0.50
			return (p.x / a) * (p.x / a) + (p.y / b) * (p.y / b) <= 1.0
		"hexagonal":
			return maxf(y * 1.154701, x + y * 0.5773503) <= radius * 0.79
		"organic":
			var theta: float = p.angle()
			var edge: float = radius * (0.67 + 0.08 * sin(theta * 3.0) + 0.055 * cos(theta * 5.0))
			return p.length() <= edge
		"linear":
			return x <= radius * 0.80 and y <= radius * 0.30
		"triangular":
			var top: float = -radius * 0.82
			var bottom: float = radius * 0.50
			var half_width: float = radius * 0.70 * (p.y - top) / (bottom - top)
			return p.y >= top and p.y <= bottom and x <= half_width
		"crescent":
			return p.length() <= radius * 0.82 and (p - Vector2(radius * 0.42, 0.0)).length() >= radius * 0.30
		_:
			return false


## Candidate building lots, deliberately separated by roads. The caller validates water and collision spacing.
static func building_lots(seed: int, layout: String, radius: float, rotation: float) -> Array[Dictionary]:
	var candidates: Array[Vector2] = []
	match layout:
		"grid":
			for ix in range(-3, 3):
				for iy in range(-3, 3):
					candidates.append(Vector2(float(ix) + 0.5, float(iy) + 0.5) * radius * 0.185)
		"radial":
			for ring in 3:
				var distance: float = radius * float([0.31, 0.54, 0.78][ring])
				var count: int = int([10, 16, 22][ring])
				for i in count:
					var theta: float = TAU * (float(i) + 0.5) / float(count)
					if absf(sin(theta * 2.0)) < 0.20:
						continue # Four broad radial avenues.
					candidates.append(Vector2.from_angle(theta) * distance)
		"oval":
			for ring in 2:
				var rx: float = radius * float([0.35, 0.72][ring])
				var ry: float = radius * float([0.22, 0.41][ring])
				var count: int = int([12, 26][ring])
				for i in count:
					var theta: float = TAU * (float(i) + 0.5) / float(count)
					candidates.append(Vector2(cos(theta) * rx, sin(theta) * ry))
		"hexagonal":
			for ring in 2:
				var distance: float = radius * float([0.34, 0.69][ring])
				var steps: int = int([2, 3][ring])
				for side in 6:
					var first: Vector2 = Vector2.from_angle(TAU * float(side) / 6.0) * distance
					var last: Vector2 = Vector2.from_angle(TAU * float(side + 1) / 6.0) * distance
					for i in steps:
						candidates.append(first.lerp(last, float(i) / float(steps)))
		"organic":
			for ring in 2:
				var count: int = int([12, 24][ring])
				var base: float = float([0.27, 0.60][ring])
				for i in count:
					var theta: float = TAU * (float(i) + 0.45 * float(ring)) / float(count)
					var warp: float = 0.06 * sin(theta * 3.0) + 0.04 * cos(theta * 5.0)
					candidates.append(Vector2.from_angle(theta) * radius * (base + warp))
		"linear":
			# Two building rows behind three parallel streets; keep houses clear of cross-roads.
			for i in 10:
				for row in [-1, 1]:
					candidates.append(Vector2((float(i) - 4.5) * radius * 0.16,
							float(row) * radius * 0.255))
		"triangular":
			# Dense staggered candidates compensate for the narrowing northern corner.
			# The caller uses its regular minimum spacing to select the actual buildings.
			for row in 14:
				var y: float = radius * (-0.70 + float(row) * 0.09)
				for column in range(-8, 9):
					var x: float = radius * (float(column) * 0.10 + (0.05 if row % 2 == 1 else 0.0))
					candidates.append(Vector2(x, y))
		"crescent":
			for ring in 3:
				var count: int = int([12, 20, 28][ring])
				var distance: float = radius * float([0.26, 0.51, 0.74][ring])
				for i in count:
					var theta: float = TAU * (float(i) + 0.5) / float(count)
					candidates.append(Vector2.from_angle(theta) * distance)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed ^ 0x62f05c77
	for i in range(candidates.size() - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var swap: Vector2 = candidates[i]
		candidates[i] = candidates[j]
		candidates[j] = swap
	var lots: Array[Dictionary] = []
	for local in candidates:
		var offset: Vector2 = local.rotated(rotation)
		if not contains(offset, layout, radius, rotation):
			continue
		var yaw: float = -atan2(offset.y, offset.x) + PI * 0.5
		if layout == "linear":
			yaw = rotation + (0.0 if local.y > 0.0 else PI)
		lots.append({"offset": offset, "yaw": yaw})
	return lots


## Polyline paths for terrain-painted, traversable streets. Every segment is at most 12 metres.
static func streets(layout: String, radius: float, rotation: float) -> Array:
	var result: Array = []
	match layout:
		"grid":
			for line in [-0.37, 0.0, 0.37]:
				var d: float = float(line) * radius
				result.append(_path([Vector2(d, -radius * 0.60), Vector2(d, radius * 0.60)], rotation))
				result.append(_path([Vector2(-radius * 0.60, d), Vector2(radius * 0.60, d)], rotation))
		"radial":
			for fraction in [0.43, 0.66]:
				result.append(_ring(radius * float(fraction), radius * float(fraction), rotation))
			for side in 4:
				var direction: Vector2 = Vector2.from_angle(TAU * float(side) / 4.0)
				result.append(_path([Vector2.ZERO, direction * radius * 0.80], rotation))
		"oval":
			result.append(_ring(radius * 0.53, radius * 0.30, rotation))
			for side in 4:
				var direction: Vector2 = Vector2.from_angle(TAU * float(side) / 4.0)
				var scale: float = radius * (0.78 if side % 2 == 0 else 0.46)
				result.append(_path([Vector2.ZERO, direction * scale], rotation))
		"hexagonal":
			var perimeter: Array[Vector2] = []
			for i in 7:
				perimeter.append(Vector2.from_angle(TAU * float(i) / 6.0) * radius * 0.51)
			result.append(_path(perimeter, rotation))
			for side in 6:
				var direction: Vector2 = Vector2.from_angle(TAU * (float(side) + 0.5) / 6.0)
				result.append(_path([Vector2.ZERO, direction * radius * 0.67], rotation))
		"organic":
			var contour: Array[Vector2] = []
			for i in 65:
				var theta: float = TAU * float(i) / 64.0
				var r: float = radius * (0.42 + 0.06 * sin(theta * 3.0) + 0.04 * cos(theta * 5.0))
				contour.append(Vector2.from_angle(theta) * r)
			result.append(_path(contour, rotation))
			for side in 5:
				var direction: Vector2 = Vector2.from_angle(TAU * float(side) / 5.0)
				result.append(_path([Vector2.ZERO, direction * radius * 0.48], rotation))
		"linear":
			for line in [-0.12, 0.0, 0.12]:
				var y: float = float(line) * radius
				result.append(_path([Vector2(-radius * 0.78, y), Vector2(radius * 0.78, y)], rotation))
			for x in [-0.45, 0.0, 0.45]:
				result.append(_path([Vector2(radius * float(x), -radius * 0.28),
						Vector2(radius * float(x), radius * 0.28)], rotation))
		"triangular":
			result.append(_path([Vector2(0.0, -radius * 0.75), Vector2(0.0, radius * 0.44)], rotation))
			for y_fraction in [-0.30, 0.18]:
				var y: float = radius * float(y_fraction)
				var half_width: float = radius * 0.70 * (float(y_fraction) + 0.82) / 1.32
				result.append(_path([Vector2(-half_width * 0.84, y), Vector2(half_width * 0.84, y)], rotation))
			result.append(_path([Vector2(0.0, -radius * 0.60), Vector2(radius * 0.50, radius * 0.38),
					Vector2(-radius * 0.50, radius * 0.38), Vector2(0.0, -radius * 0.60)], rotation))
		"crescent":
			result.append(_arc(radius * 0.56, radius * 0.56, 0.64, TAU - 0.64, rotation))
			result.append(_arc(radius * 0.23, radius * 0.23, 1.55, TAU - 1.55, rotation))
			result.append(_path([Vector2(-radius * 0.74, 0.0), Vector2(0.0, 0.0)], rotation))
			result.append(_path([Vector2(-radius * 0.30, -radius * 0.68),
					Vector2(-radius * 0.30, radius * 0.68)], rotation))
	return result


## A road endpoint chosen on the street network becomes an actual connection to the regional road.
static func entrance_offset(layout: String, radius: float, rotation: float, toward: Vector2) -> Vector2:
	if toward.length_squared() < 0.0001:
		return Vector2.ZERO
	var heading: Vector2 = toward.normalized()
	var best_score: float = -INF
	var best: Vector2 = Vector2.ZERO
	for street in streets(layout, radius, rotation):
		var path: PackedVector2Array = street
		if path.is_empty():
			continue
		for point in [path[0], path[path.size() - 1]]:
			var candidate: Vector2 = point
			var score: float = candidate.dot(heading) - absf(candidate.cross(heading)) * 0.15
			if score > best_score:
				best = candidate
				best_score = score
	return best


## Minimum distance to the polyline centreline, for obstacle and building placement.
static func street_distance(point: Vector2, paths: Array) -> float:
	var nearest: float = INF
	for street in paths:
		var path: PackedVector2Array = street
		for i in path.size() - 1:
			var a: Vector2 = path[i]
			var b: Vector2 = path[i + 1]
			var delta: Vector2 = b - a
			var length_sq: float = delta.length_squared()
			if length_sq < 0.00001:
				continue
			var t: float = clampf((point - a).dot(delta) / length_sq, 0.0, 1.0)
			nearest = minf(nearest, point.distance_to(a + delta * t))
	return nearest


static func _arc(rx: float, ry: float, from_angle: float, to_angle: float, rotation: float) -> PackedVector2Array:
	var points: Array[Vector2] = []
	for i in 49:
		var angle: float = lerpf(from_angle, to_angle, float(i) / 48.0)
		points.append(Vector2(cos(angle) * rx, sin(angle) * ry))
	return _path(points, rotation)


static func _ring(rx: float, ry: float, rotation: float) -> PackedVector2Array:
	var points: Array[Vector2] = []
	for i in 65:
		var theta: float = TAU * float(i) / 64.0
		points.append(Vector2(cos(theta) * rx, sin(theta) * ry))
	return _path(points, rotation)


static func _path(points: Array, rotation: float) -> PackedVector2Array:
	var result := PackedVector2Array()
	for i in points.size() - 1:
		var a: Vector2 = points[i]
		var b: Vector2 = points[i + 1]
		var steps: int = maxi(1, ceili(a.distance_to(b) / 10.0))
		for j in steps:
			result.append(a.lerp(b, float(j) / float(steps)).rotated(rotation))
	if not points.is_empty():
		result.append(points[points.size() - 1].rotated(rotation))
	return result
