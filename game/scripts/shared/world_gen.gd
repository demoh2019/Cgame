extends RefCounted
## Deterministic world from a seed: terrain height, biomes, zones and what lies in every chunk.
## The server and every client build the same world from the same seed, so the world never has to
## be sent over the network, only what changes in it.

const Defs = preload("res://scripts/shared/defs.gd")

var world_seed: int
var _continent: FastNoiseLite
var _hills: FastNoiseLite
var _detail: FastNoiseLite
var _temperature: FastNoiseLite
var _moisture: FastNoiseLite
var _cache: Dictionary = {}
var dynamic_blockers: Dictionary = {} # Session structures shared with movement and prediction.
var _hub_structures: Array = []
const CACHE_LIMIT := 256

# Height range in meters. The hub is leveled to HUB_HEIGHT so the town can be built flat.
const HUB_HEIGHT := 3.0
const HUB_BLEND_END := 140.0


func _init(p_seed: int = 1337) -> void:
	world_seed = p_seed
	_continent = _make_noise(p_seed, 0.0016, 4)
	_hills = _make_noise(p_seed + 101, 0.011, 3)
	_detail = _make_noise(p_seed + 202, 0.07, 2)
	_temperature = _make_noise(p_seed + 303, 0.0021, 2)
	_moisture = _make_noise(p_seed + 404, 0.0026, 2)


static func _make_noise(p_seed: int, frequency: float, octaves: int) -> FastNoiseLite:
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.seed = p_seed
	noise.frequency = frequency
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = octaves
	return noise


# Integer hash of a cell, stable across platforms (unlike hash() of a Variant).
static func mix(a: int, b: int, c: int, d: int = 0) -> int:
	var h: int = (a * 374761393 + b * 668265263 + c * 2147483647 + d * 1274126177) & 0x7FFFFFFFFFFF
	h = (h ^ (h >> 13)) * 1274126177 & 0x7FFFFFFFFFFF
	h = h ^ (h >> 16)
	return h & 0x7FFFFFFFFFFF


# --- Terrain ------------------------------------------------------------------------------------------

func height_at(x: float, z: float) -> float:
	var continent := _continent.get_noise_2d(x, z) # -1..1
	var hills := _hills.get_noise_2d(x, z)
	var detail := _detail.get_noise_2d(x, z)
	# Broad landmasses with lakes, rolling hills on top, and mountains where the continent is high.
	var base := continent * 26.0 + hills * 7.0 + detail * 0.8
	var mountain := maxf(continent - 0.28, 0.0)
	base += mountain * mountain * 180.0
	# Level the hub and blend smoothly into the wilderness.
	var distance := Vector2(x, z).length()
	var blend := smoothstep(Defs.HUB_SAFE_RADIUS + 20.0, HUB_BLEND_END, distance)
	return lerpf(HUB_HEIGHT, base, blend)


func is_water(x: float, z: float) -> bool:
	return height_at(x, z) < Defs.WATER_LEVEL


func normal_at(x: float, z: float) -> Vector3:
	var e := 1.0
	var dx := height_at(x + e, z) - height_at(x - e, z)
	var dz := height_at(x, z + e) - height_at(x, z - e)
	return Vector3(-dx, 2.0 * e, -dz).normalized()


func biome_at(x: float, z: float) -> String:
	var height := height_at(x, z)
	if height < Defs.WATER_LEVEL - 0.4:
		return "water"
	if height < Defs.WATER_LEVEL + 1.2:
		return "beach"
	if height > 48.0:
		return "mountain"
	var temperature := _temperature.get_noise_2d(x, z)
	var moisture := _moisture.get_noise_2d(x, z)
	if moisture > 0.25:
		return "swamp" if temperature > 0.0 else "forest"
	if moisture < -0.2:
		return "plains"
	return "forest" if temperature < 0.1 else "plains"


func zone_at(x: float, z: float) -> int:
	return Defs.zone_index_for_distance(Vector2(x, z).length())


static func tier_for_zone(zone: int) -> int:
	return clampi(zone + 1, 1, Defs.MAX_TIER)


func is_safe(x: float, z: float) -> bool:
	return Vector2(x, z).length() < Defs.HUB_SAFE_RADIUS


# --- Structures -----------------------------------------------------------------------------------------------
# Buildings and walls are part of the seed too: the server uses them as obstacles, the client draws them.
# kind: "fountain" | "building" | "wall" | "workbench". "variant" picks the model, "scale" the size in meters
# per model unit and "yaw" the rotation.

const BUILDING_VARIANTS := 5 # building-small-a..d and the garage.
const BUILDING_SCALE := 6.0
const WALL_SCALE := 3.0


## Everything built in the hub: a fountain plaza, a ring of houses and the workbench.
func hub_structures() -> Array:
	if _hub_structures.is_empty():
		_hub_structures.append({"kind": "fountain", "variant": 0, "scale": 5.0, "x": 0.0, "z": 0.0, "yaw": 0.0, "radius": 2.6, "blocks": false}) # A basin you can wade through.
		_hub_structures.append({"kind": "workbench", "variant": 0, "scale": 1.0, "x": 9.0, "z": 0.0, "yaw": 0.0, "radius": 0.9, "blocks": true})
		var count := 9
		for i in count:
			var angle := TAU * float(i) / float(count) + 0.3
			var radius := 31.0 + 3.0 * float(mix(i, 3, 17) % 3)
			var spot := Vector2.from_angle(angle) * radius
			_hub_structures.append({
				"kind": "building", "variant": mix(i, 5, 9) % BUILDING_VARIANTS, "scale": BUILDING_SCALE,
				"x": spot.x, "z": spot.y, "yaw": -angle + PI * 0.5, "radius": BUILDING_SCALE * 0.62, "blocks": true,
			})
	return _hub_structures


# --- Chunks --------------------------------------------------------------------------------------------

static func cell_of(x: float, z: float) -> Vector2i:
	return Vector2i(int(floor(x / Defs.CHUNK_SIZE)), int(floor(z / Defs.CHUNK_SIZE)))


static func cell_origin(cell: Vector2i) -> Vector2:
	return Vector2(cell.x, cell.y) * Defs.CHUNK_SIZE


# Stable id of a world entity that belongs to a chunk (resource node, crate, zombie spawn).
static func entity_id(cell: Vector2i, index: int) -> int:
	return (mix(cell.x, cell.y, 7) % 1000003) * 1000 + index + 1


## Everything in a chunk, derived from the seed: gatherable nodes, ruins with loot crates and the
## places where zombies spawn. The same call always gives the same answer.
func chunk(cell: Vector2i) -> Dictionary:
	if _cache.has(cell):
		return _cache[cell]
	if _cache.size() > CACHE_LIMIT:
		_cache.clear()
	var data := _generate_chunk(cell)
	_cache[cell] = data
	return data


func _generate_chunk(cell: Vector2i) -> Dictionary:
	var origin := cell_origin(cell)
	var center := origin + Vector2.ONE * Defs.CHUNK_SIZE * 0.5
	var zone := zone_at(center.x, center.y)
	var tier := tier_for_zone(zone)
	var rng := RandomNumberGenerator.new()
	rng.seed = mix(cell.x, cell.y, world_seed, 11)

	var nodes: Array = []
	var crates: Array = []
	var spawns: Array = []
	var structures: Array = []
	var ruin := false

	# Ruins: scavenging sites, never inside the hub, rarer in the safe green zone.
	var hub_distance := center.length()
	if hub_distance > Defs.HUB_SAFE_RADIUS + 60.0 and not is_water(center.x, center.y):
		var ruin_chance := 0.16 + 0.05 * zone
		ruin = rng.randf() < ruin_chance

	var index := 0
	var placed: Array[Vector2] = []
	var attempts := 46
	for i in attempts:
		var p := origin + Vector2(rng.randf(), rng.randf()) * Defs.CHUNK_SIZE
		if is_safe(p.x, p.y) or Vector2(p.x, p.y).length() < Defs.HUB_SAFE_RADIUS + 6.0:
			continue
		var biome := biome_at(p.x, p.y)
		if biome == "water" or is_water(p.x, p.y):
			continue
		var kind := _pick_node_kind(biome, rng)
		if kind == "":
			continue
		var info := Defs.node_info(kind)
		var spacing: float = 2.6
		var too_close := false
		for q in placed:
			if q.distance_to(p) < spacing:
				too_close = true
				break
		if too_close:
			continue
		placed.append(p)
		# Higher tiers appear deeper in the world; mountains hold the better rock and ore.
		var node_tier := tier
		if rng.randf() < 0.25:
			node_tier = clampi(tier - 1, 1, Defs.MAX_TIER)
		nodes.append({
			"id": entity_id(cell, index), "kind": kind, "tier": node_tier,
			"x": p.x, "z": p.y, "y": height_at(p.x, p.y), "radius": info["radius"], "blocks": info["blocks"],
		})
		index += 1

	if ruin:
		# A few crates near the middle of the chunk, guarded by a pack of zombies.
		var crate_count := rng.randi_range(3, 5)
		for i in crate_count:
			var p := center + Vector2(rng.randf_range(-12.0, 12.0), rng.randf_range(-12.0, 12.0))
			crates.append({
				"id": entity_id(cell, index), "kind": "crate", "tier": tier,
				"x": p.x, "z": p.y, "y": height_at(p.x, p.y), "radius": 0.6, "blocks": true,
			})
			index += 1
		# Ruined buildings and wall fragments around the crates.
		var struct_count := rng.randi_range(3, 5)
		var struct_spots: Array[Vector2] = []
		for i in struct_count * 6:
			if struct_spots.size() >= struct_count:
				break
			var spot := center + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(15.0, 25.0)
			var clear := not is_water(spot.x, spot.y)
			for other in struct_spots:
				if other.distance_to(spot) < 10.0:
					clear = false
			if clear:
				struct_spots.append(spot)
		for spot in struct_spots:
			var is_wall := rng.randf() < 0.4
			var yaw := rng.randf() * TAU
			structures.append({
				"id": entity_id(cell, index), "kind": "wall" if is_wall else "building", "variant": rng.randi_range(0, BUILDING_VARIANTS - 1),
				"scale": WALL_SCALE if is_wall else BUILDING_SCALE, "x": spot.x, "z": spot.y, "y": height_at(spot.x, spot.y), "yaw": yaw,
				"radius": WALL_SCALE * 0.6 if is_wall else BUILDING_SCALE * 0.62, "blocks": true,
			})
			index += 1
		var pack := rng.randi_range(4, 7) + zone
		for i in pack:
			var p := center + Vector2(rng.randf_range(-20.0, 20.0), rng.randf_range(-20.0, 20.0))
			spawns.append({"id": entity_id(cell, index), "x": p.x, "z": p.y, "type": _pick_zombie(zone, rng), "ruin": true})
			index += 1
	elif zone >= 1 and hub_distance > Defs.HUB_SAFE_RADIUS + 60.0:
		# Roaming zombies in the wilderness, thicker the deeper the zone.
		var wander := rng.randi_range(0, 2 + zone)
		for i in wander:
			var p := origin + Vector2(rng.randf(), rng.randf()) * Defs.CHUNK_SIZE
			if is_water(p.x, p.y):
				continue
			spawns.append({"id": entity_id(cell, index), "x": p.x, "z": p.y, "type": _pick_zombie(zone, rng), "ruin": false})
			index += 1

	return {"cell": cell, "zone": zone, "tier": tier, "ruin": ruin, "nodes": nodes, "crates": crates, "spawns": spawns, "structures": structures}


func _pick_node_kind(biome: String, rng: RandomNumberGenerator) -> String:
	var roll := rng.randf()
	match biome:
		"forest":
			if roll < 0.62:
				return "tree"
			if roll < 0.72:
				return "bush"
			if roll < 0.78:
				return "berry"
			if roll < 0.86:
				return "rock"
		"plains":
			if roll < 0.18:
				return "tree"
			if roll < 0.42:
				return "bush"
			if roll < 0.52:
				return "berry"
			if roll < 0.62:
				return "rock"
		"swamp":
			if roll < 0.35:
				return "tree"
			if roll < 0.58:
				return "bush"
			if roll < 0.66:
				return "berry"
		"beach":
			if roll < 0.18:
				return "bush"
			if roll < 0.26:
				return "rock"
		"mountain":
			if roll < 0.45:
				return "rock"
			if roll < 0.75:
				return "ore"
			if roll < 0.82:
				return "tree"
	return ""


static func _pick_zombie(zone: int, rng: RandomNumberGenerator) -> String:
	var roll := rng.randf()
	var brute_chance := 0.03 + 0.04 * zone
	var runner_chance := 0.18 + 0.06 * zone
	if roll < brute_chance:
		return "brute"
	if roll < brute_chance + runner_chance:
		return "runner"
	return "walker"


## Static things that block movement near a point, for both the server and client prediction.
func add_dynamic_blocker(id: int, x: float, z: float, radius: float) -> void:
	if is_finite(x) and is_finite(z) and is_finite(radius) and radius > 0.0:
		dynamic_blockers[id] = {"id": id, "x": x, "z": z, "radius": radius, "blocks": true}


func remove_dynamic_blocker(id: int) -> void:
	dynamic_blockers.erase(id)


func blockers_near(x: float, z: float, radius: float) -> Array:
	var result: Array = []
	if Vector2(x, z).length() < 60.0 + radius:
		for structure in hub_structures():
			if structure["blocks"] and absf(structure["x"] - x) < radius + structure["radius"] and absf(structure["z"] - z) < radius + structure["radius"]:
				result.append(structure)
	var cell_a := cell_of(x - radius, z - radius)
	var cell_b := cell_of(x + radius, z + radius)
	for cx in range(cell_a.x, cell_b.x + 1):
		for cz in range(cell_a.y, cell_b.y + 1):
			var data := chunk(Vector2i(cx, cz))
			for group in ["nodes", "crates", "structures"]:
				for n in data[group]:
					if n["blocks"] and absf(n["x"] - x) < radius + n["radius"] and absf(n["z"] - z) < radius + n["radius"]:
						result.append(n)
	# Include built obstacles without erasing the procedural hub/terrain blockers.
	for barricade in dynamic_blockers.values():
		if absf(float(barricade["x"]) - x) <= radius + float(barricade["radius"]) and absf(float(barricade["z"]) - z) <= radius + float(barricade["radius"]):
			result.append(barricade)
	return result
