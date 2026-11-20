extends RefCounted
## Single-use geological survey for the tiered gathering / crafting economy.
## The server alone selects a real world node. Clients cannot request a
## particular node ID, item quantity, reward, radius, or location.

const WorldGen = preload("res://scripts/shared/world_gen.gd")

const ITEM_ID := "prospecting_chart"
const SCAN_RADIUS := 180.0
const CHUNK_RADIUS := 3
const MIN_TIER := 2
const MARK_SECONDS := 80.0


## Scan at most 49 deterministic world chunks. Highest-tier ore is preferred,
## then high-tier stone, then nearest, then stable ID. All resources remain
## in the world and must still be gathered with real skill and tools.
static func nearest(world, at: Vector3, depleted: Dictionary) -> Dictionary:
	if world == null or not at.is_finite() or world.is_safe(at.x, at.z):
		return {}
	var origin := Vector2(at.x, at.z)
	var cell: Vector2i = WorldGen.cell_of(origin.x, origin.y)
	var best: Dictionary = {}
	var best_tier: int = -1
	var best_ore: bool = false
	var best_distance: float = SCAN_RADIUS * SCAN_RADIUS
	var best_id: int = 9223372036854775807
	for dx in range(-CHUNK_RADIUS, CHUNK_RADIUS + 1):
		for dz in range(-CHUNK_RADIUS, CHUNK_RADIUS + 1):
			var chunk: Dictionary = world.chunk(cell + Vector2i(dx, dz))
			for node in chunk["nodes"]:
				var id: int = int(node["id"])
				var tier: int = int(node["tier"])
				var kind: String = str(node["kind"])
				if tier < MIN_TIER or depleted.has(id) or kind not in ["ore", "rock"]:
					continue
				var x: float = float(node["x"])
				var z: float = float(node["z"])
				if not (is_finite(x) and is_finite(z)):
					continue
				var distance: float = origin.distance_squared_to(Vector2(x, z))
				if distance > SCAN_RADIUS * SCAN_RADIUS:
					continue
				var ore: bool = kind == "ore"
				if tier > best_tier or (tier == best_tier and (
						(ore and not best_ore) or (ore == best_ore and (
						distance < best_distance or (
						is_equal_approx(distance, best_distance) and id < best_id))))):
					best_tier = tier
					best_ore = ore
					best_distance = distance
					best_id = id
					best = {"id": id, "kind": kind, "tier": tier,
						"x": x, "z": z}
	return best


static func active(mark: Dictionary, now: float, depleted: Dictionary) -> bool:
	if mark.is_empty() or not is_finite(now):
		return false
	var deadline: float = float(mark.get("until", -1.0))
	return is_finite(deadline) and deadline > now and (
		int(mark.get("id", -1)) > 0 and not depleted.has(int(mark.get("id", -1))))


## Client sees only a short-lived destination, material class and tier.
## Never replicate internal node IDs or absolute server deadlines.
static func public_mark(mark: Dictionary, now: float, depleted: Dictionary) -> Dictionary:
	if not active(mark, now, depleted):
		return {}
	var x: float = float(mark.get("x", NAN))
	var z: float = float(mark.get("z", NAN))
	var kind: String = str(mark.get("kind", ""))
	var tier: int = int(mark.get("tier", 0))
	if not (is_finite(x) and is_finite(z)) or kind not in ["ore", "rock"] or (
			tier < MIN_TIER or tier > 4):
		return {}
	return {"x": x, "z": z, "kind": kind, "tier": tier,
		"remaining": clampf(float(mark["until"]) - now, 0.0, MARK_SECONDS)}
