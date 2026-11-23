extends RefCounted
## Consumable wilderness cartography. The client can request a survey but
## cannot supply a crate ID, location, search radius or any loot values.

const WorldGen = preload("res://scripts/shared/world_gen.gd")
const Defs = preload("res://scripts/shared/defs.gd")

const ITEM_ID := "ruin_survey_chart"
const SCAN_RADIUS := 190.0
const MARK_SECONDS := 75.0
const MIN_ZONE := 2
const CELL_RADIUS := 3


## Lower bound on the XZ distance to any point in a chunk. A chunk outside
## the current search radius cannot contain a closer crate, so do not
## generate its terrain, structures or contents just to reject it.
static func cell_min_distance_squared(origin: Vector2, cell: Vector2i) -> float:
	if not origin.is_finite():
		return INF
	var start: Vector2 = WorldGen.cell_origin(cell)
	var nearest := Vector2(
		clampf(origin.x, start.x, start.x + Defs.CHUNK_SIZE),
		clampf(origin.y, start.y, start.y + Defs.CHUNK_SIZE))
	return origin.distance_squared_to(nearest)


## Bounded 7x7 world-chunk scan, selecting the nearest live red/black ruin
## crate; stable ID tiebreak makes the result deterministic across clients.
static func nearest(world, at: Vector3, opened: Dictionary) -> Dictionary:
	if not at.is_finite() or world.is_safe(at.x, at.z):
		return {}
	var origin := Vector2(at.x, at.z)
	var cell: Vector2i = WorldGen.cell_of(origin.x, origin.y)
	var best_id: int = 9223372036854775807
	var best_distance: float = SCAN_RADIUS * SCAN_RADIUS
	var best: Dictionary = {}
	for dx in range(-CELL_RADIUS, CELL_RADIUS + 1):
		for dz in range(-CELL_RADIUS, CELL_RADIUS + 1):
			var chunk_cell: Vector2i = cell + Vector2i(dx, dz)
			# Re-evaluate against the nearest found candidate to prune even
			# more chunks. Strict > preserves equidistant stable-ID ties.
			if cell_min_distance_squared(origin, chunk_cell) > best_distance:
				continue
			var chunk: Dictionary = world.chunk(chunk_cell)
			if int(chunk.get("zone", -1)) < MIN_ZONE:
				continue
			for crate in chunk["crates"]:
				var id: int = int(crate["id"])
				if opened.has(id):
					continue
				var x: float = float(crate["x"])
				var z: float = float(crate["z"])
				if not (is_finite(x) and is_finite(z)):
					continue
				var distance: float = origin.distance_squared_to(Vector2(x, z))
				if distance <= best_distance and (
						best.is_empty() or distance < best_distance or id < best_id):
					best_id = id
					best_distance = distance
					best = {"id": id, "x": x, "z": z,
						"zone": int(chunk["zone"])}
	return best


static func active(mark: Dictionary, now: float, opened: Dictionary) -> bool:
	if mark.is_empty() or not is_finite(now):
		return false
	var until: float = float(mark.get("until", -1.0))
	return is_finite(until) and until > now and not opened.has(int(mark.get("id", -1)))


## Only the owner receives a private waypoint. Absolute server deadline and
## internal crate ID are never exposed, and stale marks are suppressed.
static func public_mark(mark: Dictionary, now: float, opened: Dictionary) -> Dictionary:
	if not active(mark, now, opened):
		return {}
	return {"x": float(mark["x"]), "z": float(mark["z"]),
		"zone": int(mark["zone"]),
		"remaining": maxf(0.0, float(mark["until"]) - now)}
