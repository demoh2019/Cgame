extends RefCounted
## Points of interest of the world: villages, farms, camps, depots, military outposts, watchtowers, mines, ruined cities,
## bunkers, lighthouses and docks. Everything comes from the seed, so the server and every client agree on all of it without
## a byte on the network. The world is cut into 256 m regions and each holds at most one site; a site's contents (buildings,
## walls, towers, props, loot crates, zombie packs, survivors and a workbench where people live) are built once and cached.
##
## Sites where people live (village, outpost) have a station: a workbench with a trader, usable for crafting, the vendor and
## contracts exactly like the hub's. The bank and the market stay in the hub's safe zone.

const Defs = preload("res://scripts/shared/defs.gd")

const REGION_SIZE := 256.0
const MIN_HUB_DISTANCE := 150.0
const SITE_CHANCE := 0.82
const STATION_RANGE := 6.0
const BUILDING_SCALE := 6.0
const WALL_SCALE := 3.0
const BUILDING_VARIANTS := 5

const KINDS := {
	"village": {"title": "Village", "radius": 58.0, "clear": 0.8, "station": true},
	"farm": {"title": "Farm", "radius": 44.0, "clear": 0.85, "station": false},
	"camp": {"title": "Camp", "radius": 18.0, "clear": 0.8, "station": false},
	"depot": {"title": "Depot", "radius": 34.0, "clear": 0.8, "station": false},
	"outpost": {"title": "Fort", "radius": 46.0, "clear": 0.9, "station": true},
	"tower": {"title": "Watchtower", "radius": 14.0, "clear": 0.9, "station": false},
	"mine": {"title": "Mine", "radius": 28.0, "clear": 0.6, "station": false},
	"city": {"title": "Ruins", "radius": 92.0, "clear": 0.85, "station": false},
	"bunker": {"title": "Bunker", "radius": 34.0, "clear": 0.9, "station": false},
	"lighthouse": {"title": "Lighthouse", "radius": 16.0, "clear": 0.8, "station": false},
	"dock": {"title": "Dock", "radius": 20.0, "clear": 0.7, "station": false},
}

const PREFIXES := ["Ash", "Black", "Bright", "Cold", "Crow", "Dun", "Elm", "Fair", "Grey", "Hollow", "Iron", "Kings", "Lone", "Mill", "North", "Oak", "Pine", "Raven", "Stone", "Thorn", "West", "Wolf", "Red", "Gold", "Mist", "Storm", "Rust", "Salt", "Ember", "Frost"]
const SUFFIXES := ["ford", "wick", "haven", "field", "brook", "stead", "fall", "ridge", "mere", "watch", "gate", "moor", "hollow", "port", "vale", "burn", "bridge", "rest"]
const FIRST_NAMES := ["Mara", "Tobias", "Ilya", "Nadia", "Boris", "Elena", "Marek", "Zosia", "Viktor", "Anya", "Piotr", "Katia", "Oleg", "Lena", "Jakub", "Irina", "Dmitri", "Sofia", "Anton", "Vera"]
const CHARACTERS := ["Elf_Male", "Elf_Female", "Orc_Male", "Orc_Female"]
const ROLES := {
	"trader": {"title": "Trader", "animation": "Idle_Talking_Loop"},
	"guard": {"title": "Guard", "animation": "Idle_FoldArms_Loop"},
	"villager": {"title": "Villager", "animation": "Idle_Talking_Loop"},
	"farmer": {"title": "Farmer", "animation": "Farm_Harvest"},
	"sitter": {"title": "Survivor", "animation": "Sitting_Idle_Loop"},
	"watch": {"title": "Lookout", "animation": "Idle_Lantern_Loop"},
	"miner": {"title": "Miner", "animation": "Fixing_Kneeling"},
	"fisher": {"title": "Fisher", "animation": "Idle_Rail_Loop"},
}
const PROP_VARIANTS := 6 # barrel, crate, bench, table, basket, stool: see Assets.PROP_FILES.

var world
var _regions: Dictionary = {}
var _leveller_cache: Dictionary = {}


func _init(p_world) -> void:
	world = p_world


# --- Sites -------------------------------------------------------------------------------------------------------

func sites_in_region(rx: int, rz: int) -> Array:
	var key := Vector2i(rx, rz)
	if not _regions.has(key):
		_regions[key] = _build_region(rx, rz)
	return _regions[key]


## Every site whose area may touch a circle: for chunk generation, map markers and the HUD.
func sites_near(x: float, z: float, radius: float) -> Array:
	var result: Array = []
	var margin: float = radius + 100.0
	for rx in range(int(floor((x - margin) / REGION_SIZE)), int(floor((x + margin) / REGION_SIZE)) + 1):
		for rz in range(int(floor((z - margin) / REGION_SIZE)), int(floor((z + margin) / REGION_SIZE)) + 1):
			for site in sites_in_region(rx, rz):
				if Vector2(float(site["x"]) - x, float(site["z"]) - z).length() <= radius + float(site["radius"]):
					result.append(site)
	return result


## The site whose area covers a point, or {}.
func site_at(x: float, z: float) -> Dictionary:
	for site in sites_near(x, z, 0.0):
		if Vector2(float(site["x"]) - x, float(site["z"]) - z).length() <= float(site["radius"]):
			return site
	return {}


## Whether a workbench station of any settlement is within `reach` of a point.
func station_near(x: float, z: float, reach: float = STATION_RANGE) -> bool:
	for site in sites_near(x, z, reach):
		if bool(site["station"]) and Vector2(float(site["station_x"]) - x, float(site["station_z"]) - z).length() <= reach:
			return true
	return false


## Sites that level some ground inside a region: its own and those of the neighbours that reach over the border.
## Sites that level ground inside a region, as light records for the terrain hot path: {x, z, y, inner, outer}: full level out
## to `inner`, a smooth ramp to `outer`.
func levellers(rx: int, rz: int) -> Array:
	var key := Vector2i(rx, rz)
	if _leveller_cache.has(key):
		return _leveller_cache[key]
	var list: Array = []
	var region_rect := Rect2(Vector2(rx, rz) * REGION_SIZE, Vector2.ONE * REGION_SIZE)
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			for site in sites_in_region(rx + dx, rz + dz):
				var reach: float = float(site["radius"]) * 1.15
				if region_rect.grow(reach).has_point(Vector2(float(site["x"]), float(site["z"]))):
					list.append({"x": float(site["x"]), "z": float(site["z"]), "y": float(site["y"]), "inner": float(site["radius"]) * 0.6, "outer": reach})
	_leveller_cache[key] = list
	return list


func _build_region(rx: int, rz: int) -> Array:
	world.poi_building = true
	var found: Array = _find_site(rx, rz)
	world.poi_building = false
	return found


func _find_site(rx: int, rz: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = world.mix(rx, rz, world.world_seed, 71)
	if rng.randf() > SITE_CHANCE:
		return []
	var origin := Vector2(rx, rz) * REGION_SIZE
	for attempt in 14:
		var p := origin + Vector2(rng.randf_range(54.0, REGION_SIZE - 54.0), rng.randf_range(54.0, REGION_SIZE - 54.0))
		var hub_distance: float = p.length()
		if hub_distance < MIN_HUB_DISTANCE or hub_distance > world.WORLD_RADIUS - 220.0 or world.is_water(p.x, p.y):
			continue
		var zone: int = world.zone_at(p.x, p.y)
		var biome: String = world.biome_at(p.x, p.y)
		var kind: String = _pick_kind(zone, biome, _near_water(p), rng)
		var radius: float = float(KINDS[kind]["radius"])
		if not _flat_and_dry(p, minf(radius, 26.0), 10.0 if kind != "lighthouse" and kind != "dock" else 40.0):
			continue
		var site_seed: int = world.mix(rx, rz, world.world_seed, 73)
		var name := _place_name(site_seed)
		var station_offset := Vector2(3.5, 0.0)
		return [{
			"id": site_seed % 10000000, "kind": kind, "name": name, "title": KINDS[kind]["title"],
			"display": _display_name(kind, name), "x": p.x, "z": p.y, "y": world.height_at(p.x, p.y),
			"radius": radius, "clear": float(KINDS[kind]["clear"]) * radius, "zone": zone, "biome": biome,
			"station": bool(KINDS[kind]["station"]), "station_x": p.x + station_offset.x, "station_z": p.y + station_offset.y,
			"seed": site_seed,
		}]
	return []


func _near_water(p: Vector2) -> bool:
	for i in 8:
		if world.is_water(p.x + cos(float(i) * TAU / 8.0) * 45.0, p.y + sin(float(i) * TAU / 8.0) * 45.0):
			return true
	return false


## A site needs dry ground and a reasonably level surface. `spread` is the height difference tolerated within `radius`.
func _flat_and_dry(p: Vector2, radius: float, spread: float) -> bool:
	var low: float = world.height_at(p.x, p.y)
	var high: float = low
	if low < Defs.WATER_LEVEL + 1.0:
		return false
	for i in 8:
		var q := p + Vector2.from_angle(float(i) * TAU / 8.0) * radius
		var h: float = world.height_at(q.x, q.y)
		if h < Defs.WATER_LEVEL + (-3.0 if spread > 10.0 else 0.4):
			return false
		low = minf(low, h)
		high = maxf(high, h)
	return high - low <= spread


func _pick_kind(zone: int, biome: String, coastal: bool, rng: RandomNumberGenerator) -> String:
	var weights: Dictionary = {}
	match zone:
		0:
			weights = {"village": 5.0, "farm": 3.0, "camp": 2.0}
		1:
			weights = {"village": 3.0, "farm": 2.0, "camp": 3.0, "depot": 2.0, "tower": 1.5}
		2:
			weights = {"outpost": 3.0, "depot": 2.0, "camp": 2.0, "city": 3.0, "tower": 2.0, "village": 3.0, "farm": 1.5}
		_:
			weights = {"city": 4.0, "bunker": 3.0, "outpost": 2.5, "camp": 1.0, "tower": 1.0, "depot": 1.0, "village": 3.5, "farm": 2.0}
	if biome == "mountain":
		weights["mine"] = 9.0
	if coastal and (biome == "beach" or biome == "plains" or biome == "forest"):
		weights["lighthouse"] = 1.2
		weights["dock"] = 2.0
	var total := 0.0
	for kind in weights:
		total += float(weights[kind])
	var roll: float = rng.randf() * total
	for kind in weights:
		roll -= float(weights[kind])
		if roll <= 0.0:
			return kind
	return "camp"


func _place_name(site_seed: int) -> String:
	var prefix: String = PREFIXES[site_seed % PREFIXES.size()]
	var suffix: String = SUFFIXES[(site_seed / 31) % SUFFIXES.size()]
	return prefix + suffix


static func _display_name(kind: String, name: String) -> String:
	match kind:
		"outpost":
			return "Fort " + name
		"city":
			return "Ruins of " + name
		_:
			return "%s %s" % [name, KINDS[kind]["title"]]


# --- Contents ------------------------------------------------------------------------------------------------------

## Buildings, walls, towers, props, crates, zombie packs, ore and survivors of a site, in world coordinates and without
## ids (the chunk that holds an item gives it one). Built once.
func contents(site: Dictionary) -> Dictionary:
	if site.has("contents"):
		return site["contents"]
	var rng := RandomNumberGenerator.new()
	rng.seed = int(site["seed"]) ^ 0x5bd1e995
	var center := Vector2(float(site["x"]), float(site["z"]))
	var kind: String = site["kind"]
	var zone: int = int(site["zone"])
	var result := {"structures": [], "crates": [], "spawns": [], "props": [], "npcs": [], "nodes": []}
	var taken: Array[Vector2] = []
	match kind:
		"village":
			_station(result, site)
			_houses(result, rng, center, rng.randi_range(6, 9), 20.0, 46.0, 12.0, taken)
			_fences(result, rng, center, rng.randi_range(3, 5), 48.0, 54.0)
			_crates(result, rng, center, rng.randi_range(2, 4), 8.0, 36.0, taken)
			_props(result, rng, center, rng.randi_range(12, 18), 6.0, 36.0)
			_npcs(result, rng, site, [["guard", 2], ["villager", 3], ["farmer", 1]], 6.0, 26.0)
			_zombies(result, rng, center, rng.randi_range(0, 1) if zone == 0 else rng.randi_range(1, 3), 62.0, 80.0, zone, false)
		"farm":
			_houses(result, rng, center, rng.randi_range(2, 3), 12.0, 24.0, 12.0, taken)
			_ring_walls(result, rng, center, 33.0, 0.7)
			_crates(result, rng, center, rng.randi_range(1, 2), 6.0, 24.0, taken)
			_props(result, rng, center, rng.randi_range(10, 14), 4.0, 28.0)
			_npcs(result, rng, site, [["farmer", 2], ["villager", 1]], 8.0, 26.0)
			_zombies(result, rng, center, rng.randi_range(0, 2), 48.0, 62.0, zone, false)
		"camp":
			_houses(result, rng, center, rng.randi_range(2, 3), 6.0, 11.0, 9.0, taken, 4.0, 3)
			_crates(result, rng, center, rng.randi_range(1, 2), 3.0, 9.0, taken)
			_props(result, rng, center, rng.randi_range(6, 9), 2.0, 12.0)
			_npcs(result, rng, site, [["sitter", 2], ["watch", 1]], 2.5, 7.0)
			_zombies(result, rng, center, rng.randi_range(1, 3), 22.0, 40.0, zone, false)
		"depot":
			_houses(result, rng, center, 2, 12.0, 20.0, 18.0, taken, 9.0)
			_ring_walls(result, rng, center, 28.0, 0.55)
			_crates(result, rng, center, rng.randi_range(4, 6), 5.0, 22.0, taken)
			_props(result, rng, center, rng.randi_range(10, 14), 4.0, 24.0)
			_zombies(result, rng, center, rng.randi_range(3, 5) + zone, 5.0, 30.0, zone, true)
		"outpost":
			_station(result, site)
			_ring_walls(result, rng, center, 31.0, 0.78)
			_towers(result, center, [Vector2(-31.0, -31.0), Vector2(31.0, 31.0)])
			_houses(result, rng, center, 2, 9.0, 18.0, 12.0, taken)
			_crates(result, rng, center, rng.randi_range(3, 5), 5.0, 24.0, taken)
			_props(result, rng, center, rng.randi_range(8, 12), 4.0, 26.0)
			_npcs(result, rng, site, [["guard", 4]], 6.0, 22.0)
			_zombies(result, rng, center, rng.randi_range(3, 5), 40.0, 58.0, zone, false)
		"tower":
			_towers(result, center, [Vector2.ZERO])
			_crates(result, rng, center, 1, 3.0, 7.0, taken)
			_props(result, rng, center, rng.randi_range(3, 5), 3.0, 9.0)
			_zombies(result, rng, center, rng.randi_range(1, 3), 5.0, 14.0, zone, true)
		"mine":
			_houses(result, rng, center, rng.randi_range(1, 2), 8.0, 14.0, 10.0, taken, 5.0)
			_crates(result, rng, center, 2, 5.0, 14.0, taken)
			_props(result, rng, center, rng.randi_range(5, 8), 4.0, 16.0)
			_ore(result, rng, center, rng.randi_range(6, 9), 12.0, 24.0, zone)
			_npcs(result, rng, site, [["miner", 2]], 5.0, 11.0)
			_zombies(result, rng, center, rng.randi_range(2, 4), 6.0, 24.0, zone, true)
		"city":
			_houses(result, rng, center, rng.randi_range(14, 22), 14.0, 80.0, 12.0, taken)
			_fences(result, rng, center, rng.randi_range(8, 14), 10.0, 82.0)
			_crates(result, rng, center, rng.randi_range(6, 10), 8.0, 64.0, taken)
			_props(result, rng, center, rng.randi_range(20, 30), 6.0, 70.0)
			_zombies(result, rng, center, rng.randi_range(8, 14) + zone, 8.0, 70.0, zone, true)
		"bunker":
			_ring_walls(result, rng, center, 24.0, 0.85)
			_towers(result, center, [Vector2(-20.0, 0.0), Vector2(20.0, 0.0)] if rng.randf() < 0.5 else [Vector2(0.0, 0.0)])
			_houses(result, rng, center, rng.randi_range(1, 2), 8.0, 15.0, 12.0, taken)
			_crates(result, rng, center, rng.randi_range(5, 7), 3.0, 18.0, taken)
			_props(result, rng, center, rng.randi_range(6, 10), 3.0, 20.0)
			_zombies(result, rng, center, rng.randi_range(6, 9) + zone, 4.0, 28.0, zone, true)
		"lighthouse":
			_towers(result, center, [Vector2.ZERO], 1.5)
			_houses(result, rng, center, 1, 8.0, 11.0, 8.0, taken, 5.0)
			_crates(result, rng, center, 1, 4.0, 9.0, taken)
			_props(result, rng, center, rng.randi_range(3, 5), 3.0, 11.0)
			_npcs(result, rng, site, [["watch", 1]], 4.0, 7.0)
			_zombies(result, rng, center, rng.randi_range(0, 2), 12.0, 26.0, zone, false)
		"dock":
			_houses(result, rng, center, 2, 7.0, 14.0, 10.0, taken, 5.0)
			_crates(result, rng, center, 2, 4.0, 12.0, taken)
			_props(result, rng, center, rng.randi_range(6, 8), 3.0, 14.0)
			_npcs(result, rng, site, [["fisher", 1], ["villager", 1]], 4.0, 12.0)
			_zombies(result, rng, center, rng.randi_range(0, 2), 14.0, 28.0, zone, false)
	site["contents"] = result
	return result


func _ground(p: Vector2) -> float:
	return world.height_at(p.x, p.y)


func _usable(p: Vector2, taken: Array, spacing: float) -> bool:
	if world.is_water(p.x, p.y) or p.length() < Defs.HUB_SAFE_RADIUS + 12.0:
		return false
	for q in taken:
		if q.distance_to(p) < spacing:
			return false
	return true


func _station(result: Dictionary, site: Dictionary) -> void:
	var p := Vector2(float(site["station_x"]), float(site["station_z"]))
	result["structures"].append({"kind": "workbench", "variant": 0, "scale": 1.0, "x": p.x, "z": p.y, "y": _ground(p), "yaw": 0.0, "radius": 0.9, "blocks": true})
	var trader_spot := p + Vector2(-2.2, 1.6)
	_add_npc(result, site, "trader", trader_spot, p, int(site["seed"]) + 11)


func _houses(result: Dictionary, rng: RandomNumberGenerator, center: Vector2, count: int, rmin: float, rmax: float, spacing: float, taken: Array, scale: float = BUILDING_SCALE, variant_limit: int = BUILDING_VARIANTS) -> void:
	var placed := 0
	for attempt in count * 14:
		if placed >= count:
			break
		var p := center + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(rmin, rmax)
		if not _usable(p, taken, spacing):
			continue
		taken.append(p)
		placed += 1
		# Houses in a settlement face the centre; ruins sit at any angle.
		var yaw: float = -atan2(p.y - center.y, p.x - center.x) + PI * 0.5 + rng.randf_range(-0.35, 0.35)
		result["structures"].append({"kind": "building", "variant": rng.randi_range(0, variant_limit - 1), "scale": scale, "x": p.x, "z": p.y, "y": _ground(p), "yaw": yaw, "radius": scale * 0.62, "blocks": true})


func _fences(result: Dictionary, rng: RandomNumberGenerator, center: Vector2, count: int, rmin: float, rmax: float) -> void:
	for i in count:
		var p := center + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(rmin, rmax)
		if world.is_water(p.x, p.y):
			continue
		result["structures"].append({"kind": "wall", "variant": 0, "scale": WALL_SCALE, "x": p.x, "z": p.y, "y": _ground(p), "yaw": rng.randf() * PI, "radius": WALL_SCALE * 0.6, "blocks": true})


## A fence or palisade round a site with a few gaps for the way in.
func _ring_walls(result: Dictionary, rng: RandomNumberGenerator, center: Vector2, radius: float, coverage: float) -> void:
	var segments: int = int(TAU * radius / 3.6)
	var gap_a: float = rng.randf() * TAU
	var gap_b: float = gap_a + PI
	for i in segments:
		var angle: float = TAU * float(i) / float(segments)
		if absf(wrapf(angle - gap_a, -PI, PI)) < 0.2 or absf(wrapf(angle - gap_b, -PI, PI)) < 0.2:
			continue
		if rng.randf() > coverage:
			continue
		var p := center + Vector2.from_angle(angle) * radius
		if world.is_water(p.x, p.y):
			continue
		result["structures"].append({"kind": "wall", "variant": 0, "scale": WALL_SCALE, "x": p.x, "z": p.y, "y": _ground(p), "yaw": -angle + PI * 0.5, "radius": WALL_SCALE * 0.6, "blocks": true})


func _towers(result: Dictionary, center: Vector2, offsets: Array, height_scale: float = 1.0) -> void:
	for offset in offsets:
		var p: Vector2 = center + offset
		if world.is_water(p.x, p.y):
			continue
		result["structures"].append({"kind": "tower", "variant": 0, "scale": 5.0 * height_scale, "x": p.x, "z": p.y, "y": _ground(p), "yaw": 0.0, "radius": 2.4, "blocks": true})


func _crates(result: Dictionary, rng: RandomNumberGenerator, center: Vector2, count: int, rmin: float, rmax: float, taken: Array) -> void:
	for attempt in count * 10:
		if result["crates"].size() >= count:
			break
		var p := center + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(rmin, rmax)
		if not _usable(p, taken, 4.5):
			continue
		taken.append(p)
		result["crates"].append({"kind": "crate", "x": p.x, "z": p.y, "y": _ground(p), "radius": 0.6, "blocks": true})


func _props(result: Dictionary, rng: RandomNumberGenerator, center: Vector2, count: int, rmin: float, rmax: float) -> void:
	for i in count:
		var p := center + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(rmin, rmax)
		if world.is_water(p.x, p.y) or p.length() < Defs.HUB_SAFE_RADIUS + 8.0:
			continue
		result["props"].append({"kind": "prop", "variant": rng.randi_range(0, PROP_VARIANTS - 1), "x": p.x, "z": p.y, "y": _ground(p), "yaw": rng.randf() * TAU, "scale": 1.5, "radius": 0.45, "blocks": true})


func _ore(result: Dictionary, rng: RandomNumberGenerator, center: Vector2, count: int, rmin: float, rmax: float, zone: int) -> void:
	var info: Dictionary = Defs.node_info("ore")
	for i in count:
		var p := center + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(rmin, rmax)
		if world.is_water(p.x, p.y):
			continue
		result["nodes"].append({"kind": "ore", "tier": clampi(zone + 1, 1, Defs.MAX_TIER), "x": p.x, "z": p.y, "y": _ground(p), "radius": info["radius"], "blocks": info["blocks"]})


func _zombies(result: Dictionary, rng: RandomNumberGenerator, center: Vector2, count: int, rmin: float, rmax: float, zone: int, ruin: bool) -> void:
	for i in count:
		var p := center + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(rmin, rmax)
		if world.is_water(p.x, p.y):
			continue
		result["spawns"].append({"x": p.x, "z": p.y, "type": world._pick_zombie(zone, rng), "ruin": ruin})


func _npcs(result: Dictionary, rng: RandomNumberGenerator, site: Dictionary, wanted: Array, rmin: float, rmax: float) -> void:
	var center := Vector2(float(site["x"]), float(site["z"]))
	var serial := 0
	for entry in wanted:
		for i in int(entry[1]):
			var p := center + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(rmin, rmax)
			if world.is_water(p.x, p.y):
				continue
			serial += 1
			_add_npc(result, site, str(entry[0]), p, center, int(site["seed"]) + serial * 7)


func _add_npc(result: Dictionary, site: Dictionary, role: String, p: Vector2, face: Vector2, salt: int) -> void:
	var name: String = FIRST_NAMES[world.mix(salt, 3, 5) % FIRST_NAMES.size()]
	result["npcs"].append({
		"role": role, "title": ROLES[role]["title"], "name": name, "animation": ROLES[role]["animation"],
		"model": CHARACTERS[world.mix(salt, 9, 2) % CHARACTERS.size()],
		"x": p.x, "z": p.y, "y": _ground(p), "yaw": atan2(face.x - p.x, face.y - p.y),
	})
