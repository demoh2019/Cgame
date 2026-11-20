extends RefCounted
## Deterministic 2D ray/solid intersection for authoritative ranged combat.
## Uses the world's movement blocker broadphase, including constructed walls.

## The server needs both first-hit distance and collider identity. Static
## scenery may have an id too; the game server separately checks barricades.
## Empty means the ray is clear. Invalid rays fail closed at distance zero.
static func first_blocker(world, origin: Vector2,
		direction: Vector2, reach: float, min_radius: float = 0.0) -> Dictionary:
	if not origin.is_finite() or not direction.is_finite() or not is_finite(reach) \
			or reach <= 0.0 or direction.length_squared() < 0.000001:
		return {"distance": 0.0, "id": -1}
	var ray: Vector2 = direction.normalized()
	var middle: Vector2 = origin + ray * (reach * 0.5)
	# Query only blockers overlapping the attack corridor.
	var candidates: Array = world.blockers_near(middle.x, middle.y, reach * 0.5 + 1.0)
	var first: float = INF
	var result: Dictionary = {}
	for entry in candidates:
		if not (entry is Dictionary):
			continue
		var blocker: Dictionary = entry
		if not bool(blocker.get("blocks", true)):
			continue
		var x: float = float(blocker.get("x", NAN))
		var z: float = float(blocker.get("z", NAN))
		var radius: float = float(blocker.get("radius", 0.0))
		if not is_finite(x) or not is_finite(z) or not is_finite(radius) \
				or radius <= 0.0 or radius < min_radius:
			continue
		var relative: Vector2 = Vector2(x, z) - origin
		var along: float = relative.dot(ray)
		if along + radius <= 0.0 or along - radius >= reach:
			continue
		var across_squared: float = maxf(0.0, relative.length_squared() - along * along)
		if across_squared >= radius * radius:
			continue # Tangency does not count as an impact.
		var half_chord: float = sqrt(radius * radius - across_squared)
		var entry_distance: float = maxf(0.0, along - half_chord)
		if along + half_chord > 0.0 and entry_distance < first:
			first = entry_distance
			result = {"distance": entry_distance, "id": int(blocker.get("id", -1))}
	return result


## Original cover API stays available for every existing caller.
static func first_blocker_distance(world, origin: Vector2,
		direction: Vector2, reach: float, min_radius: float = 0.0) -> float:
	return float(first_blocker(world, origin, direction, reach, min_radius).get("distance", INF))
