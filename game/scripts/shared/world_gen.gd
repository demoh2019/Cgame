extends RefCounted
## Deterministic world from a seed: terrain height, biomes, zones and what lies in every chunk.
## The server and every client build the same world from the same seed, so the world never has to
## be sent over the network, only what changes in it.

const Defs = preload("res://scripts/shared/defs.gd")
const WorldPoi = preload("res://scripts/shared/world_poi.gd")

var world_seed: int
var _continent: FastNoiseLite
var _hills: FastNoiseLite
var _detail: FastNoiseLite
var _temperature: FastNoiseLite
var _moisture: FastNoiseLite
var _cache: Dictionary = {}
var dynamic_blockers: Dictionary = {} # Session structures shared with movement and prediction.
var _hub_structures: Array = []
var _level_rx: int = 1 << 30
var _level_rz: int = 1 << 30
var _levellers: Array = []
var poi_building := false # While sites are being found, terrain is read without their levelling.
var poi # Villages, camps, forts, ruined cities and the rest: see world_poi.gd.
const CACHE_LIMIT := 256

# Height range in meters. The hub is leveled to HUB_HEIGHT so the town can be built flat.
const HUB_HEIGHT := 3.0
const HUB_BLEND_END := 140.0
# The world is one big island: land out to EDGE_START, then it sinks into the sea that ends at WORLD_RADIUS.
const LAND_BIAS := 8.0 # Raises all land: with 0 only a tenth of the island could be walked to from the hub.
const WORLD_RADIUS := 3200.0
const EDGE_START := 2650.0


func _init(p_seed: int = 1337) -> void:
	world_seed = p_seed
	_continent = _make_noise(p_seed, 0.0016, 4)
	_hills = _make_noise(p_seed + 101, 0.011, 3)
	_detail = _make_noise(p_seed + 202, 0.07, 2)
	_temperature = _make_noise(p_seed + 303, 0.0021, 2)
	_moisture = _make_noise(p_seed + 404, 0.0026, 2)
	poi = WorldPoi.new(self)


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

## Terrain height: the natural land, levelled under every site so buildings stand on flat ground.
func height_at(x: float, z: float) -> float:
	var raw: float = _raw_height(x, z)
	if poi_building:
		return raw
	# Hot path: which sites can level ground in this region is remembered between calls.
	var rx: int = floori(x * 0.00390625) # 1 / 256, the size of a region.
	var rz: int = floori(z * 0.00390625)
	if rx != _level_rx or rz != _level_rz:
		_level_rx = rx
		_level_rz = rz
		_levellers = poi.levellers(rx, rz)
	var result: float = raw
	for site in _levellers:
		var dx: float = site["x"] - x
		var dz: float = site["z"] - z
		var outer: float = site["outer"]
		var d2: float = dx * dx + dz * dz
		if d2 < outer * outer:
			result = lerpf(result, site["y"], 1.0 - smoothstep(site["inner"], outer, sqrt(d2)))
	return result


func _raw_height(x: float, z: float) -> float:
	var continent := _continent.get_noise_2d(x, z) # -1..1
	var hills := _hills.get_noise_2d(x, z)
	var detail := _detail.get_noise_2d(x, z)
	# Broad landmasses with lakes, rolling hills on top, and mountains where the continent is high.
	var base := continent * 26.0 + hills * 7.0 + detail * 0.8 + LAND_BIAS
	var mountain := maxf(continent - 0.28, 0.0)
	base += mountain * mountain * 180.0
	# Level the hub and blend smoothly into the wilderness.
	var distance := Vector2(x, z).length()
	# The edge of the world: the land sinks into the sea.
	base -= smoothstep(EDGE_START, WORLD_RADIUS, distance) * 120.0
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


# Names of the big areas: an adjective for every 640 m cell and a noun for the kind of land you stand on.
const AREA_ADJECTIVES := ["Whispering", "Silent", "Broken", "Hollow", "Ashen", "Gilded", "Lonely", "Frozen", "Burning", "Forgotten", "Wailing", "Emerald", "Crimson", "Pale", "Iron", "Sunken"]
const AREA_NOUNS := {
	"forest": ["Pines", "Woods", "Thicket", "Timberland"], "plains": ["Fields", "Meadows", "Downs", "Steppe"],
	"swamp": ["Marsh", "Fen", "Bog"], "mountain": ["Peaks", "Crags", "Heights"], "beach": ["Shore", "Sands", "Coast"],
	"water": ["Bay", "Waters", "Deep"],
}


func area_name(x: float, z: float) -> String:
	var cell_x: int = floori(x / 640.0)
	var cell_z: int = floori(z / 640.0)
	var hash_value: int = mix(cell_x, cell_z, world_seed, 91)
	var nouns: Array = AREA_NOUNS[biome_at(x, z)]
	return "%s %s" % [AREA_ADJECTIVES[hash_value % AREA_ADJECTIVES.size()], nouns[(hash_value / 17) % nouns.size()]]


func zone_at(x: float, z: float) -> int:
	return Defs.zone_index_for_distance(Vector2(x, z).length())


static func tier_for_zone(zone: int) -> int:
	return clampi(zone + 1, 1, Defs.MAX_TIER)


## A workbench station of a settlement within reach (the hub's own workbench is separate, see GameServer).
func settlement_station_near(x: float, z: float, reach: float = WorldPoi.STATION_RANGE) -> bool:
	return poi.station_near(x, z, reach)


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
## Built from the cell coordinates, so two chunks can never share an id (a hash would, now and then, and a depleted tree
## would hide another one far away). Cells within +-1024 of the origin, 65 km, fit; ids stay under 4.3e9, clear of the
## server's own running ids and the barricade ids.
static func entity_id(cell: Vector2i, index: int) -> int:
	return ((cell.x + 1024) * 2048 + (cell.y + 1024)) * 1000 + index + 1


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
	var props: Array = []
	var npcs: Array = []
	var pois: Array = []
	var ruin := false
	# Settlements and other sites whose area touches this chunk.
	var sites: Array = poi.sites_near(center.x, center.y, Defs.CHUNK_SIZE * 0.75)

	# Ruins: scavenging sites, never inside the hub, rarer in the safe green zone.
	var hub_distance := center.length()
	if hub_distance > Defs.HUB_SAFE_RADIUS + 60.0 and not is_water(center.x, center.y):
		var ruin_chance := 0.16 + 0.05 * zone
		ruin = rng.randf() < ruin_chance
		# A site already fills the area: no extra ruin on top of it.
		for site in sites:
			if center.distance_to(Vector2(float(site["x"]), float(site["z"]))) < float(site["radius"]) + 45.0:
				ruin = false

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
		if _in_site_clearing(p, sites):
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

	# Contents of the sites: each item lands in the chunk that holds its position and gets an id there.
	var cell_rect := Rect2(origin, Vector2.ONE * Defs.CHUNK_SIZE)
	for site in sites:
		var site_zone: int = int(site["zone"])
		var content: Dictionary = poi.contents(site)
		if cell_rect.has_point(Vector2(float(site["x"]), float(site["z"]))):
			pois.append({"id": site["id"], "kind": site["kind"], "name": site["name"], "display": site["display"], "x": site["x"], "z": site["z"], "radius": site["radius"], "zone": site_zone, "station": site["station"]})
		for item in content["structures"]:
			if cell_rect.has_point(Vector2(float(item["x"]), float(item["z"]))):
				var copy: Dictionary = item.duplicate()
				copy["id"] = entity_id(cell, index)
				structures.append(copy)
				index += 1
		for item in content["crates"]:
			if cell_rect.has_point(Vector2(float(item["x"]), float(item["z"]))):
				var copy: Dictionary = item.duplicate()
				copy["id"] = entity_id(cell, index)
				copy["tier"] = tier_for_zone(site_zone)
				crates.append(copy)
				index += 1
		for item in content["nodes"]:
			if cell_rect.has_point(Vector2(float(item["x"]), float(item["z"]))):
				var copy: Dictionary = item.duplicate()
				copy["id"] = entity_id(cell, index)
				nodes.append(copy)
				index += 1
		for item in content["spawns"]:
			if cell_rect.has_point(Vector2(float(item["x"]), float(item["z"]))):
				var copy: Dictionary = item.duplicate()
				copy["id"] = entity_id(cell, index)
				spawns.append(copy)
				index += 1
		for item in content["props"]:
			if cell_rect.has_point(Vector2(float(item["x"]), float(item["z"]))):
				props.append(item)
		for item in content["npcs"]:
			if cell_rect.has_point(Vector2(float(item["x"]), float(item["z"]))):
				npcs.append(item)
	return {"cell": cell, "zone": zone, "tier": tier, "ruin": ruin, "nodes": nodes, "crates": crates, "spawns": spawns, "structures": structures, "props": props, "npcs": npcs, "pois": pois}


## Trees and rocks keep out of the inner part of a settlement, camp or city.
func _in_site_clearing(p: Vector2, sites: Array) -> bool:
	for site in sites:
		if Vector2(float(site["x"]), float(site["z"])).distance_to(p) < float(site["clear"]):
			return true
	return false


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
	# Acid spitters only appear in the two highest-risk regions.
	var spitter_chance := 0.0 if zone < 2 else 0.08 + 0.04 * float(mini(zone, 3) - 2)
	if roll < brute_chance:
		return "brute"
	if roll < brute_chance + runner_chance:
		return "runner"
	if roll < brute_chance + runner_chance + spitter_chance:
		return "spitter"
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
			for group in ["nodes", "crates", "structures", "props"]:
				for n in data[group]:
					if n["blocks"] and absf(n["x"] - x) < radius + n["radius"] and absf(n["z"] - z) < radius + n["radius"]:
						result.append(n)
	# Include built obstacles without erasing the procedural hub/terrain blockers.
	for barricade in dynamic_blockers.values():
		if absf(float(barricade["x"]) - x) <= radius + float(barricade["radius"]) and absf(float(barricade["z"]) - z) <= radius + float(barricade["radius"]):
			result.append(barricade)
	return result
