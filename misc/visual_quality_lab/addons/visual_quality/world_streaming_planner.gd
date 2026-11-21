extends RefCounted
class_name WorldStreamingPlanner3D
## Pure, deterministic streaming planner. Only the actual streamer owns nodes.
## Required cells are always scheduled before speculative look-ahead cells.


static func predict_cell(local_position: Vector3, local_velocity: Vector3,
		width: float, horizon_seconds: float, max_lead_cells: int) -> Vector2i:
	var origin: Vector2i = cell_for_position(local_position, width)
	if width <= 0.0 or not is_finite(width) or not is_finite(horizon_seconds):
		return origin
	if not is_finite(local_velocity.x) or not is_finite(local_velocity.z):
		return origin
	var prediction: Vector3 = local_position + local_velocity * maxf(horizon_seconds, 0.0)
	var desired: Vector2i = cell_for_position(prediction, width)
	var limit: int = maxi(max_lead_cells, 0)
	return origin + Vector2i(clampi(desired.x - origin.x, -limit, limit),
		clampi(desired.y - origin.y, -limit, limit))


static func cell_for_position(local_position: Vector3, width: float) -> Vector2i:
	if width <= 0.0 or not is_finite(width):
		return Vector2i.ZERO
	return Vector2i(floori(local_position.x / width), floori(local_position.z / width))


static func in_radius(coord: Vector2i, center: Vector2i, radius: int) -> bool:
	return radius >= 0 and maxi(absi(coord.x - center.x), absi(coord.y - center.y)) <= radius


static func build_load_queue(registered: Dictionary, active: Dictionary,
		center: Vector2i, predicted: Vector2i, required_radius: int,
		keep_radius: int, prefetch_radius: int, max_prefetch: int) -> Array[Vector2i]:
	var required: Array[Vector2i] = []
	var speculative: Array[Vector2i] = []
	var safe_keep: int = maxi(keep_radius, required_radius)
	for key in registered.keys():
		if typeof(key) != TYPE_VECTOR2I or active.has(key):
			continue
		var coord: Vector2i = key
		if in_radius(coord, center, required_radius):
			required.append(coord)
		elif predicted != center and max_prefetch > 0 and prefetch_radius >= 0 \
				and in_radius(coord, predicted, prefetch_radius) \
				and in_radius(coord, center, safe_keep):
			speculative.append(coord)
	# Avoid starvation: the closest currently needed cells are always first.
	# Among equal-distance cells, prioritize the player's travel direction.
	required.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		var ad: int = (a - center).length_squared()
		var bd: int = (b - center).length_squared()
		if ad != bd:
			return ad < bd
		var ap: int = (a - predicted).length_squared()
		var bp: int = (b - predicted).length_squared()
		if ap != bp:
			return ap < bp
		return less_coord(a, b)
	)
	speculative.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		var ad: int = (a - predicted).length_squared()
		var bd: int = (b - predicted).length_squared()
		if ad != bd:
			return ad < bd
		return less_coord(a, b)
	)
	for i in range(mini(maxi(max_prefetch, 0), speculative.size())):
		required.append(speculative[i])
	return required


static func less_coord(a: Vector2i, b: Vector2i) -> bool:
	if a.x != b.x:
		return a.x < b.x
	return a.y < b.y


static func is_speculative(coord: Vector2i, center: Vector2i, required_radius: int) -> bool:
	return not in_radius(coord, center, required_radius)
