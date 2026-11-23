extends RefCounted
## A north-up, purely visual compass for the user's own caravan and party
## rally. Never selects or accepts targets from other survivors' snapshots.

const LABELS := ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]


static func target(data: Variant, x_key: String, z_key: String) -> Vector2:
	if not (data is Dictionary):
		return Vector2(INF, INF)
	var record: Dictionary = data
	if not record.has(x_key) or not record.has(z_key):
		return Vector2(INF, INF)
	var x: Variant = record[x_key]
	var z: Variant = record[z_key]
	if not (x is float or x is int) or not (z is float or z is int):
		return Vector2(INF, INF)
	var point := Vector2(float(x), float(z))
	return point if point.is_finite() else Vector2(INF, INF)


static func distance_meters(origin: Vector2, destination: Vector2) -> int:
	if not origin.is_finite() or not destination.is_finite():
		return -1
	var distance: float = origin.distance_to(destination)
	# Guard overflow before converting float to int for the UI compass.
	if not is_finite(distance) or distance > 2147483647.0:
		return -1
	return maxi(0, roundi(distance))


static func compass(origin: Vector2, destination: Vector2) -> String:
	if not origin.is_finite() or not destination.is_finite():
		return ""
	var delta: Vector2 = destination - origin
	var distance_squared: float = delta.length_squared()
	if not delta.is_finite() or not is_finite(distance_squared):
		return ""
	if distance_squared <= 4.0:
		return "ARRIVED"
	# World coordinates use -Z as north and +X as east.
	var angle: float = atan2(delta.x, -delta.y)
	return str(LABELS[wrapi(roundi(angle / (PI / 4.0)), 0, 8)])


## Convert a local pointer in the full-island map into a private waypoint.
## Invalid/off-island clicks are rejected instead of producing a fake route.
static func valid_destination(destination: Vector2, world_radius: float) -> bool:
	if not destination.is_finite() or not is_finite(world_radius) or world_radius <= 0.0:
		return false
	var distance_squared: float = destination.length_squared()
	var radius_squared: float = world_radius * world_radius
	return is_finite(distance_squared) and is_finite(radius_squared) and \
		distance_squared <= radius_squared


static func world_from_map(pointer: Vector2, bounds: Rect2, span: float,
		world_radius: float) -> Vector2:
	if not pointer.is_finite() or not bounds.position.is_finite() or \
			not bounds.size.is_finite() or bounds.size.x <= 0.0 or bounds.size.y <= 0.0 or \
			not is_finite(span) or span <= 0.0 or \
			not is_finite(world_radius) or world_radius <= 0.0 or \
			not bounds.has_point(pointer):
		return Vector2(INF, INF)
	var destination: Vector2 = ((pointer - bounds.position) / bounds.size - Vector2(0.5, 0.5)) * span
	return destination if valid_destination(destination, world_radius) else Vector2(INF, INF)


## Projection returns one point inside a radar if the marker is near;
## otherwise returns a clipped edge pointer in the direction of the marker.
## No geometry is produced for missing/malformed private waypoint data.
static func project(origin: Vector2, destination: Vector2, map_size: Vector2,
		world_radius: float = 72.0, inset: float = 0.44) -> Dictionary:
	if not origin.is_finite() or not destination.is_finite() or \
			not map_size.is_finite() or map_size.x <= 0.0 or map_size.y <= 0.0 or \
			not is_finite(world_radius) or world_radius <= 0.0 or \
			not is_finite(inset) or inset <= 0.0 or inset > 0.48:
		return {}
	var vector: Vector2 = destination - origin
	var distance: float = vector.length()
	if not is_finite(distance):
		return {}
	var map_center: Vector2 = map_size * 0.5
	var pixel_radius: float = minf(map_size.x, map_size.y) * inset
	var inside: bool = distance <= world_radius
	var marker: Vector2
	if inside:
		marker = map_center + vector * pixel_radius / world_radius
	else:
		marker = map_center + vector / distance * maxf(0.0, pixel_radius - 2.0)
	return {"point": marker, "inside": inside, "distance": distance}
