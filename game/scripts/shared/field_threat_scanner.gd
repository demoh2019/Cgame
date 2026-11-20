extends RefCounted
## A paid, single-use recon sweep for high-risk PvE expeditions.
## The server selects living targets. Players never submit coordinates or IDs.
## Results and the follow-up moving pin belong only to the owner snapshot.

const ITEM_ID := "field_threat_scanner"
const SCAN_RADIUS := 145.0
const TRACK_RADIUS := 170.0
const MARK_SECONDS := 50.0


## Raid encounters take precedence over elites; inside a category choose
## the nearest survivor-visible threat, breaking ties by stable server ID.
static func nearest(at: Vector3, zombies: Dictionary) -> Dictionary:
	if not at.is_finite():
		return {}
	var origin := Vector2(at.x, at.z)
	var best: Dictionary = {}
	var best_priority: int = 2
	var best_distance: float = SCAN_RADIUS * SCAN_RADIUS
	var best_id: int = 9223372036854775807
	for infected in zombies.values():
		if infected == null or not infected.is_alive():
			continue
		if not infected.raid_boss and not infected.elite:
			continue
		var position: Vector3 = infected.position
		if not position.is_finite():
			continue
		var distance: float = origin.distance_squared_to(Vector2(position.x, position.z))
		if distance > SCAN_RADIUS * SCAN_RADIUS:
			continue
		var priority: int = 0 if infected.raid_boss else 1
		if priority < best_priority or (priority == best_priority and (
				distance < best_distance or (is_equal_approx(distance, best_distance) and
				infected.id < best_id))):
			best_priority = priority
			best_distance = distance
			best_id = infected.id
			best = {"target": infected.id,
				"kind": "raid" if infected.raid_boss else "elite"}
	return best


## The mark can follow its target briefly but cannot follow an infected
## across the world, survive its death or outlive the original paid scan.
static func public_mark(state: Dictionary, zombies: Dictionary,
		at: Vector3, now: float) -> Dictionary:
	if state.is_empty() or not at.is_finite() or not is_finite(now):
		return {}
	var deadline: float = float(state.get("expires", -1.0))
	if not is_finite(deadline) or now >= deadline:
		return {}
	var target_id: int = int(state.get("target", -1))
	if target_id <= 0 or not zombies.has(target_id):
		return {}
	var infected = zombies[target_id]
	if infected == null or not infected.is_alive() or (
			not infected.raid_boss and not infected.elite):
		return {}
	var position: Vector3 = infected.position
	if not position.is_finite() or Vector2(at.x, at.z).distance_squared_to(
			Vector2(position.x, position.z)) > TRACK_RADIUS * TRACK_RADIUS:
		return {}
	return {"x": position.x, "z": position.z,
		"kind": "raid" if infected.raid_boss else "elite",
		"remaining": clampf(deadline - now, 0.0, MARK_SECONDS)}
