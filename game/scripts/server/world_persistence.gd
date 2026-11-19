extends RefCounted
## Dedicated-server world checkpoints for account-owned barricades only.
## Authenticated account IDs stay on the server and are NEVER sent to clients.
## Session-only offline/guest structures cannot be reclaimed safely after restart.

const Structures = preload("res://scripts/shared/structures.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const VERSION: int = 1
const MAX_BYTES: int = 131072
const MAX_ABS_COORD: float = 20000.0
const MIN_ID: int = 5000000001
const MAX_ID: int = 9007199254740000
const MAX_OWNER_LENGTH: int = 128


class ValidationContext:
	var world


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
			"hp": float(item["hp"]), "owner_account": account,
		})
	walls.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["id"]) < int(b["id"]))
	return {"version": VERSION, "world_seed": int(sim.world.world_seed), "barricades": walls}


## Do all checks before adding a single blocker or modifying any active wall.
## Refuse a snapshot from another seed or terrain layout, including overlapping
## terrain obstacles, neighboring restored walls and impossible owner quotas.
static func validate(data: Variant, sim) -> Dictionary:
	if typeof(data) != TYPE_DICTIONARY or data.size() != 3:
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
		if typeof(value) != TYPE_DICTIONARY or value.size() != 5:
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
		if not _bounded_float(value.get("hp"), 0.001, Structures.MAX_HEALTH):
			return {}
		if typeof(value.get("owner_account")) != TYPE_STRING:
			return {}
		var uid: String = value["owner_account"]
		if uid.is_empty() or uid.length() > MAX_OWNER_LENGTH or uid != uid.strip_edges():
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
		walls.append({"id": id, "x": x, "z": z, "hp": float(value["hp"]), "owner_account": uid})
	return {"version": VERSION, "world_seed": int(data["world_seed"]), "barricades": walls}


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
			"hp": float(wall["hp"]), "owner": -1, "owner_account": wall["owner_account"],
		}
		sim.world.add_dynamic_blocker(id, x, z, Structures.RADIUS)
		sim._next_id = maxi(sim._next_id, id)
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


## Check a snapshot with a fresh terrain generator, not the live world:
## existing walls would otherwise appear to overlap their own saved copies.
static func _valid_independent_snapshot(data: Variant, seed: int) -> bool:
	var context := ValidationContext.new()
	context.world = WorldGen.new(seed)
	return not validate(data, context).is_empty()


## A successful second save retains one previous complete checkpoint in .bak.
## The backup is not loaded automatically, because that could resurrect items
## already salvaged/destroyed after the previous save.
static func save(sim, path: String) -> bool:
	if not valid_world_path(path):
		return false
	var data: Dictionary = capture(sim)
	if not _valid_independent_snapshot(data, int(sim.world.world_seed)):
		return false # Never commit a malformed runtime checkpoint.
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
		# A parseable header is not enough: an impossible wall must not
		# replace the last known-good backup.
		if not _valid_independent_snapshot(previous, int(sim.world.world_seed)):
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
