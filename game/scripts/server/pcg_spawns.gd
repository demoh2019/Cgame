extends RefCounted
## PCG-placed loot caches and encounter spots, added per chunk on top of WorldGen's own content.
##
## Deterministic: the engine's PCG graphs are seeded by the world seed and never depend on how the world is cut into
## chunks, and the candidate lists are pure functions of the world seed. The server is authoritative (it alone decides what
## a crate holds and when an infected group spawns); clients attach the same extender only so their view of the chunk
## lists the same crates. No-op when ENABLED is false or the engine has no PCG classes: chunks are then exactly the
## classic ones. Hook: WorldGen.spawn_extender, called at the end of chunk generation (see PcgSpawns.attach).

const Defs = preload("res://scripts/shared/defs.gd")
const Dungeon = preload("res://scripts/shared/dungeon.gd")
const PcgGraphs = preload("res://scripts/shared/pcg_graphs.gd")

const ENABLED := true

# Entity ids inside a chunk (index of WorldGen.entity_id): clear of nodes/crates/structures (< 700), outposts (850+),
# hostiles (900+), sunken caches (950) and groves (960+).
const CRATE_ID_BASE := 700
const CRATE_ID_MAX := 12
const SPAWN_ID_BASE := 720
const SPAWN_ID_MAX := 24

const MAX_CACHES_PER_CHUNK := 3
const MAX_ENCOUNTER_SPAWNS_PER_CHUNK := 8
const LOOT_KINDS := ["city", "bunker", "depot", "mine", "landmark"]
const SETTLEMENT_KINDS := ["village", "farm", "outpost", "camp", "dock", "lighthouse", "tower"]
const SPOTS_PER_SITE := 4
const RUIN_SPOTS := 3
const HUB_ENCOUNTER_RADIUS := 25.0 # Added to Defs.HUB_SAFE_RADIUS before the graph's own margin.
const ENCOUNTERS_PER_ZONE := [1, 1, 2, 2]
const CRATE_VARIANTS := 6

var world
var _executor
var _loot_graph
var _encounter_graph


## Hooks an extender into a world when the engine supports it; returns whether it is active.
static func attach(p_world) -> bool:
	if not ENABLED or not PcgGraphs.available():
		return false
	var extender = new(p_world)
	if not extender.active():
		return false
	p_world.spawn_extender = extender
	p_world._cache.clear() # Chunks built before the hook would lack the extra content.
	return true


func _init(p_world) -> void:
	world = p_world
	if not ENABLED or not PcgGraphs.available():
		return
	_executor = ClassDB.instantiate(PcgGraphs.CLASS_EXECUTOR)
	_executor.max_cache_entries = 256
	_loot_graph = PcgGraphs.loot_caches()
	_encounter_graph = PcgGraphs.encounter_spots()


func active() -> bool:
	return ENABLED and _executor != null and _loot_graph != null and _encounter_graph != null and PcgGraphs.available()


## Adds the PCG crates and infected spawns of a chunk to its data (called by WorldGen at the end of generation).
func extend(cell: Vector2i, data: Dictionary) -> void:
	if not active() or not data.has("crates") or not data.has("spawns"):
		return
	var origin: Vector2 = world.cell_origin(cell)
	if Dungeon.is_underground(origin.x + Defs.CHUNK_SIZE):
		return
	var bounds := AABB(Vector3(origin.x, -500.0, origin.y), Vector3(Defs.CHUNK_SIZE, 1500.0, Defs.CHUNK_SIZE))
	_add_caches(cell, origin, bounds, data)
	_add_encounters(cell, origin, bounds, data)


## The points of a graph over a chunk, or null on failure.
func run_graph(graph, bounds: AABB, cell: Vector2i, overrides: Dictionary, exclusions: Array, user_data: Dictionary, salt: int):
	var context = ClassDB.instantiate("PCGContext")
	context.set_seed(world.world_seed * 31 + salt)
	context.set_bounds(bounds)
	context.set_cell(cell)
	context.set_overrides(overrides)
	context.set_height_sampler(Callable(world, "height_at"))
	context.set_biome_sampler(Callable(world, "biome_at"))
	context.set_water_sampler(Callable(world, "is_water"))
	context.set_exclusions(exclusions)
	context.set_user_data(user_data)
	var result: Dictionary = _executor.execute(graph, context)
	if result.has("error"):
		return null
	return result.get("output", null)


# --- Safe zones ---------------------------------------------------------------------------------------------------

## Exclusion cylinders around a chunk: the hub's safe zone and every settlement that can reach it.
func safe_exclusions(center: Vector2, reach: float) -> Array:
	var list: Array = [{"center": Vector3.ZERO, "radius": Defs.HUB_SAFE_RADIUS + HUB_ENCOUNTER_RADIUS}]
	for site in world.poi.sites_near(center.x, center.y, reach):
		if SETTLEMENT_KINDS.has(str(site["kind"])):
			list.append({"center": Vector3(float(site["x"]), 0.0, float(site["z"])), "radius": float(site["radius"])})
	return list


func _in_safe_area(x: float, z: float, exclusions: Array) -> bool:
	if world.is_safe(x, z):
		return true
	for e in exclusions:
		var c: Vector3 = e["center"]
		if Vector2(x - c.x, z - c.z).length() <= float(e["radius"]):
			return true
	return false


# --- Loot caches --------------------------------------------------------------------------------------------------

func _cache_candidates(cell: Vector2i, center: Vector2, data: Dictionary, exclusions: Array) -> Array:
	var points: Array = []
	var zone: int = int(data["zone"])
	var reach: float = Defs.CHUNK_SIZE * 0.75
	for site in world.poi.sites_near(center.x, center.y, reach):
		if not LOOT_KINDS.has(str(site["kind"])):
			continue
		var tier := clampi(int(site["zone"]) + 1 + (1 if str(site["kind"]) in ["city", "bunker"] else 0), 1, PcgGraphs.LOOT_TIERS)
		var rng := RandomNumberGenerator.new()
		rng.seed = world.mix(int(site["seed"]) & 0xFFFFFF, SPOTS_PER_SITE, world.world_seed, 97)
		for k in SPOTS_PER_SITE:
			var p := Vector2(float(site["x"]), float(site["z"])) + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(0.25, 0.75) * float(site["radius"])
			points.append({"position": Vector3(p.x, 0.0, p.y), "density": float(tier) / PcgGraphs.LOOT_TIERS})
	if bool(data["ruin"]):
		var tier := clampi(zone + 2, 1, PcgGraphs.LOOT_TIERS)
		var rng2 := RandomNumberGenerator.new()
		rng2.seed = world.mix(cell.x, cell.y, world.world_seed, 98)
		for k in RUIN_SPOTS:
			var p := center + Vector2.from_angle(rng2.randf() * TAU) * rng2.randf_range(26.0, 33.0)
			points.append({"position": Vector3(p.x, 0.0, p.y), "density": float(tier) / PcgGraphs.LOOT_TIERS})
	var kept: Array = []
	for point in points:
		var pos: Vector3 = point["position"]
		if world.is_water(pos.x, pos.z) or _in_safe_area(pos.x, pos.z, exclusions):
			continue
		pos.y = world.height_at(pos.x, pos.z)
		point["position"] = pos
		kept.append(point)
	return kept


func _add_caches(cell: Vector2i, origin: Vector2, bounds: AABB, data: Dictionary) -> void:
	var center: Vector2 = origin + Vector2.ONE * Defs.CHUNK_SIZE * 0.5
	var exclusions := safe_exclusions(center, Defs.CHUNK_SIZE * 0.75)
	var candidates := _cache_candidates(cell, center, data, exclusions)
	if candidates.is_empty():
		return
	var points = run_graph(_loot_graph, bounds, cell, {"max_per_chunk": MAX_CACHES_PER_CHUNK}, exclusions, {"pois": candidates}, 11)
	if points == null:
		return
	var index := 0
	for i in points.get_point_count():
		if index >= CRATE_ID_MAX:
			break
		var p: Vector3 = points.get_position(i)
		if _blocked_by_structure(p, data):
			continue
		var tier := clampi(int(points.get_attribute_value("asset", i, 1.0)), 1, Defs.MAX_TIER)
		data["crates"].append({
			"id": world.entity_id(cell, CRATE_ID_BASE + index), "kind": "crate", "variant": absi(int(points.get_seed(i))) % CRATE_VARIANTS,
			"tier": tier, "x": p.x, "z": p.z, "y": p.y, "radius": 0.6, "blocks": true, "pcg": true,
		})
		index += 1


func _blocked_by_structure(p: Vector3, data: Dictionary) -> bool:
	for s in data["structures"]:
		if Vector2(p.x - float(s["x"]), p.z - float(s["z"])).length() < float(s.get("radius", 1.0)) + 1.5:
			return true
	return false


# --- Encounter spots ----------------------------------------------------------------------------------------------

func _add_encounters(cell: Vector2i, origin: Vector2, bounds: AABB, data: Dictionary) -> void:
	var center: Vector2 = origin + Vector2.ONE * Defs.CHUNK_SIZE * 0.5
	var zone: int = int(data["zone"])
	var exclusions := safe_exclusions(center, Defs.CHUNK_SIZE * 0.75 + 60.0)
	var limit: int = ENCOUNTERS_PER_ZONE[clampi(zone, 0, ENCOUNTERS_PER_ZONE.size() - 1)]
	var points = run_graph(_encounter_graph, bounds, cell, {"max_per_chunk": limit}, exclusions, {}, 13)
	if points == null:
		return
	var index := 0
	var total := 0
	for i in points.get_point_count():
		var rng := RandomNumberGenerator.new()
		rng.seed = world.mix(int(points.get_seed(i)) & 0xFFFFFFF, cell.x, world.world_seed, 101)
		var group := 1 + (rng.randi_range(0, mini(zone, 2)) if zone > 0 else 0)
		var spot: Vector3 = points.get_position(i)
		for g in group:
			if index >= SPAWN_ID_MAX or total >= MAX_ENCOUNTER_SPAWNS_PER_CHUNK:
				return
			var p := Vector2(spot.x, spot.z) + Vector2(rng.randf_range(-4.0, 4.0), rng.randf_range(-4.0, 4.0))
			var type: String = world._pick_zombie(zone, rng) # Always draw: later spawns of the group stay stable.
			if world.is_water(p.x, p.y) or _in_safe_area(p.x, p.y, exclusions):
				continue
			data["spawns"].append({"id": world.entity_id(cell, SPAWN_ID_BASE + index), "x": p.x, "z": p.y, "type": type, "ruin": false, "pcg": true})
			index += 1
			total += 1
