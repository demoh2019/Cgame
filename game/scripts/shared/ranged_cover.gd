extends RefCounted
## Deterministic 2D ray/solid intersection for the server-owned combat model.
## Reuses the same procedurally generated and player-built collision blockers
## as movement. Does not require a scene tree or trust any client hit result.

## First solid surface along a ray in metres; INF means clear.
## The world broadphase includes trees, rocks, structures and built walls.
static func first_blocker_distance(world, origin: Vector2,
		direction: Vector2, reach: float) -> float:
	if not origin.is_finite() or not direction.is_finite() or not is_finite(reach) 			or reach <= 0.0 or direction.length_squared() < 0.000001:
		return 0.0 # Invalid input must not grant an unobstructed shot.
	var ray: Vector2 = direction.normalized()
	var middle: Vector2 = origin + ray * (reach * 0.5)
	# One broadphase query, not a full-world scan per hit target.
	var candidates: Array = world.blockers_near(middle.x, middle.y, reach * 0.5 + 1.0)
	var first: float = INF
	for entry in candidates:
		if not entry is Dictionary:
			continue
		var blocker: Dictionary = entry
		if not bool(blocker.get("blocks", true)):
			continue
		var x: float = float(blocker.get("x", NAN))
		var z: float = float(blocker.get("z", NAN))
		var radius: float = float(blocker.get("radius", 0.0))
		if not is_finite(x) or not is_finite(z) or not is_finite(radius) or radius <= 0.0:
			continue
		var relative: Vector2 = Vector2(x, z) - origin
		var along: float = relative.dot(ray)
		# Reject objects entirely behind the shooter or beyond maximum range.
		if along + radius <= 0.0 or along - radius >= reach:
			continue
		var across_squared: float = maxf(0.0, relative.length_squared() - along * along)
		if across_squared >= radius * radius:
			continue # Tangency is not a solid hit: no width passes through cover.
		var half_chord: float = sqrt(radius * radius - across_squared)
		var entry_distance: float = maxf(0.0, along - half_chord)
		if along + half_chord > 0.0 and entry_distance < first:
			first = entry_distance
	return first
