extends RefCounted
## Session-based PvP outpost control, a precursor to persistent clan sieges.
## All presence, group ownership and stamina support are derived from the
## authoritative world simulation. Clients can observe but never set ownership.

const Defs = preload("res://scripts/shared/defs.gd")
const ZoneRisk = preload("res://scripts/shared/zone_risk.gd")
const OutpostFortification = preload("res://scripts/shared/outpost_fortification.gd")
const OutpostBreach = preload("res://scripts/shared/outpost_breach.gd")
const OutpostSupplies = preload("res://scripts/shared/outpost_supplies.gd")
const GuildTerritory = preload("res://scripts/shared/guild_territory.gd")

const MAX_SITES := 3
const CAPTURE_RADIUS := 12.0
const RALLY_RADIUS := 18.0
const HARVEST_RADIUS := 100.0 # Economic benefit is local to a captured outpost.
const FIELD_BENCH_RADIUS := 6.5 # Owner-only portable bench at the central flag.
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
				"progress": 0.0, "contested": false, "fortification": 0,
				"breach_ready_at": 0.0,
				"supplies_left": 0, "supply_epoch": 0,
				"supply_claims": {},
			})
			break


func public_state(now: float, players: Dictionary = {}, parties = null) -> Array:
	var result: Array = []
	for site in sites:
		var clan: Dictionary = GuildTerritory.owner_banner(site, players, parties)
		result.append({
			"id": int(site["id"]), "x": float(site["x"]), "z": float(site["z"]),
			"owner": int(site["owner"]), "challenger": int(site["challenger"]),
			"guild": clan,
			"progress": float(site["progress"]), "contested": bool(site["contested"]),
			"fortification": int(site["fortification"]),
			"capture_target": capture_target(site),
			"breach_cooldown": maxf(0.0, float(site.get("breach_ready_at", 0.0)) - now),
			"expires_in": maxf(0.0, float(site["until"]) - now),
			"supplies_left": int(site.get("supplies_left", 0)),
		})
	return result


## A fortified owner's flag requires more uninterrupted enemy presence.
## Neutral and newly captured sites always use the base capture duration.
func capture_target(site: Dictionary) -> float:
	return OutpostFortification.capture_duration(CAPTURE_SECONDS, int(site.get("fortification", 0)))


func site_by_id(site_id: int) -> Dictionary:
	for site in sites:
		if int(site["id"]) == site_id:
			return site
	return {}


func contested_by_rivals(site: Dictionary, group_id: int, players: Dictionary, parties) -> bool:
	for other_group in _occupied_groups(site, players, parties):
		if int(other_group) != group_id:
			return true
	return false


func _occupied_groups(site: Dictionary, players: Dictionary, parties) -> Dictionary:
	var active: Dictionary = {}
	var point := Vector2(float(site["x"]), float(site["z"]))
	for player in players.values():
		if not player.survival.alive or not player.position.is_finite():
			continue
		if point.distance_squared_to(Vector2(player.position.x, player.position.z)) > CAPTURE_RADIUS * CAPTURE_RADIUS:
			continue
		var group_id: int = GuildTerritory.occupancy_side(site, player, players, parties)
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
			site["fortification"] = 0
			site["supply_claims"] = {}
			site["breach_ready_at"] = 0.0
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
		site["progress"] = minf(capture_target(site), float(site["progress"]) + step)
		if float(site["progress"]) >= capture_target(site):
			site["owner"] = group_id
			site["until"] = now + HOLD_SECONDS
			OutpostSupplies.initialize_capture(site)
			site["fortification"] = 0 # Previous defenders lose their walls.
			site["breach_ready_at"] = 0.0 # Siege timer belongs to former owner.
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


func has_rally_bonus(peer_id: int, position: Vector3, parties, now: float,
		players: Dictionary = {}) -> bool:
	if not position.is_finite():
		return false
	var group_id: int = parties.group_of(peer_id)
	var player = players.get(peer_id)
	for site in sites:
		var owner: int = int(site["owner"])
		if owner <= 0 or not parties.groups.has(owner) or now >= float(site["until"]):
			continue
		var my_party: bool = group_id > 0 and group_id == owner
		var my_clan: bool = GuildTerritory.same_owner_guild(site, player, players, parties)
		if not my_party and not my_clan:
			continue
		if Vector2(position.x, position.z).distance_squared_to(
				Vector2(site["x"], site["z"])) <= RALLY_RADIUS * RALLY_RADIUS:
			return true
	return false

## Holding a dangerous-zone outpost rewards nearby harvesters, not remote farmers.
## All ownership, Nakama clan membership and live contesting sides are resolved
## on the server at harvest completion, so losing a flag cancels the benefit.
## The reward is exactly one additional raw crafting resource per node.
func harvest_bonus(peer_id: int, node: Dictionary, players: Dictionary,
		parties, now: float, world) -> int:
	if not is_finite(now) or not ["tree", "rock", "ore", "bush"].has(
			str(node.get("kind", ""))):
		return 0
	var x: float = float(node.get("x", NAN))
	var z: float = float(node.get("z", NAN))
	if not is_finite(x) or not is_finite(z) or not ZoneRisk.full_loot(world.zone_at(x, z)):
		return 0
	var player = players.get(peer_id)
	if player == null or not player.survival.alive or not player.position.is_finite():
		return 0
	var node_position := Vector2(x, z)
	if Vector2(player.position.x, player.position.z).distance_to(
			node_position) > Defs.REACH + 0.8:
		return 0
	var group_id: int = parties.group_of(peer_id)
	for site in sites:
		var owner: int = int(site["owner"])
		if owner <= 0 or not parties.groups.has(owner) or now >= float(site["until"]):
			continue
		if node_position.distance_squared_to(Vector2(float(site["x"]), float(site["z"]))) > \
				HARVEST_RADIUS * HARVEST_RADIUS:
			continue
		if group_id != owner and not GuildTerritory.same_owner_guild(
				site, player, players, parties):
			continue
		# Re-evaluate occupants immediately; cached contested flags may be stale.
		var blocked := false
		for presence_group in _occupied_groups(site, players, parties):
			if int(presence_group) != owner:
				blocked = true
				break
		if not blocked:
			return 1
	return 0

## Captured outposts act as local workbenches for their occupying party or a
## fully verified owning guild. The authoritative server checks current world
## position, expiry and *live* rival occupancy immediately before crafting.
## An old client snapshot or stale contested flag never opens a station.
func has_field_workbench(peer_id: int, players: Dictionary, parties, now: float) -> bool:
	if not is_finite(now):
		return false
	var player = players.get(peer_id)
	if player == null or not player.survival.alive or not player.position.is_finite():
		return false
	var here := Vector2(player.position.x, player.position.z)
	var group_id: int = parties.group_of(peer_id)
	for site in sites:
		var owner: int = int(site["owner"])
		if owner <= 0 or not parties.groups.has(owner) or now >= float(site["until"]):
			continue
		if here.distance_squared_to(Vector2(float(site["x"]), float(site["z"]))) > \
				FIELD_BENCH_RADIUS * FIELD_BENCH_RADIUS:
			continue
		if group_id != owner and not GuildTerritory.same_owner_guild(site, player, players, parties):
			continue
		var contested_now := false
		for occupants_id in _occupied_groups(site, players, parties):
			if int(occupants_id) != owner:
				contested_now = true
				break
		if not contested_now:
			return true
	return false
