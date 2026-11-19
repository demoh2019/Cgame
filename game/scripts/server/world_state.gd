extends RefCounted
## Versioned world snapshot validator. Pure except for GameServer.restore_world_state.
## Structure data is stored separately from account character data and never
## accepted from arbitrary client payloads.

const Structures = preload("res://scripts/shared/structures.gd")
const VERSION := 1
const MAX_COORD := 200000.0
const FIRST_STRUCTURE_ID := 5_000_000_000


static func owner_key_for(player) -> String:
	# An authenticated Nakama account is the durable identity. Offline mode
	# has no authentication; peer IDs are suitable only for local/dev worlds.
	if not player.user_id.is_empty():
		return "account:" + player.user_id
	return "local:%d" % player.id


static func export_state(server) -> Dictionary:
	var entries: Array = []
	for structure in server.barricades.values():
		entries.append({
			"id": int(structure["id"]),
			"x": float(structure["x"]),
			"z": float(structure["z"]),
			"hp": float(structure["hp"]),
			"owner_key": str(structure.get("owner_key", "")),
		})
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["id"]) < int(b["id"]))
	return {"version": VERSION, "seed": int(server.world.world_seed), "barricades": entries}


static func _number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))


## JSON may decode integer tokens as float. Accept only exactly integral finite
## numbers representable without precision loss (IDs remain well below 2^53).
static func _whole_number(value: Variant) -> bool:
	return _number(value) and absf(float(value)) <= 9007199254740991.0 and floor(float(value)) == float(value)


static func _valid_owner_key(value: Variant) -> bool:
	if not value is String or value.is_empty() or value.length() > 128:
		return false
	if value.contains("\n") or value.contains("\r") or value.contains("\t"):
		return false
	if value.begins_with("account:"):
		return value.length() > 8
	if value.begins_with("local:"):
		var number: String = value.substr(6)
		return number.is_valid_int() and int(number) > 0
	return false


## Completely validate in a staging array before changing the authoritative
## world. Reject malformed snapshots; never silently reset valuable bases.
static func parse_state(world, data: Variant) -> Dictionary:
	if not data is Dictionary:
		return {"ok": false, "reason": "bad_document"}
	if not _whole_number(data.get("version")) or int(data["version"]) != VERSION:
		return {"ok": false, "reason": "wrong_version"}
	if not _whole_number(data.get("seed")) or int(data["seed"]) != world.world_seed:
		return {"ok": false, "reason": "wrong_seed"}
	var records: Variant = data.get("barricades")
	if not records is Array or records.size() > Structures.MAX_GLOBAL:
		return {"ok": false, "reason": "bad_structure_list"}
	var staged: Array = []
	var seen: Dictionary = {}
	var owned: Dictionary = {}
	var max_id: int = FIRST_STRUCTURE_ID
	for record in records:
		if not record is Dictionary:
			return {"ok": false, "reason": "bad_entry"}
		if not _whole_number(record.get("id")) or int(record["id"]) <= FIRST_STRUCTURE_ID:
			return {"ok": false, "reason": "bad_id"}
		var id: int = record["id"]
		if seen.has(id):
			return {"ok": false, "reason": "duplicate_id"}
		seen[id] = true
		for key in ["x", "z", "hp"]:
			if not _number(record.get(key)):
				return {"ok": false, "reason": "bad_number"}
		var x: float = float(record["x"])
		var z: float = float(record["z"])
		var hp: float = float(record["hp"])
		var location := Vector2(x, z)
		if absf(x) > MAX_COORD or absf(z) > MAX_COORD or location.length() < Structures.MIN_HUB_DISTANCE:
			return {"ok": false, "reason": "bad_position"}
		if hp <= 0.0 or hp > Structures.MAX_HEALTH:
			return {"ok": false, "reason": "bad_health"}
		var identity: Variant = record.get("owner_key")
		if not _valid_owner_key(identity):
			return {"ok": false, "reason": "bad_owner"}
		owned[identity] = int(owned.get(identity, 0)) + 1
		if owned[identity] > Structures.MAX_PER_OWNER:
			return {"ok": false, "reason": "owner_limit"}
		if world.is_water(x, z) or world.normal_at(x, z).y < Structures.MIN_SLOPE_NORMAL_Y:
			return {"ok": false, "reason": "bad_terrain"}
		for blocker in world.blockers_near(x, z, Structures.RADIUS + 1.0):
			var obstacle := Vector2(float(blocker["x"]), float(blocker["z"]))
			if location.distance_to(obstacle) < Structures.RADIUS + float(blocker["radius"]) + 0.1:
				return {"ok": false, "reason": "world_overlap"}
		for existing in staged:
			var other := Vector2(float(existing["x"]), float(existing["z"]))
			if location.distance_to(other) < 2.0 * Structures.RADIUS + 0.1:
				return {"ok": false, "reason": "wall_overlap"}
		staged.append({
			"id": id, "x": x, "y": world.height_at(x, z), "z": z,
			"hp": hp, "owner": -1, "owner_key": identity,
		})
		max_id = maxi(max_id, id)
	return {"ok": true, "structures": staged, "max_id": max_id}
