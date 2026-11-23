extends RefCounted
## The owner-only expedition journal shown on the full island map. All
## destinations originate from the authenticated "you" snapshot, never from
## another player's replication, and are purely visual navigation targets.

const WorldGen = preload("res://scripts/shared/world_gen.gd")
const TravelNavigation = preload("res://scripts/shared/travel_navigation.gd")


static func _add(out: Array[Dictionary], source: Variant, key: String,
		label: String, x_key: String = "x", z_key: String = "z",
		timed: bool = false) -> void:
	if not (source is Dictionary):
		return
	var data: Dictionary = source
	if timed:
		if not data.has("remaining"):
			return
		var raw_remaining: Variant = data["remaining"]
		if not (raw_remaining is float or raw_remaining is int):
			return
		var seconds: float = float(raw_remaining)
		if not is_finite(seconds) or seconds <= 0.0:
			return
	var point: Vector2 = TravelNavigation.target(data, x_key, z_key)
	if not TravelNavigation.valid_destination(point, WorldGen.WORLD_RADIUS):
		return
	out.append({"key": key, "label": label, "x": point.x, "z": point.y})


## Draw order is stable so goals do not jump when values change.
## No arbitrary user-controlled names, rewards, or inventory are displayed.
static func objectives(you: Variant) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not (you is Dictionary):
		return result
	var self_state: Dictionary = you
	_add(result, self_state.get("death_recovery", {}), "recovery",
		"LOST BACKPACK", "x", "z", true)
	var boss: Variant = self_state.get("threat_scan", {})
	if boss is Dictionary:
		var threat: Dictionary = boss
		var kind: String = str(threat.get("kind", ""))
		if kind in ["raid", "elite"]:
			_add(result, threat, "threat",
				"RAID BOSS" if kind == "raid" else "ELITE INFECTED",
				"x", "z", true)
	var mine: Variant = self_state.get("prospect_mark", {})
	if mine is Dictionary:
		var vein: Dictionary = mine
		var material: String = str(vein.get("kind", ""))
		var tier_value: Variant = vein.get("tier", 0)
		if material in ["ore", "rock"] and tier_value is int:
			var tier: int = tier_value
			if tier >= 2 and tier <= 4:
				_add(result, vein, "prospect",
					"T%d %s VEIN" % [tier, material.to_upper()],
					"x", "z", true)
	_add(result, self_state.get("ruin_survey", {}), "ruin",
		"RUIN CACHE", "x", "z", true)
	_add(result, self_state.get("caravan", {}), "caravan",
		"CARAVAN DELIVERY", "dst_x", "dst_z")
	var party: Variant = self_state.get("party", {})
	if party is Dictionary:
		var group: Dictionary = party
		_add(result, group.get("escort_caravan", {}), "escort",
			"ESCORT COURIER", "dst_x", "dst_z")
		_add(result, group.get("corpse_rescue", {}), "rescue",
			"RECOVER TEAMMATE GEAR", "x", "z", true)
		_add(result, group.get("rally", {}), "rally",
			"PARTY RALLY", "x", "z", true)
		var raw_ping: Variant = group.get("ping", {})
		if raw_ping is Dictionary:
			var party_ping: Dictionary = raw_ping
			var ping_label := "PARTY PING"
			var tier_value: Variant = party_ping.get("tier", 0)
			# A malformed tier cannot turn an ordinary ping into a high-tier ore vein.
			if str(party_ping.get("kind", "")) == "survey" and (
					str(party_ping.get("material", "")) in ["ore", "rock"]) and (
					tier_value is int) and tier_value >= 2 and tier_value <= 4:
				ping_label = "T%d %s PARTY VEIN" % [
					tier_value, str(party_ping["material"]).to_upper()]
			_add(result, party_ping, "ping", ping_label, "x", "z", true)
	return result


static func find(objectives_list: Array[Dictionary], key: String) -> Dictionary:
	for objective in objectives_list:
		if str(objective.get("key", "")) == key:
			return objective
	return {}
