extends RefCounted
const HousePieces = preload("res://scripts/shared/house_pieces.gd")
## Dedicated-server world checkpoints for account-owned barricades only.
## Authenticated account IDs stay on the server and are NEVER sent to clients.
## Session-only offline/guest structures cannot be reclaimed safely after restart.

const Structures = preload("res://scripts/shared/structures.gd")
const MarketBoard = preload("res://scripts/shared/market_board.gd")
const Defs = preload("res://scripts/shared/defs.gd")
const VERSION: int = 1
const MAX_BYTES: int = 262144 # Barricades plus escrowed market listings.
const MAX_ABS_COORD: float = 20000.0
const MIN_ID: int = 5000000001
const MAX_ID: int = 9007199254740000
const MAX_OWNER_LENGTH: int = 128


static func _bounded_int(value: Variant, low: int, high: int) -> bool:
	if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
		return false
	var number: float = float(value)
	return is_finite(number) and number >= float(low) and number <= float(high) and number == floor(number)


static func _bounded_float(value: Variant, low: float, high: float) -> bool:
	if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
		return false
	var number: float = float(value)
	return is_finite(number) and number >= low and number <= high


static func capture(sim) -> Dictionary:
	var walls: Array = []
	for id in sim.barricades:
		var item: Dictionary = sim.barricades[id]
		var account: String = str(item.get("owner_account", ""))
		if account.is_empty():
			continue # A guest peer ID is not stable across server restarts.
		walls.append({
			"id": int(id),
			"x": float(item["x"]), "z": float(item["z"]),
			"hp": float(item["hp"]), "tier": Structures.tier_of(item), "owner_account": account,
			"owner_guild": str(item.get("owner_guild", "")),
			"yaw": float(item.get("yaw", 0.0)), "piece": str(item.get("piece", "")), "open": bool(item.get("open", true)),
			"upkeep": clampf(float(item.get("upkeep_until", sim.time)) - sim.time, 0.0, Structures.UPKEEP_SECONDS),
		})
	walls.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["id"]) < int(b["id"]))
	return {"version": VERSION, "world_seed": int(sim.world.world_seed), "barricades": walls,
		"outposts": sim.territory.persistent_holds(sim.time), "market": _capture_market(sim)}


## Escrowed listings, unpaid proceeds and returned goods of signed-in accounts (guests are not saved).
static func _capture_market(sim) -> Dictionary:
	var orders: Array = []
	for listing_id in sim.market_orders.keys():
		var o: Dictionary = sim.market_orders[listing_id]
		if str(o["account"]).begins_with("peer:"):
			continue
		orders.append({"account": str(o["account"]), "seller_name": str(o.get("seller_name", "")),
			"item": str(o["item"]), "remaining": int(o["remaining"]), "price": int(o["price"]),
			"left": maxf(0.0, float(o["expires"]) - sim.time)})
	var payouts: Dictionary = {}
	for a in sim.market_payouts.keys():
		if not str(a).begins_with("peer:"):
			payouts[str(a)] = int(sim.market_payouts[a])
	var returns: Dictionary = {}
	for a in sim.market_returns.keys():
		if not str(a).begins_with("peer:"):
			returns[str(a)] = sim.market_returns[a].duplicate()
	return {"orders": orders, "payouts": payouts, "returns": returns}


static func _valid_account(a: Variant) -> bool:
	return typeof(a) == TYPE_STRING and not a.is_empty() and a.length() <= MAX_OWNER_LENGTH and not a.begins_with("peer:")


static func _validate_market(source: Variant) -> Variant:
	if typeof(source) != TYPE_DICTIONARY:
		return null
	var orders: Variant = source.get("orders", [])
	var payouts: Variant = source.get("payouts", {})
	var returns: Variant = source.get("returns", {})
	if typeof(orders) != TYPE_ARRAY or typeof(payouts) != TYPE_DICTIONARY or typeof(returns) != TYPE_DICTIONARY:
		return null
	if orders.size() > MarketBoard.MAX_LISTINGS or payouts.size() > 4096 or returns.size() > 4096:
		return null
	for o in orders:
		if typeof(o) != TYPE_DICTIONARY or not _valid_account(o.get("account")):
			return null
		if typeof(o.get("item")) != TYPE_STRING or not Defs.is_item(o["item"]) or o["item"] == "silver":
			return null
		if not _bounded_int(o.get("remaining"), 1, 1000000) or not _bounded_int(o.get("price"), 1, MarketBoard.MAX_UNIT_PRICE):
			return null
		if not _bounded_float(o.get("left"), 0.0, MarketBoard.LISTING_LIFETIME) or typeof(o.get("seller_name", "")) != TYPE_STRING:
			return null
	for a in payouts.keys():
		if not _valid_account(a) or not _bounded_int(payouts[a], 0, 2147483647):
			return null
	for a in returns.keys():
		if not _valid_account(a) or typeof(returns[a]) != TYPE_DICTIONARY or returns[a].size() > 256:
			return null
		for item in returns[a].keys():
			if typeof(item) != TYPE_STRING or not Defs.is_item(item) or not _bounded_int(returns[a][item], 1, 1000000):
				return null
	return {"orders": orders, "payouts": payouts, "returns": returns}


## Guild holds of outposts: [{id, guild, name, remaining}]. Older checkpoints have none.
static func _validate_holds(source: Variant, sim) -> Variant:
	if typeof(source) != TYPE_ARRAY or source.size() > sim.territory.sites.size():
		return null
	var holds: Array = []
	var seen: Dictionary = {}
	for value in source:
		if typeof(value) != TYPE_DICTIONARY or value.size() != 4:
			return null
		if not _bounded_int(value.get("id"), 1, 64) or sim.territory.site_by_id(int(value["id"])).is_empty():
			return null
		if seen.has(int(value["id"])):
			return null
		seen[int(value["id"])] = true
		if typeof(value.get("guild")) != TYPE_STRING or typeof(value.get("name")) != TYPE_STRING:
			return null
		var guild: String = value["guild"]
		var name: String = value["name"]
		if guild.is_empty() or guild.length() > MAX_OWNER_LENGTH or guild != guild.strip_edges() or name.length() > MAX_OWNER_LENGTH:
			return null
		if not _bounded_float(value.get("remaining"), 0.0, sim.territory.HOLD_SECONDS):
			return null
		holds.append({"id": int(value["id"]), "guild": guild, "name": name, "remaining": float(value["remaining"])})
	return holds


## Do all checks before adding a single blocker or modifying any active wall.
## Refuse a snapshot from another seed or terrain layout, including overlapping
## terrain obstacles, neighboring restored walls and impossible owner quotas.
static func validate(data: Variant, sim) -> Dictionary:
	if typeof(data) != TYPE_DICTIONARY or data.size() not in [3, 4, 5]:
		return {}
	for key in data.keys():
		if not str(key) in ["version", "world_seed", "barricades", "outposts", "market"]:
			return {}
	var market: Variant = _validate_market(data.get("market", {}))
	if market == null:
		return {}
	var holds: Variant = _validate_holds(data.get("outposts", []), sim)
	if holds == null:
		return {}
	if not _bounded_int(data.get("version"), VERSION, VERSION):
		return {}
	if not _bounded_int(data.get("world_seed"), -2147483648, 2147483647):
		return {}
	if int(data["world_seed"]) != int(sim.world.world_seed):
		return {}
	var source: Variant = data.get("barricades")
	if typeof(source) != TYPE_ARRAY or source.size() > Structures.MAX_GLOBAL:
		return {}
	var walls: Array = []
	var ids: Dictionary = {}
	var owner_counts: Dictionary = {}
	for value in source:
		if typeof(value) != TYPE_DICTIONARY or value.size() not in [5, 6, 7, 9]:
			return {}
		# Current checkpoints add the facing and the upkeep left.
		if value.size() == 9 and not (value.has("tier") and value.has("owner_guild") and value.has("yaw") and value.has("upkeep")):
			return {}
		if not _bounded_float(value.get("yaw", 0.0), 0.0, TAU) or not _bounded_float(value.get("upkeep", 0.0), 0.0, Structures.UPKEEP_SECONDS):
			return {}
		# Old checkpoints have five or six fields, before guild identity existed.
		if value.size() == 6 and not value.has("tier"):
			return {}
		if value.size() == 7 and (not value.has("tier") or not value.has("owner_guild")):
			return {}
		if not _bounded_int(value.get("id"), MIN_ID, MAX_ID):
			return {}
		var id: int = int(value["id"])
		if ids.has(id):
			return {}
		ids[id] = true
		if not _bounded_float(value.get("x"), -MAX_ABS_COORD, MAX_ABS_COORD):
			return {}
		if not _bounded_float(value.get("z"), -MAX_ABS_COORD, MAX_ABS_COORD):
			return {}
		if not _bounded_int(value.get("tier", 1), 1, Structures.MAX_TIER):
			return {}
		var tier: int = int(value.get("tier", 1))
		if not _bounded_float(value.get("hp"), 0.001, Structures.max_health(tier)):
			return {}
		if typeof(value.get("owner_account")) != TYPE_STRING:
			return {}
		var uid: String = value["owner_account"]
		if uid.is_empty() or uid.length() > MAX_OWNER_LENGTH or uid != uid.strip_edges():
			return {}
		if typeof(value.get("owner_guild", "")) != TYPE_STRING:
			return {}
		var guild: String = str(value.get("owner_guild", ""))
		if guild.length() > MAX_OWNER_LENGTH or guild != guild.strip_edges():
			return {}
		var x: float = float(value["x"])
		var z: float = float(value["z"])
		var at := Vector2(x, z)
		if at.length() < Structures.MIN_HUB_DISTANCE or sim.world.is_water(x, z):
			return {}
		if sim.world.normal_at(x, z).y < Structures.MIN_SLOPE_NORMAL_Y:
			return {}
		for blocker in sim.world.blockers_near(x, z, Structures.RADIUS + 1.0):
			if at.distance_to(Vector2(float(blocker["x"]), float(blocker["z"]))) < Structures.RADIUS + float(blocker["radius"]) + 0.1:
				return {}
		for prior in walls:
			var previous := Vector2(float(prior["x"]), float(prior["z"]))
			if at.distance_to(previous) < Structures.RADIUS * 2.0 + 0.1:
				return {}
		var next_count: int = int(owner_counts.get(uid, 0)) + 1
		if next_count > Structures.MAX_PER_OWNER:
			return {}
		owner_counts[uid] = next_count
		walls.append({"id": id, "x": x, "z": z, "hp": float(value["hp"]),
			"tier": tier, "owner_account": uid, "owner_guild": guild,
			"yaw": float(value.get("yaw", 0.0)), "upkeep": float(value.get("upkeep", Structures.UPKEEP_SECONDS)),
			"piece": str(value.get("piece", "")) if HousePieces.valid(str(value.get("piece", ""))) else "",
			"open": bool(value.get("open", true))})
	return {"version": VERSION, "world_seed": int(data["world_seed"]), "barricades": walls, "outposts": holds, "market": market}


static func restore(sim, data: Variant) -> bool:
	# Never replace live structures: restored state is an initial bootstrap only.
	if not sim.barricades.is_empty() or not sim.players.is_empty():
		return false
	var valid: Dictionary = validate(data, sim)
	if valid.is_empty():
		return false
	for wall in valid["barricades"]:
		var id: int = int(wall["id"])
		var x: float = float(wall["x"])
		var z: float = float(wall["z"])
		sim.barricades[id] = {
			"id": id, "x": x, "y": sim.world.height_at(x, z), "z": z,
			"hp": float(wall["hp"]), "tier": int(wall.get("tier", 1)), "owner": -1,
			"owner_account": wall["owner_account"], "owner_guild": str(wall.get("owner_guild", "")),
			"yaw": float(wall.get("yaw", 0.0)), "upkeep_until": sim.time + float(wall.get("upkeep", Structures.UPKEEP_SECONDS)),
		}
		var piece: String = str(wall.get("piece", ""))
		if HousePieces.valid(piece):
			sim.barricades[id]["piece"] = piece
			sim.barricades[id]["open"] = bool(wall.get("open", true))
			sim.barricades[id]["y"] = sim.world.height_at(x, z) + HousePieces.elevation(piece)
			sim.world.add_structure_blockers(id, HousePieces.blockers_of(sim.barricades[id]))
		else:
			sim.world.add_dynamic_blocker(id, x, z, Structures.RADIUS)
		sim._next_id = maxi(sim._next_id, id)
	sim.territory.restore_holds(valid["outposts"], sim.time)
	var market: Dictionary = valid["market"]
	for o in market["orders"]:
		sim.market_orders[sim.new_id()] = {"account": str(o["account"]), "seller_name": str(o.get("seller_name", "")),
			"item": str(o["item"]), "remaining": int(o["remaining"]), "price": int(o["price"]),
			"expires": sim.time + float(o["left"])}
	for a in market["payouts"].keys():
		sim.market_payouts[str(a)] = int(market["payouts"][a])
	for a in market["returns"].keys():
		var goods: Dictionary = {}
		for item in market["returns"][a].keys():
			goods[str(item)] = int(market["returns"][a][item])
		sim.market_returns[str(a)] = goods
	return true


## Prevent a --world-save argument from escaping the Cgame user-data tree.
## This is path normalization, not a defense against attacker-created symlinks
## on the host filesystem (administrators must secure the data directory).
static func valid_world_path(path: String) -> bool:
	if not path.begins_with("user://"):
		return false
	var base: String = ProjectSettings.globalize_path("user://").simplify_path().trim_suffix("/")
	var target: String = ProjectSettings.globalize_path(path).simplify_path()
	return target.begins_with(base + "/") and not target.ends_with("/")


## A successful second save retains one previous complete checkpoint in .bak.
## The backup is not loaded automatically, because that could resurrect items
## already salvaged/destroyed after the previous save.
static func save(sim, path: String) -> bool:
	if not valid_world_path(path):
		return false
	var data: Dictionary = capture(sim)
	var payload: String = JSON.stringify(data)
	if payload.to_utf8_buffer().size() > MAX_BYTES:
		return false
	var absolute: String = ProjectSettings.globalize_path(path)
	if DirAccess.make_dir_recursive_absolute(absolute.get_base_dir()) != OK:
		return false
	var temporary: String = absolute + ".tmp"
	var file: FileAccess = FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(payload)
	file.flush()
	var result: Error = file.get_error()
	file.close()
	if result != OK:
		return false
	if FileAccess.file_exists(path):
		var old_file: FileAccess = FileAccess.open(path, FileAccess.READ)
		if old_file == null:
			return false
		var old_length: int = old_file.get_length()
		if old_length <= 0 or old_length > MAX_BYTES:
			old_file.close()
			return false
		var previous: Variant = JSON.parse_string(old_file.get_as_text())
		old_file.close()
		# Refuse to rotate an obviously corrupt primary over the last backup.
		if typeof(previous) != TYPE_DICTIONARY or not _bounded_int(previous.get("version"), VERSION, VERSION):
			return false
		if not _bounded_int(previous.get("world_seed"), -2147483648, 2147483647):
			return false
		if int(previous["world_seed"]) != int(sim.world.world_seed) or typeof(previous.get("barricades")) != TYPE_ARRAY:
			return false
		var backup_temp: String = absolute + ".bak.tmp"
		if DirAccess.copy_absolute(absolute, backup_temp) != OK:
			return false
		if DirAccess.rename_absolute(backup_temp, absolute + ".bak") != OK:
			return false
	return DirAccess.rename_absolute(temporary, absolute) == OK


static func load(sim, path: String) -> bool:
	if not valid_world_path(path):
		return false
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return false
	if file.get_length() > MAX_BYTES:
		file.close()
		return false
	var decoded: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	return restore(sim, decoded)
