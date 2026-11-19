extends RefCounted
## Session-based PvP outpost control, a precursor to persistent clan sieges.
## All presence, group ownership and stamina support are derived from the
## authoritative world simulation. Clients can observe but never set ownership.

const Defs = preload("res://scripts/shared/defs.gd")
const ZoneRisk = preload("res://scripts/shared/zone_risk.gd")
const OutpostSupplies = preload("res://scripts/shared/outpost_supplies.gd")

const MAX_SITES := 3
const CAPTURE_RADIUS := 12.0
const RALLY_RADIUS := 18.0
const CAPTURE_SECONDS := 30.0
const HOLD_SECONDS := 900.0
const MIN_CAPTURERS := 2
const RALLY_STAMINA_PER_SECOND := 2.0

var sites: Array[Dictionary] = []


func _init(world) -> void:
	for index in range(MAX_SITES):
		var ring: float = 760.0 if index == 0 else 1175.0
		# Search a seeded angular sequence for walkable land in a full-loot zone.
		# IDs stay stable even if a seed has no suitable position for one site.
		for attempt in range(72):
			var degrees: int = (world.world_seed % 359 + index * 127 + attempt * 37) % 360
			var distance: float = ring + float((attempt % 5) - 2) * 14.0
			var position := Vector2.from_angle(deg_to_rad(float(degrees))) * distance
			if not ZoneRisk.allows_pvp(world.zone_at(position.x, position.y)):
				continue
			if world.is_water(position.x, position.y) or world.normal_at(position.x, position.y).y < 0.7:
				continue
			var spaced := true
			for prior in sites:
				if position.distance_to(Vector2(prior["x"], prior["z"])) < 110.0:
					spaced = false
					break
			if not spaced:
				continue
			sites.append({
				"id": index + 1, "x": position.x, "z": position.y,
				"owner": 0, "until": 0.0, "challenger": 0,
				"progress": 0.0, "contested": false,
				"supplies_left": 0, "supply_epoch": 0,
				"supply_claims": {},
			})
			break


func public_state(now: float) -> Array:
	var result: Array = []
	for site in sites:
		result.append({
			"id": int(site["id"]), "x": float(site["x"]), "z": float(site["z"]),
			"owner": int(site["owner"]), "challenger": int(site["challenger"]),
			"progress": float(site["progress"]), "contested": bool(site["contested"]),
			"expires_in": maxf(0.0, float(site["until"]) - now),
			"supplies_left": int(site.get("supplies_left", 0)),
		})
	return result


func _occupied_groups(site: Dictionary, players: Dictionary, parties) -> Dictionary:
	var active: Dictionary = {}
	var point := Vector2(float(site["x"]), float(site["z"]))
	for player in players.values():
		if not player.survival.alive or not player.position.is_finite():
			continue
		if point.distance_squared_to(Vector2(player.position.x, player.position.z)) > CAPTURE_RADIUS * CAPTURE_RADIUS:
			continue
		var group_id: int = parties.group_of(player.id)
		active[group_id] = int(active.get(group_id, 0)) + 1
	return active


func tick(delta: float, now: float, players: Dictionary, parties) -> Array:
	var changed: Array = []
	if not is_finite(delta) or delta <= 0.0 or not is_finite(now):
		return changed
	# Clamp unusually large frame gaps so a single stall cannot instantly cap a site.
	var step: float = minf(delta, 0.25)
	for site in sites:
		var owner: int = int(site["owner"])
		if owner != 0 and (not parties.groups.has(owner) or now >= float(site["until"])):
			site["owner"] = 0
			site["until"] = 0.0
			site["supplies_left"] = 0
			site["supply_claims"] = {}
			changed.append({"type": "outpost_lost", "id": site["id"], "x": site["x"], "z": site["z"]})
		var occupants: Dictionary = _occupied_groups(site, players, parties)
		site["contested"] = occupants.size() > 1
		var group_id := 0
		if occupants.size() == 1:
			var candidate: int = int(occupants.keys()[0])
			if candidate > 0 and parties.groups.has(candidate) \
					and int(occupants[candidate]) >= MIN_CAPTURERS:
				group_id = candidate
		if group_id == 0 or group_id == int(site["owner"]):
			site["progress"] = maxf(0.0, float(site["progress"]) - step)
			if float(site["progress"]) == 0.0:
				site["challenger"] = 0
			continue
		if int(site["challenger"]) != group_id:
			site["challenger"] = group_id
			site["progress"] = 0.0
		site["progress"] = minf(CAPTURE_SECONDS, float(site["progress"]) + step)
		if float(site["progress"]) >= CAPTURE_SECONDS:
			site["owner"] = group_id
			site["until"] = now + HOLD_SECONDS
			OutpostSupplies.initialize_capture(site)
			site["challenger"] = 0
			site["progress"] = 0.0
			changed.append({
				"type": "outpost_taken", "id": site["id"],
				"x": site["x"], "z": site["z"], "owner": group_id,
			})
	return changed


## Server-only lookup that rechecks live occupancy rather than stale snapshot
## contested state. A hostile player physically present blocks supply claims.
func claim_supplies(site_id: int, player, players: Dictionary, parties,
		world, now: float) -> Dictionary:
	var group_id: int = parties.group_of(player.id)
	for site in sites:
		if int(site["id"]) != site_id:
			continue
		var owner: int = int(site["owner"])
		if owner == 0 or not parties.groups.has(owner):
			return {"ok": false, "reason": "not_owner"}
		# Recompute live presence so a challenger cannot loot while an enemy
		# is standing on the flag between two regular territory ticks.
		var occupants: Dictionary = _occupied_groups(site, players, parties)
		var contested_now: bool = occupants.size() > 1
		return OutpostSupplies.claim(site, player, group_id,
			world.zone_at(float(site["x"]), float(site["z"])), now, contested_now)
	return {"ok": false, "reason": "no_such_site"}


func has_rally_bonus(peer_id: int, position: Vector3, parties, now: float) -> bool:
	if not position.is_finite():
		return false
	var group_id: int = parties.group_of(peer_id)
	if group_id == 0 or not parties.groups.has(group_id):
		return false
	for site in sites:
		if int(site["owner"]) == group_id and now < float(site["until"]) and \
				Vector2(position.x, position.z).distance_squared_to(Vector2(site["x"], site["z"])) <= RALLY_RADIUS * RALLY_RADIUS:
			return true
	return false
