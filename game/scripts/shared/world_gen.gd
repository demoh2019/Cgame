extends RefCounted
## Deterministic world from a seed: terrain height, biomes, zones and what lies in every chunk.
## The server and every client build the same world from the same seed, so the world never has to
## be sent over the network, only what changes in it.

const WorldRivers = preload("res://scripts/shared/world_rivers.gd")
const Defs = preload("res://scripts/shared/defs.gd")
const Dungeon = preload("res://scripts/shared/dungeon.gd")
const WorldPoi = preload("res://scripts/shared/world_poi.gd")
const WorldRoads = preload("res://scripts/shared/world_roads.gd")
const StoneResources = preload("res://scripts/shared/stone_resources.gd")
const StaticBlockerGrid = preload("res://scripts/shared/static_blocker_grid.gd")
const DynamicBlockerGrid = preload("res://scripts/shared/dynamic_blocker_grid.gd")
const SolidScenery = preload("res://scripts/shared/solid_scenery.gd")

var world_seed: int
var _continent: FastNoiseLite
var _hills: FastNoiseLite
var _detail: FastNoiseLite
var _temperature: FastNoiseLite
var _moisture: FastNoiseLite
var _cache: Dictionary = {}
var _cache_ages: Dictionary = {} # Last use of each live chunk; incremental LRU eviction.
var _static_blockers: Dictionary = {} # Per-chunk 8m tile broadphase, same LRU lifetime as _cache.
var _cache_clock: int = 0
var _cache_hits: int = 0
var _cache_misses: int = 0
var _cache_evictions: int = 0
var dynamic_blockers: Dictionary = {} # Session structures shared with movement and prediction.
var _dynamic_index := DynamicBlockerGrid.new() # Exact incremental broadphase for built obstacles.
# Generated resource geometry remains immutable for deterministic world seeding.
# Only its collision eligibility is mutable, matching server depletion and
# client snapshot state (the renderer hides the same node IDs).
var depleted_blockers: Dictionary = {}

var _hub_structures: Array = []
var _level_rx: int = 1 << 30
var _level_rz: int = 1 << 30
var _levellers: Array = []
var _erosion: FastNoiseLite
var poi_building := false # While sites are being found, terrain is read without their levelling.
var roads # Seeded roads shared by renderer and movement physics.
var rivers # Seeded rivers and lakes carved into the land (world_rivers.gd).
var poi # Villages, camps, forts, ruined cities and the rest: see world_poi.gd.
var spawn_extender = null # Optional per-chunk content hook (server/pcg_spawns.gd); null = classic chunks.
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
	_erosion = _make_noise(p_seed + 505, 0.0055, 3)
	_erosion.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	rivers = WorldRivers.new(self)
	rivers.ensure_built() # Before sites: villages must see the rivers to stay out of them.
	poi = WorldPoi.new(self)
	roads = WorldRoads.new(self)

## Renderer and authoritative locomotion query exactly the same road graph.
func road_coverage_at(x: float, z: float) -> float:
	return roads.coverage_at(x, z)


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
	var ground: float = ground_at(x, z)
	# Bridge decks carry roads over rivers: you walk on the deck, not in the water below.
	if roads != null and not poi_building:
		var deck: float = roads.bridge_deck(x, z)
		if deck > ground:
			return deck
	return ground


## The ground itself (no bridge decks): what the terrain mesh is built from.
func ground_at(x: float, z: float) -> float:
	if x >= Dungeon.UNDERGROUND_X - 40.0 and not poi_building:
		return Dungeon.FLOOR_Y # The stone floor of the dungeons below the bunkers.
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


## Natural land with rivers and lakes cut in.
func _raw_height(x: float, z: float) -> float:
	return rivers.carve(x, z, _base_height(x, z)) if rivers != null else _base_height(x, z)


## The natural land before rivers: continents, hills, mountains, and erosion on the slopes.
func _base_height(x: float, z: float) -> float:
	var continent := _continent.get_noise_2d(x, z) # -1..1
	var hills := _hills.get_noise_2d(x, z)
	var detail := _detail.get_noise_2d(x, z)
	# Broad landmasses with lakes, rolling hills on top, and mountains where the continent is high.
	var base := continent * 26.0 + hills * 7.0 + detail * 0.8 + LAND_BIAS
	var mountain := maxf(continent - 0.28, 0.0)
	base += mountain * mountain * 180.0
	# Erosion, approximated analytically (no per-frame simulation; height_at must stay a pure function):
	# hydraulic - branching gullies and ravines cut down the high ground, deepest on mountains;
	# thermal - the very tops slump, so peaks round off instead of standing as needles.
	var high: float = smoothstep(10.0, 60.0, base)
	var gully: float = 1.0 - absf(_erosion.get_noise_2d(x, z))
	base -= high * pow(gully, 5.0) * (6.0 + mountain * 55.0)
	if base > 70.0:
		base = 70.0 + (base - 70.0) * 0.72
	# Level the hub and blend smoothly into the wilderness.
	var distance := Vector2(x, z).length()
	# The edge of the world: the land sinks into the sea.
	base -= smoothstep(EDGE_START, WORLD_RADIUS, distance) * 120.0
	var blend := smoothstep(Defs.HUB_SAFE_RADIUS + 20.0, HUB_BLEND_END, distance)
	return lerpf(HUB_HEIGHT, base, blend)


func is_water(x: float, z: float) -> bool:
	var ground: float = height_at(x, z)
	return ground < Defs.WATER_LEVEL or (rivers != null and rivers.surface_at(x, z) > ground)


## Water surface height here: the sea level, or a river/lake surface above it.
func water_level_at(x: float, z: float) -> float:
	return maxf(Defs.WATER_LEVEL, rivers.surface_at(x, z) if rivers != null else -INF)


func normal_at(x: float, z: float) -> Vector3:
	var e := 1.0
	var dx := height_at(x + e, z) - height_at(x - e, z)
	var dz := height_at(x, z + e) - height_at(x, z - e)
	return Vector3(-dx, 2.0 * e, -dz).normalized()


func biome_at(x: float, z: float) -> String:
	if Dungeon.is_underground(x, z):
		return "dungeon"
	var height := height_at(x, z)
	if height < Defs.WATER_LEVEL - 0.4 or (rivers != null and rivers.surface_at(x, z) > height):
		return "water"
	if height < Defs.WATER_LEVEL + 1.2:
		return "beach"
	if height > 48.0:
		return "mountain"
	return _biome_from_climate(_temperature.get_noise_2d(x, z), _moisture.get_noise_2d(x, z))


static func _biome_from_climate(temperature: float, moisture: float) -> String:
	if moisture > 0.25:
		return "swamp" if temperature > 0.0 else "forest"
	if moisture < -0.2:
		return "plains"
	return "forest" if temperature < 0.1 else "plains"


## Cgame samples an entire chart row natively; stock Godot uses identical serial samples.
static func _sample_noise_2dv(noise: Noise, points: PackedVector2Array, force_scalar: bool = false) -> PackedFloat64Array:
	if not force_scalar and noise.has_method("get_noise_2dv_batch"):
		var native_values: PackedFloat64Array = noise.call("get_noise_2dv_batch", points)
		return native_values
	var samples := PackedFloat64Array()
	samples.resize(points.size())
	for i in points.size():
		samples[i] = noise.get_noise_2d(points[i].x, points[i].y)
	return samples


## Batch biome classification for render/chart consumers with precomputed heights.
## Scalar biome_at() remains the authoritative query and is not changed for simulation.
func biomes_at_points(points: PackedVector2Array, heights: PackedFloat64Array) -> PackedStringArray:
	var result := PackedStringArray()
	if points.size() != heights.size():
		return result
	var temperatures: PackedFloat64Array = _sample_noise_2dv(_temperature, points)
	var moistures: PackedFloat64Array = _sample_noise_2dv(_moisture, points)
	for i in points.size():
		var position: Vector2 = points[i]
		var height: float = heights[i]
		if Dungeon.is_underground(position.x, position.y):
			result.append("dungeon")
		elif height < Defs.WATER_LEVEL - 0.4:
			result.append("water")
		elif height < Defs.WATER_LEVEL + 1.2:
			result.append("beach")
		elif height > 48.0:
			result.append("mountain")
		else:
			result.append(_biome_from_climate(temperatures[i], moistures[i]))
	return result


# Names of the big areas: an adjective for every 640 m cell and a noun for the kind of land you stand on.
const AREA_ADJECTIVES := ["Whispering", "Silent", "Broken", "Hollow", "Ashen", "Gilded", "Lonely", "Frozen", "Burning", "Forgotten", "Wailing", "Emerald", "Crimson", "Pale", "Iron", "Sunken"]
const AREA_NOUNS := {
	"forest": ["Pines", "Woods", "Thicket", "Timberland"], "plains": ["Fields", "Meadows", "Downs", "Steppe"],
	"swamp": ["Marsh", "Fen", "Bog"], "mountain": ["Peaks", "Crags", "Heights"], "beach": ["Shore", "Sands", "Coast"],
	"water": ["Bay", "Waters", "Deep"],
	"dungeon": ["Vaults", "Depths", "Catacombs", "Undercroft"],
}


func area_name(x: float, z: float) -> String:
	var cell_x: int = floori(x / 640.0)
	var cell_z: int = floori(z / 640.0)
	var hash_value: int = mix(cell_x, cell_z, world_seed, 91)
	var nouns: Array = AREA_NOUNS[biome_at(x, z)]
	return "%s %s" % [AREA_ADJECTIVES[hash_value % AREA_ADJECTIVES.size()], nouns[(hash_value / 17) % nouns.size()]]


func zone_at(x: float, z: float) -> int:
	if Dungeon.is_underground(x, z):
		return dungeon_zone(Dungeon.region_of(x, z))
	return Defs.zone_index_for_distance(Vector2(x, z).length())


var _dungeon_zones: Dictionary = {}


## A dungeon is one zone deeper than the land above it (harder infected, richer chests), at most black.
func dungeon_zone(region: Vector2i) -> int:
	if not _dungeon_zones.has(region):
		var zone := 3
		var bunker: Dictionary = dungeon_bunker(region)
		if not bunker.is_empty():
			zone = mini(3, Defs.zone_index_for_distance(Vector2(float(bunker["x"]), float(bunker["z"])).length()) + 1)
		_dungeon_zones[region] = zone
	return _dungeon_zones[region]


## The bunker above a region's dungeon, or {} where that region has none.
func dungeon_bunker(region: Vector2i) -> Dictionary:
	for site in poi.sites_in_region(region.x, region.y):
		if str(site.get("kind", "")) == "bunker":
			return site
	return {}


## A chunk underground: the infected and the chests of the dungeon rooms whose centre lies in it; no trees, no sites.
func _dungeon_chunk(cell: Vector2i, origin: Vector2) -> Dictionary:
	var nodes: Array = []
	var crates: Array = []
	var spawns: Array = []
	var cell_rect := Rect2(origin, Vector2.ONE * Defs.CHUNK_SIZE)
	var region: Vector2i = Dungeon.region_of(origin.x + Defs.CHUNK_SIZE * 0.5, origin.y + Defs.CHUNK_SIZE * 0.5)
	var zone: int = dungeon_zone(region)
	var index := 0
	if not dungeon_bunker(region).is_empty():
		for room in Dungeon.layout(world_seed, region)["rooms"]:
			if not cell_rect.has_point(Dungeon.room_center(region, room)):
				continue
			var contents: Dictionary = Dungeon.room_contents(world_seed, region, room, zone)
			for infected in contents["infected"]:
				spawns.append({"id": entity_id(cell, index), "x": float(infected["x"]), "z": float(infected["z"]),
					"type": str(infected["type"]), "ruin": true, "dungeon_boss": bool(infected["boss"])})
				index += 1
			for chest in contents["chests"]:
				crates.append({"id": entity_id(cell, index), "kind": "crate", "tier": int(chest["tier"]), "dungeon": true,
					"x": float(chest["x"]), "z": float(chest["z"]), "y": Dungeon.FLOOR_Y, "radius": 0.6, "blocks": true})
				index += 1
	return {"cell": cell, "zone": zone, "tier": tier_for_zone(zone), "ruin": true, "nodes": nodes, "crates": crates,
		"spawns": spawns, "structures": [], "props": [], "npcs": [], "pois": [], "dungeon": true}


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
	_cache_clock += 1
	if _cache.has(cell):
		_cache_hits += 1
		_cache_ages[cell] = _cache_clock
		return _cache[cell]
	_cache_misses += 1
	# Evict only the least recently used chunk. Clearing the entire cache
	# caused a burst of expensive world-generation work at the 256-cell edge.
	if _cache.size() >= CACHE_LIMIT:
		var oldest_cell: Vector2i = _cache_ages.keys()[0]
		var oldest_age: int = int(_cache_ages[oldest_cell])
		for cached_cell in _cache_ages:
			var age: int = int(_cache_ages[cached_cell])
			if age < oldest_age:
				oldest_cell = cached_cell
				oldest_age = age
		_cache.erase(oldest_cell)
		_cache_ages.erase(oldest_cell)
		_static_blockers.erase(oldest_cell)
		_cache_evictions += 1
	var data: Dictionary = _generate_chunk(cell)
	_cache[cell] = data
	_cache_ages[cell] = _cache_clock
	# Build the footprint-aware 8m tile index only on a cache miss.
	# The existing per-chunk LRU evicts this index together with its data.
	_static_blockers[cell] = StaticBlockerGrid.build(data, cell_origin(cell))
	return data


## Lightweight counters used by the in-game performance overlay and tests.
func chunk_cache_stats() -> Dictionary:
	return {"size": _cache.size(), "capacity": CACHE_LIMIT, "hits": _cache_hits,
		"misses": _cache_misses, "evictions": _cache_evictions,
		"collision_chunks": _static_blockers.size()}


func chunk_cache_size() -> int:
	return _cache.size()


func chunk_cache_evictions() -> int:
	return _cache_evictions


func chunk_cache_hit_percent() -> float:
	var total: int = _cache_hits + _cache_misses
	return 0.0 if total == 0 else 100.0 * float(_cache_hits) / float(total)


## Sunken caches lie on the bottom of deep water; only a diver can open them. A separate
## random stream keeps every other piece of the chunk exactly as it was before.
const SUNKEN_MIN_DEPTH := 2.2
const SUNKEN_ID_BASE := 950


## Extra infected that make the wilds teem: ruin guardians and screamers, crawler swarms,
## lone stalkers that hunt you down, and stragglers even in the green zone. Own random
## stream, so every other piece of the chunk is unchanged.
const HOSTILE_ID_BASE := 900
const HOSTILE_ID_MAX := 45


func _add_hostiles(cell: Vector2i, origin: Vector2, zone: int, ruin: bool, spawns: Array) -> void:
	var center := origin + Vector2.ONE * Defs.CHUNK_SIZE * 0.5
	if center.length() < Defs.HUB_SAFE_RADIUS + 60.0 or Dungeon.is_underground(origin.x + Defs.CHUNK_SIZE):
		return
	var hrng := RandomNumberGenerator.new()
	hrng.seed = mix(cell.x, cell.y, world_seed, 83)
	var picks: Array = [] # [type, position]
	if ruin:
		# Every ruin has a guardian; darker zones add a screamer and a bigger pack.
		picks.append(["sentinel" if zone >= 1 else "brute", center + _jitter(hrng, 8.0)])
		if zone >= 1 and hrng.randf() < 0.55:
			picks.append(["howler", center + _jitter(hrng, 14.0)])
		for i in hrng.randi_range(2, 4) + zone:
			picks.append(["crawler" if hrng.randf() < 0.5 else "walker", center + _jitter(hrng, 22.0)])
	elif zone == 0:
		for i in hrng.randi_range(1, 4):
			picks.append(["walker", origin + Vector2(hrng.randf(), hrng.randf()) * Defs.CHUNK_SIZE])
		if hrng.randf() < 0.2:
			var green_nest := origin + Vector2(hrng.randf(), hrng.randf()) * Defs.CHUNK_SIZE
			for i in hrng.randi_range(3, 5):
				picks.append(["crawler", green_nest + _jitter(hrng, 5.0)])
	else:
		if hrng.randf() < 0.45 + 0.1 * zone:
			var nest := origin + Vector2(hrng.randf(), hrng.randf()) * Defs.CHUNK_SIZE
			for i in hrng.randi_range(4, 6) + zone:
				picks.append(["crawler", nest + _jitter(hrng, 6.0)])
		if hrng.randf() < 0.25 + 0.1 * zone:
			picks.append(["stalker", origin + Vector2(hrng.randf(), hrng.randf()) * Defs.CHUNK_SIZE])
		if hrng.randf() < 0.18 + 0.05 * zone:
			picks.append(["howler", origin + Vector2(hrng.randf(), hrng.randf()) * Defs.CHUNK_SIZE])
		for i in hrng.randi_range(2, 4 + zone):
			picks.append([_pick_zombie(zone, hrng), origin + Vector2(hrng.randf(), hrng.randf()) * Defs.CHUNK_SIZE])
	var k := 0
	for pick in picks:
		if k >= HOSTILE_ID_MAX:
			break
		var p: Vector2 = pick[1]
		if is_water(p.x, p.y) or is_safe(p.x, p.y):
			continue
		spawns.append({"id": entity_id(cell, HOSTILE_ID_BASE + k), "x": p.x, "z": p.y, "type": str(pick[0]), "ruin": ruin})
		k += 1


static func _jitter(rng: RandomNumberGenerator, radius: float) -> Vector2:
	return Vector2(rng.randf_range(-radius, radius), rng.randf_range(-radius, radius))


## Lone wilderness outposts between the settlements: a trapper's shack, a watchtower, or a cluster
## of ruins, often with a loot crate and some clutter. Collidable structures shared by server and
## client; own random stream (ids 850-899), so everything else in the chunk keeps its place.
const OUTPOST_ID_BASE := 850
const OUTPOST_CHANCE := 0.32


func _add_outposts(cell: Vector2i, origin: Vector2, zone: int, ruin: bool, structures: Array, crates: Array,
		props: Array, sites: Array) -> void:
	var center := origin + Vector2.ONE * Defs.CHUNK_SIZE * 0.5
	if ruin or center.length() < Defs.HUB_SAFE_RADIUS + 80.0 or Dungeon.is_underground(origin.x + Defs.CHUNK_SIZE):
		return
	var orng := RandomNumberGenerator.new()
	orng.seed = mix(cell.x, cell.y, world_seed, 131)
	if orng.randf() > OUTPOST_CHANCE:
		return
	var at := origin + Vector2(orng.randf_range(14.0, 50.0), orng.randf_range(14.0, 50.0))
	if is_water(at.x, at.y) or is_safe(at.x, at.y) or normal_at(at.x, at.y).y < 0.85:
		return
	for site in sites:
		if at.distance_to(Vector2(float(site["x"]), float(site["z"]))) < float(site["radius"]) + 25.0:
			return
	var index := OUTPOST_ID_BASE
	var kind_roll := orng.randf()
	var yaw := orng.randf() * TAU
	if kind_roll < 0.4:
		# Trapper's shack.
		structures.append({"id": entity_id(cell, index), "kind": "building", "variant": orng.randi_range(0, BUILDING_VARIANTS - 1),
			"scale": BUILDING_SCALE, "x": at.x, "z": at.y, "y": height_at(at.x, at.y), "yaw": yaw,
			"radius": BUILDING_SCALE * 0.62, "blocks": true})
		index += 1
	elif kind_roll < 0.7:
		# Watchtower.
		structures.append({"id": entity_id(cell, index), "kind": "tower", "variant": orng.randi_range(0, WorldPoi.TOWER_VARIANTS - 1),
			"scale": 5.0 * orng.randf_range(0.8, 1.1), "x": at.x, "z": at.y, "y": height_at(at.x, at.y), "yaw": 0.0,
			"radius": 2.4, "blocks": true})
		index += 1
	else:
		# Overgrown ruins: a few broken walls and remains.
		for r in orng.randi_range(3, 6):
			var p := at + Vector2.from_angle(orng.randf() * TAU) * orng.randf_range(3.0, 9.0)
			if is_water(p.x, p.y):
				continue
			var variant := orng.randi_range(0, WorldPoi.RUIN_RADII.size() - 1)
			structures.append({"id": entity_id(cell, index), "kind": "ruin", "variant": variant, "scale": 1.0,
				"x": p.x, "z": p.y, "y": height_at(p.x, p.y), "yaw": orng.randf() * TAU,
				"radius": WorldPoi.RUIN_RADII[variant], "blocks": true})
			index += 1
	# Clutter and, often, a crate to scavenge.
	for c in orng.randi_range(2, 4):
		var p := at + Vector2.from_angle(orng.randf() * TAU) * orng.randf_range(4.5, 8.0)
		if is_water(p.x, p.y):
			continue
		var variant := orng.randi_range(0, mini(8, WorldPoi.PROP_RADII.size() - 1))
		props.append({"id": entity_id(cell, index), "kind": "prop", "variant": variant, "x": p.x, "z": p.y, "y": height_at(p.x, p.y),
			"yaw": orng.randf() * TAU, "scale": 1.5, "radius": WorldPoi.PROP_RADII[variant], "blocks": true})
		index += 1
	if orng.randf() < 0.65:
		var p := at + Vector2.from_angle(orng.randf() * TAU) * orng.randf_range(4.0, 6.0)
		if not is_water(p.x, p.y):
			crates.append({"id": entity_id(cell, index), "kind": "crate", "tier": tier_for_zone(zone),
				"x": p.x, "z": p.y, "y": height_at(p.x, p.y), "radius": 0.6, "blocks": true})


## Extra trees in groves, so forests read as forests: a few grove centres per chunk with trees
## clustered around them, densest in forest, thinner in swamp and plains. Real gatherable,
## collidable tree nodes (server and client agree), on their own random stream so every other
## node of the chunk keeps its place. Ids 960-999.
const PICKUP_ID_BASE := 790 # 790..809: between loose-stone and outpost IDs.
const GROVE_ID_BASE := 960
const GROVE_ID_MAX := 40
const GROVE_TREES := {"forest": [18, 30], "swamp": [8, 14], "plains": [4, 10]}


func _add_groves(cell: Vector2i, origin: Vector2, tier: int, nodes: Array, sites: Array) -> void:
	var center := origin + Vector2.ONE * Defs.CHUNK_SIZE * 0.5
	if center.length() < Defs.HUB_SAFE_RADIUS + 20.0 or Dungeon.is_underground(origin.x + Defs.CHUNK_SIZE):
		return
	var biome := biome_at(center.x, center.y)
	if not GROVE_TREES.has(biome):
		return
	var grng := RandomNumberGenerator.new()
	grng.seed = mix(cell.x, cell.y, world_seed, 97)
	var wanted: int = grng.randi_range(int(GROVE_TREES[biome][0]), int(GROVE_TREES[biome][1]))
	var groves: Array[Vector2] = []
	for g in grng.randi_range(2, 4):
		groves.append(origin + Vector2(grng.randf(), grng.randf()) * Defs.CHUNK_SIZE)
	var taken: Array[Vector2] = []
	for node in nodes:
		taken.append(Vector2(float(node["x"]), float(node["z"])))
	var info := Defs.node_info("tree")
	var placed := 0
	for attempt in wanted * 4:
		if placed >= mini(wanted, GROVE_ID_MAX):
			break
		var grove: Vector2 = groves[grng.randi() % groves.size()]
		var p := grove + Vector2.from_angle(grng.randf() * TAU) * (sqrt(grng.randf()) * 14.0)
		if p.x < origin.x or p.y < origin.y or p.x >= origin.x + Defs.CHUNK_SIZE or p.y >= origin.y + Defs.CHUNK_SIZE:
			continue
		if is_water(p.x, p.y) or is_safe(p.x, p.y) or biome_at(p.x, p.y) != biome or _in_site_clearing(p, sites):
			continue
		var crowded := false
		for q in taken:
			if q.distance_to(p) < 3.2:
				crowded = true
				break
		if crowded:
			continue
		taken.append(p)
		nodes.append({
			"id": entity_id(cell, GROVE_ID_BASE + placed), "kind": "tree", "tier": tier,
			"x": p.x, "z": p.y, "y": height_at(p.x, p.y), "radius": info["radius"], "blocks": info["blocks"],
		})
		placed += 1


## Small items are real server/client-shared resource nodes, not cosmetic PCG meshes.
## Separate random stream and reserved IDs keep all existing tree/ore placement stable.
func _add_ground_pickups(cell: Vector2i, origin: Vector2, nodes: Array, sites: Array) -> void:
	var prng := RandomNumberGenerator.new()
	prng.seed = mix(cell.x, cell.y, world_seed, 109)
	var wanted: int = prng.randi_range(4, 8)
	var placed: int = 0
	for _attempt in 48:
		if placed >= wanted:
			break
		var p: Vector2 = origin + Vector2(prng.randf(), prng.randf()) * Defs.CHUNK_SIZE
		if is_water(p.x, p.y) or is_safe(p.x, p.y) or _in_site_clearing(p, sites):
			continue
		var too_close: bool = false
		for existing in nodes:
			if Vector2(float(existing["x"]), float(existing["z"])).distance_to(p) < 1.5:
				too_close = true
				break
		if too_close:
			continue
		var kind: String = "pebble" if prng.randf() < 0.52 else "branch"
		var info: Dictionary = Defs.node_info(kind)
		nodes.append({
			"id": entity_id(cell, PICKUP_ID_BASE + placed), "kind": kind, "tier": 1,
			"x": p.x, "z": p.y, "y": height_at(p.x, p.y),
			"radius": info["radius"], "blocks": false,
		})
		placed += 1


func _add_sunken_caches(cell: Vector2i, origin: Vector2, zone: int, crates: Array) -> void:
	var sunken_rng := RandomNumberGenerator.new()
	sunken_rng.seed = mix(cell.x, cell.y, world_seed, 71)
	if sunken_rng.randf() > 0.35:
		return
	var placed := 0
	for attempt in 10:
		if placed >= 2:
			break
		var p := origin + Vector2(sunken_rng.randf(), sunken_rng.randf()) * Defs.CHUNK_SIZE
		var depth: float = Defs.WATER_LEVEL - height_at(p.x, p.y)
		if depth < SUNKEN_MIN_DEPTH or is_safe(p.x, p.y):
			continue
		crates.append({
			"id": entity_id(cell, SUNKEN_ID_BASE + placed), "kind": "crate", "sunken": true,
			"tier": clampi(tier_for_zone(zone) + 1, 1, Defs.MAX_TIER),
			"x": p.x, "z": p.y, "y": height_at(p.x, p.y), "radius": 0.6, "blocks": false,
		})
		placed += 1


## Loose rocks have stable, independently seeded resource ids. The older
## generated chunks use < 550; outposts start at 850, hostiles at 900,
## sunken caches at 950, and grove trees at 960.
const STONE_ID_BASE := 550
const STONE_ID_LIMIT := 240


func _try_add_stone(cell: Vector2i, origin: Vector2, point: Vector2, small: bool,
		tier: int, sites: Array, nodes: Array, placed: Array[Vector2],
		rng: RandomNumberGenerator, position_index: int) -> bool:
	if position_index >= STONE_ID_LIMIT:
		return false
	if point.x < origin.x or point.y < origin.y or point.x >= origin.x + Defs.CHUNK_SIZE or point.y >= origin.y + Defs.CHUNK_SIZE:
		return false
	if is_water(point.x, point.y) or is_safe(point.x, point.y) or _in_site_clearing(point, sites):
		return false
	if roads != null and roads.coverage_at(point.x, point.y) > 0.0:
		return false
	for other in placed:
		if other.distance_squared_to(point) < (0.9 if small else 3.0) ** 2:
			return false
	var biome: String = biome_at(point.x, point.y)
	var variant: int = StoneResources.pick_model(biome, small, rng)
	if variant < 0:
		return false
	var entry: Dictionary = StoneResources.MODELS[variant]
	# A tiny pickable stone uses the real scanned/kit model; a large rock is
	# a normal mineable resource and requires tools/skill according to tier.
	var scale: float = rng.randf_range(0.4, 0.75) if small else rng.randf_range(0.75, 1.2)
	var kind: String = "pebble" if small else "rock"
	var info: Dictionary = Defs.node_info(kind)
	var visual_radius: float = clampf(float(entry["size"]) * scale * 0.4, 0.12, 1.8)
	nodes.append({
		"id": entity_id(cell, STONE_ID_BASE + position_index),
		"kind": kind, "tier": 1 if small else tier,
		"stone_model": variant, "scale": scale, "yaw": rng.randf() * TAU,
		"x": point.x, "z": point.y, "y": height_at(point.x, point.y),
		"radius": visual_radius if not small else float(info["radius"]),
		"blocks": not small,
	})
	placed.append(point)
	return true


## This is server/client shared world content, not decorative MultiMeshes.
## Every visible loose stone has an authoritative id, depletion and inventory
## reward. The separate random stream leaves original trees, ores and crates
## unchanged and limits the resource overhead of each chunk.
func _add_loose_stones(cell: Vector2i, origin: Vector2, tier: int, nodes: Array,
		sites: Array) -> void:
	var center: Vector2 = origin + Vector2.ONE * Defs.CHUNK_SIZE * 0.5
	if center.length() < Defs.HUB_SAFE_RADIUS + 30.0:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = mix(cell.x, cell.y, world_seed, 233)
	var anchors: Array[Dictionary] = []
	for node in nodes:
		if str(node["kind"]) in ["rock", "ore"]:
			anchors.append(node)
	var placed: Array[Vector2] = []
	var count := 0
	for anchor in anchors:
		if count >= STONE_ID_LIMIT:
			break
		var center_at := Vector2(float(anchor["x"]), float(anchor["z"]))
		for _attempt in rng.randi_range(2, 5):
			var at: Vector2 = center_at + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(1.3, 3.7)
			if _try_add_stone(cell, origin, at, true, tier, sites, nodes, placed, rng, count):
				count += 1
	# Isolated boulders still appear when a chunk has few regular rock nodes.
	for _attempt in 3:
		if count >= STONE_ID_LIMIT:
			break
		var at := origin + Vector2(rng.randf(), rng.randf()) * Defs.CHUNK_SIZE
		if _try_add_stone(cell, origin, at, false, tier, sites, nodes, placed, rng, count):
			count += 1


func _generate_chunk(cell: Vector2i) -> Dictionary:
	var origin := cell_origin(cell)
	if Dungeon.is_underground(origin.x + Defs.CHUNK_SIZE):
		return _dungeon_chunk(cell, origin)
	var center := origin + Vector2.ONE * Defs.CHUNK_SIZE * 0.5
	var zone := zone_at(center.x, center.y)
	var tier := Defs.tier_for_distance(center.length()) if zone >= Defs.ZONE_RADII.size() else tier_for_zone(zone)
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
		var ruin_chance := 0.24 + 0.06 * zone
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
	_add_sunken_caches(cell, origin, zone, crates)
	_add_hostiles(cell, origin, zone, ruin, spawns)
	_add_groves(cell, origin, tier, nodes, sites)
	_add_outposts(cell, origin, zone, ruin, structures, crates, props, sites)
	_add_ground_pickups(cell, origin, nodes, sites)
	_add_loose_stones(cell, origin, tier, nodes, sites)
	_add_fallen_wood(cell, origin, tier, nodes, structures, crates, props, sites)
	var generated := {"cell": cell, "zone": zone, "tier": tier, "ruin": ruin, "nodes": nodes, "crates": crates, "spawns": spawns, "structures": structures, "props": props, "npcs": npcs, "pois": pois}
	if spawn_extender != null:
		spawn_extender.extend(cell, generated)
	return generated


## Large fallen trunks use the same world IDs on the server and every client.
## Slots 810..819 do not overlap loose stones (550..789), pickups (790..809),
## outposts (850+), hostiles (900+) or grove trees (960+).
const FALLEN_WOOD_ID_BASE := 810
const FALLEN_WOOD_MAX := 1


func _add_fallen_wood(cell: Vector2i, origin: Vector2, tier: int, nodes: Array,
		structures: Array, crates: Array, props: Array, sites: Array) -> void:
	var center := origin + Vector2.ONE * Defs.CHUNK_SIZE * 0.5
	if center.length() < Defs.HUB_SAFE_RADIUS + 40.0 or Dungeon.is_underground(origin.x + Defs.CHUNK_SIZE):
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = mix(cell.x, cell.y, world_seed, 149)
	if rng.randf() > 0.55:
		return
	var placed := 0
	for _attempt in 16:
		if placed >= FALLEN_WOOD_MAX:
			break
		# Keep every 5m log away from borders so adjacent chunks cannot
		# create overlapping collision on either side of a streaming seam.
		var point := origin + Vector2(rng.randf_range(6.0, Defs.CHUNK_SIZE - 6.0),
			rng.randf_range(6.0, Defs.CHUNK_SIZE - 6.0))
		if is_water(point.x, point.y) or is_safe(point.x, point.y):
			continue
		if roads != null and roads.coverage_at(point.x, point.y) > 0.0:
			continue
		var variants: Array[int] = SolidScenery.available_variants(biome_at(point.x, point.y))
		if variants.is_empty():
			continue
		var variant: int = variants[rng.randi_range(0, variants.size() - 1)]
		var scale: float = rng.randf_range(0.85, 1.15)
		var radius: float = SolidScenery.radius(variant, scale)
		var blocked := false
		for site in sites:
			if point.distance_to(Vector2(float(site["x"]), float(site["z"]))) < float(site["radius"]) + radius + 2.0:
				blocked = true
				break
		if blocked:
			continue
		for group in [nodes, structures, crates, props]:
			for obj in group:
				var clearance: float = radius + float(obj.get("radius", 0.5)) + 0.7
				if point.distance_squared_to(Vector2(float(obj["x"]), float(obj["z"]))) < clearance * clearance:
					blocked = true
					break
			if blocked:
				break
		if blocked:
			continue
		var descriptor: Dictionary = SolidScenery.MODELS[variant]
		nodes.append({
			"id": entity_id(cell, FALLEN_WOOD_ID_BASE + placed),
			"kind": str(descriptor["resource"]), "solid_model": variant,
			"x": point.x, "z": point.y, "y": height_at(point.x, point.y),
			"yaw": rng.randf() * TAU, "scale": scale, "radius": radius,
			"tier": tier, "blocks": true,
		})
		placed += 1


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


## A depleted resource has no visible mesh and must not block locomotion.
## This is updated only on a server gather/respawn or a changed client snapshot.
func set_node_depleted(node_id: int, depleted: bool) -> void:
	if depleted:
		depleted_blockers[node_id] = true
	else:
		depleted_blockers.erase(node_id)


## Snapshots replace the complete live depletion set, including corrections
## after reconnect. Copy it rather than alias mutable client state.
func sync_depleted_nodes(nodes: Dictionary) -> void:
	depleted_blockers = nodes.duplicate()


## Static things that block movement near a point, for both the server and client prediction.
func add_dynamic_blocker(id: int, x: float, z: float, radius: float) -> void:
	if is_finite(x) and is_finite(z) and is_finite(radius) and radius > 0.0:
		if _structure_parts.has(id):
			remove_dynamic_blocker(id)
		var entry: Dictionary = {"id": id, "x": x, "z": z, "radius": radius, "blocks": true}
		dynamic_blockers[id] = entry
		_dynamic_index.upsert(id, entry)


## A structure made of several circles (house walls, doorways). Tagged so house placement can
## tell pieces apart from scenery; removed together by remove_dynamic_blocker(id).
var _structure_parts: Dictionary = {}


func add_structure_blockers(id: int, circles: Array) -> void:
	remove_dynamic_blocker(id)
	var keys: Array = []
	for k in circles.size():
		var c: Array = circles[k]
		if not (is_finite(float(c[0])) and is_finite(float(c[1])) and is_finite(float(c[2])) and float(c[2]) > 0.0):
			continue
		var key := "%d:%d" % [id, k]
		var entry: Dictionary = {"id": id, "x": float(c[0]), "z": float(c[1]), "radius": float(c[2]), "blocks": true, "piece_owner": str(id)}
		dynamic_blockers[key] = entry
		_dynamic_index.upsert(key, entry)
		keys.append(key)
	_structure_parts[id] = keys


func remove_dynamic_blocker(id: int) -> void:
	dynamic_blockers.erase(id)
	_dynamic_index.remove(id)
	for key in _structure_parts.get(id, []):
		dynamic_blockers.erase(key)
		_dynamic_index.remove(key)
	_structure_parts.erase(id)


func dynamic_blocker_stats() -> Dictionary:
	return _dynamic_index.stats()


func dynamic_blocker_count() -> int:
	return dynamic_blockers.size()


func dynamic_blocker_query_candidates() -> int:
	return _dynamic_index.last_candidates


func blockers_near(x: float, z: float, radius: float) -> Array:
	var result: Array = []
	if Dungeon.is_underground(x, z):
		result = Dungeon.blockers_near(world_seed, x, z, radius)
		result.append_array(_dynamic_index.query(dynamic_blockers, x, z, radius))
		return result
	if Vector2(x, z).length() < 60.0 + radius:
		for structure in hub_structures():
			if structure["blocks"] and absf(structure["x"] - x) < radius + structure["radius"] and absf(structure["z"] - z) < radius + structure["radius"]:
				result.append(structure)
	var cell_a := cell_of(x - radius, z - radius)
	var cell_b := cell_of(x + radius, z + radius)
	for cx in range(cell_a.x, cell_b.x + 1):
		for cz in range(cell_a.y, cell_b.y + 1):
			var cell: Vector2i = Vector2i(cx, cz)
			chunk(cell) # Existing LRU keeps this tile index in sync with chunk data.
			result.append_array(StaticBlockerGrid.query(
				_static_blockers[cell], cell_origin(cell), x, z, radius,
				depleted_blockers))
	# Include built obstacles without erasing the procedural hub/terrain blockers.
	result.append_array(_dynamic_index.query(dynamic_blockers, x, z, radius))
	return result
