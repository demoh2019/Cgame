extends RefCounted
## Points of interest of the world: villages, farms, camps, depots, military outposts, watchtowers, mines, ruined cities,
## bunkers, lighthouses and docks. Everything comes from the seed, so the server and every client agree on all of it without
## a byte on the network. The world is cut into 256 m regions and each holds at most one site; a site's contents (buildings,
## walls, towers, props, loot crates, zombie packs, survivors and a workbench where people live) are built once and cached.
##
## Sites where people live (village, outpost) have a station: a workbench with a trader, usable for crafting, the vendor and
## contracts exactly like the hub's. The bank and the market stay in the hub's safe zone.

const Defs = preload("res://scripts/shared/defs.gd")
const CityLayout = preload("res://scripts/shared/city_layout.gd")

const REGION_SIZE := 256.0
const MIN_HUB_DISTANCE := 150.0
const SITE_CHANCE := 0.82
const STATION_RANGE := 6.0
const BUILDING_SCALE := 6.0
const WALL_SCALE := 3.0
const BUILDING_VARIANTS := 9 # Models of the client's HOUSES list; the client takes variant % installed models.
const TOWN_CENTER_VARIANT := 7 # The big building in the middle of a village (not drawn at random for ordinary houses).
const TOWER_VARIANTS := 3 # Watchtower, round tower, tall coastal tower.
const WALL_WOOD := 2 # Palisade of villages, farms and camps.
const WALL_STONE := 1 # Fort wall.

# What blocks movement, per variant, of the client's PROPS and RUINS lists (the server never loads a model): a test checks
# that these tables and the lists in model_catalog.gd have the same length.
const PROP_RADII := [0.45, 0.45, 0.6, 0.6, 0.35, 0.3, 0.5, 0.5, 0.6, 2.4, 0.4, 0.7, 0.9, 0.7, 0.8, 0.5, 0.9, 0.2, 1.0, 0.9, 0.8, 0.45, 1.5, 0.25, 0.25, 1.3, 0.45, 0.45, 0.5, 0.25, 0.25, 0.6, 0.55, 0.25, 0.4, 0.3, 1.1, 0.4, 0.35, 0.35, 0.5, 0.3, 0.25, 0.9, 0.25, 0.3, 0.45, 0.8, 0.5, 0.6, 0.5, 0.6, 0.8, 0.8, 0.4, 0.5]
const RUIN_RADII := [0.8, 0.8, 1.8, 1.8, 1.1, 2.6, 1.6, 0.5, 1.9, 2.2,
	1.8, 1.8, 0.9, 1.2, 2.4, 2.4, 2.2, 2.2, 1.5, 1.6, 1.8, 1.4, 0.8, 0.7, 2.0, 2.6, 1.2, 1.8, 1.8, 0.7, 1.0, 2.0, 1.6, 1.7, 1.7]
const CRATE_VARIANTS := 6
# Landmarks fill the regions that hold no settlement: odd, memorable places to find. Their big pieces are "monument"
# structures; the client's MONUMENTS list draws them (standing stone, giant crystal, great tree, shrine pillar).
const MONUMENT_RADII := [1.1, 1.3, 2.6, 0.9]
const LANDMARKS := [
	{"title": "Stone Circle"}, {"title": "Crystal Grove"}, {"title": "Great Tree"}, {"title": "Old Shrine"}, {"title": "Battlefield"},
]
const LANDMARK_CHANCE := 0.85
# Which props belong where. Indices into PROP_RADII.
const RUSTIC_PROPS := [0, 1, 2, 3, 4, 5, 6, 7, 8, 11, 12, 20, 21, 22, 23, 24, 43, 46, 49, 45, 29, 28, 50, 51, 52, 53, 54, 55]
const MARKET_PROPS := [9, 10, 8, 16, 11, 25, 22, 43, 46, 44, 49, 51, 52, 50]
const MILITARY_PROPS := [6, 7, 13, 14, 15, 17, 8, 20, 22, 31, 32, 33, 30, 39, 40, 36, 26, 27, 47]
const RUIN_PROPS := [13, 14, 15, 16, 19, 12, 0, 1, 26, 27, 28, 34, 35, 36, 37, 38, 41, 42, 45, 47, 48, 29, 44]

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
	"landmark": {"title": "Landmark", "radius": 24.0, "clear": 0.85, "station": false},
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
		return _find_landmark(rx, rz)
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
		var site: Dictionary = {
			"id": site_seed % 10000000, "kind": kind, "name": name, "title": KINDS[kind]["title"],
			"display": _display_name(kind, name), "x": p.x, "z": p.y, "y": world.height_at(p.x, p.y),
			"radius": radius, "clear": float(KINDS[kind]["clear"]) * radius, "zone": zone, "biome": biome,
			"station": bool(KINDS[kind]["station"]), "station_x": p.x + station_offset.x, "station_z": p.y + station_offset.y,
			"seed": site_seed,
		}
		if kind == "city":
			site["layout"] = CityLayout.layout_for_seed(site_seed)
			site["layout_rotation"] = CityLayout.rotation_for_seed(site_seed)
		return [site]
	return _find_landmark(rx, rz)


## A landmark for a region without a settlement. Its own random stream, so the settlements of other regions never move.
func _find_landmark(rx: int, rz: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = world.mix(rx, rz, world.world_seed, 79)
	if rng.randf() > LANDMARK_CHANCE:
		return []
	var origin := Vector2(rx, rz) * REGION_SIZE
	for attempt in 12:
		var p := origin + Vector2(rng.randf_range(40.0, REGION_SIZE - 40.0), rng.randf_range(40.0, REGION_SIZE - 40.0))
		var hub_distance: float = p.length()
		if hub_distance < MIN_HUB_DISTANCE or hub_distance > world.WORLD_RADIUS - 220.0 or world.is_water(p.x, p.y):
			continue
		if not _flat_and_dry(p, 18.0, 9.0):
			continue
		var zone: int = world.zone_at(p.x, p.y)
		var biome: String = world.biome_at(p.x, p.y)
		var variant: int = _pick_landmark(zone, biome, rng)
		var site_seed: int = world.mix(rx, rz, world.world_seed, 81)
		var name := _place_name(site_seed)
		var title: String = LANDMARKS[variant]["title"]
		var radius: float = float(KINDS["landmark"]["radius"])
		return [{
			"id": site_seed % 10000000, "kind": "landmark", "variant": variant, "name": name, "title": title,
			"display": "%s %s" % [name, title], "x": p.x, "z": p.y, "y": world.height_at(p.x, p.y),
			"radius": radius, "clear": float(KINDS["landmark"]["clear"]) * radius, "zone": zone, "biome": biome,
			"station": false, "station_x": p.x, "station_z": p.y, "seed": site_seed,
		}]
	return []


func _pick_landmark(zone: int, biome: String, rng: RandomNumberGenerator) -> int:
	var weights := {0: 3.0, 3: 2.0}
	if biome == "forest" or biome == "plains" or biome == "swamp":
		weights[2] = 4.0
	if biome == "mountain" or zone >= 1:
		weights[1] = 3.5 if biome == "mountain" else 1.5
	if zone >= 2:
		weights[4] = 3.0
	var total := 0.0
	for key in weights:
		total += float(weights[key])
	var roll: float = rng.randf() * total
	for key in weights:
		roll -= float(weights[key])
		if roll <= 0.0:
			return int(key)
	return 0


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
			_town_center(result, rng, center, 13.0, 19.0, taken)
			_houses(result, rng, center, rng.randi_range(6, 9), 22.0, 48.0, 12.0, taken)
			if rng.randf() < 0.6:
				_windmill(result, rng, center, 30.0, 50.0, taken)
			_fences(result, rng, center, rng.randi_range(5, 8), 50.0, 56.0, [WALL_WOOD, WALL_WOOD, 3])
			_crates(result, rng, center, rng.randi_range(2, 4), 8.0, 36.0, taken)
			_props(result, rng, center, rng.randi_range(12, 18), 6.0, 36.0)
			_props(result, rng, center, rng.randi_range(3, 5), 5.0, 22.0, MARKET_PROPS)
			_npcs(result, rng, site, [["guard", 2], ["villager", 3], ["farmer", 1]], 6.0, 26.0)
			_zombies(result, rng, center, rng.randi_range(0, 1) if zone == 0 else rng.randi_range(1, 3), 62.0, 80.0, zone, false)
		"farm":
			_houses(result, rng, center, rng.randi_range(2, 3), 12.0, 24.0, 12.0, taken)
			_windmill(result, rng, center, 8.0, 24.0, taken)
			_ring_walls(result, rng, center, 33.0, 0.7, [WALL_WOOD, 3])
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
			_ring_walls(result, rng, center, 28.0, 0.55, [WALL_STONE, 4])
			_crates(result, rng, center, rng.randi_range(4, 6), 5.0, 22.0, taken)
			_props(result, rng, center, rng.randi_range(10, 14), 4.0, 24.0, MILITARY_PROPS)
			_zombies(result, rng, center, rng.randi_range(3, 5) + zone, 5.0, 30.0, zone, true)
		"outpost":
			_station(result, site)
			_ring_walls(result, rng, center, 31.0, 0.78, [WALL_STONE, WALL_STONE, 4, 0])
			_towers(result, center, [Vector2(-31.0, -31.0), Vector2(31.0, 31.0), Vector2(-31.0, 31.0), Vector2(31.0, -31.0)], 1.0, 1)
			_town_center(result, rng, center, 9.0, 14.0, taken)
			_houses(result, rng, center, 2, 16.0, 24.0, 12.0, taken)
			_crates(result, rng, center, rng.randi_range(3, 5), 5.0, 24.0, taken)
			_props(result, rng, center, rng.randi_range(8, 12), 4.0, 26.0, MILITARY_PROPS)
			_npcs(result, rng, site, [["guard", 4]], 6.0, 22.0)
			_zombies(result, rng, center, rng.randi_range(3, 5), 40.0, 58.0, zone, false)
		"tower":
			_towers(result, center, [Vector2.ZERO], 1.0, 0)
			_crates(result, rng, center, 1, 3.0, 7.0, taken)
			_props(result, rng, center, rng.randi_range(3, 5), 3.0, 9.0, MILITARY_PROPS)
			_zombies(result, rng, center, rng.randi_range(1, 3), 5.0, 14.0, zone, true)
		"mine":
			_houses(result, rng, center, rng.randi_range(1, 2), 8.0, 14.0, 10.0, taken, 5.0)
			_crates(result, rng, center, 2, 5.0, 14.0, taken)
			_props(result, rng, center, rng.randi_range(5, 8), 4.0, 16.0)
			_ore(result, rng, center, rng.randi_range(6, 9), 12.0, 24.0, zone)
			_npcs(result, rng, site, [["miner", 2]], 5.0, 11.0)
			_zombies(result, rng, center, rng.randi_range(2, 4), 6.0, 24.0, zone, true)
		"city":
			_city_buildings(result, rng, site, center, taken)
			_ruin_bits(result, rng, center, rng.randi_range(24, 36), 8.0, 84.0, taken)
			_fences(result, rng, center, rng.randi_range(8, 14), 10.0, 82.0, [WALL_STONE, 4, 0])
			_crates(result, rng, center, rng.randi_range(6, 10), 8.0, 64.0, taken)
			_props(result, rng, center, rng.randi_range(20, 30), 6.0, 70.0, RUIN_PROPS)
			_zombies(result, rng, center, rng.randi_range(8, 14) + zone, 8.0, 70.0, zone, true)
			_trim_city_footprint(result, center, str(site["layout"]), float(site["layout_rotation"]), float(site["radius"]))
		"bunker":
			_ring_walls(result, rng, center, 24.0, 0.85, [WALL_STONE, 4])
			_towers(result, center, [Vector2(-20.0, 0.0), Vector2(20.0, 0.0)] if rng.randf() < 0.5 else [Vector2(0.0, 0.0)], 1.0, 1)
			_houses(result, rng, center, rng.randi_range(1, 2), 8.0, 15.0, 12.0, taken)
			_ruin_bits(result, rng, center, rng.randi_range(5, 9), 6.0, 26.0, taken)
			_crates(result, rng, center, rng.randi_range(5, 7), 3.0, 18.0, taken)
			_props(result, rng, center, rng.randi_range(6, 10), 3.0, 20.0, MILITARY_PROPS)
			_zombies(result, rng, center, rng.randi_range(6, 9) + zone, 4.0, 28.0, zone, true)
		"lighthouse":
			_towers(result, center, [Vector2.ZERO], 1.5, 2)
			_houses(result, rng, center, 1, 8.0, 11.0, 8.0, taken, 5.0)
			_crates(result, rng, center, 1, 4.0, 9.0, taken)
			_props(result, rng, center, rng.randi_range(3, 5), 3.0, 11.0)
			_npcs(result, rng, site, [["watch", 1]], 4.0, 7.0)
			_zombies(result, rng, center, rng.randi_range(0, 2), 12.0, 26.0, zone, false)
		"landmark":
			_landmark(result, rng, site, center, zone, taken)
		"dock":
			_houses(result, rng, center, 2, 7.0, 14.0, 10.0, taken, 5.0)
			_crates(result, rng, center, 2, 4.0, 12.0, taken)
			_props(result, rng, center, rng.randi_range(6, 8), 3.0, 14.0)
			_npcs(result, rng, site, [["fisher", 1], ["villager", 1]], 4.0, 12.0)
			_zombies(result, rng, center, rng.randi_range(0, 2), 14.0, 28.0, zone, false)
	site["contents"] = result
	return result


## City buildings follow the seeded district plan, leaving actual room for painted streets.
func _city_buildings(result: Dictionary, rng: RandomNumberGenerator, site: Dictionary, center: Vector2, taken: Array) -> void:
	var layout: String = str(site["layout"])
	var rotation: float = float(site["layout_rotation"])
	var candidates: Array[Dictionary] = CityLayout.building_lots(int(site["seed"]), layout, float(site["radius"]), rotation)
	var wanted: int = rng.randi_range(14, 22)
	var placed := 0
	for lot in candidates:
		if placed >= wanted:
			break
		var p: Vector2 = center + Vector2(lot["offset"])
		if not _usable(p, taken, 12.0):
			continue
		taken.append(p)
		placed += 1
		var yaw: float = float(lot["yaw"]) + rng.randf_range(-0.12, 0.12)
		result["structures"].append({"kind": "building", "variant": _house_variant(rng, BUILDING_VARIANTS - 1),
			"scale": BUILDING_SCALE, "x": p.x, "z": p.y, "y": _ground(p), "yaw": yaw,
			"radius": BUILDING_SCALE * 0.62, "blocks": true})


## Keep rubble, loot and enemies inside the same footprint as the city blocks.
func _trim_city_footprint(result: Dictionary, center: Vector2, layout: String, rotation: float, radius: float) -> void:
	for group in ["structures", "crates", "props", "spawns"]:
		var inside: Array = []
		for item in result[group]:
			var offset := Vector2(float(item["x"]), float(item["z"])) - center
			if CityLayout.contains(offset, layout, radius, rotation):
				inside.append(item)
		result[group] = inside


func _house_variant(rng: RandomNumberGenerator, limit: int) -> int:
	var variant: int = rng.randi_range(0, mini(limit, BUILDING_VARIANTS - 1) - 1)
	return variant + 1 if variant >= TOWN_CENTER_VARIANT and limit > TOWN_CENTER_VARIANT else variant


func _ground(p: Vector2) -> float:
	return world.height_at(p.x, p.y)


func _usable(p: Vector2, taken: Array, spacing: float) -> bool:
	if world.is_water(p.x, p.y) or p.length() < Defs.HUB_SAFE_RADIUS + 12.0:
		return false
	for q in taken:
		if q.distance_to(p) < spacing:
			return false
	return true


func _monument(result: Dictionary, p: Vector2, variant: int, yaw: float) -> void:
	result["structures"].append({"kind": "monument", "variant": variant, "scale": 1.0, "x": p.x, "z": p.y, "y": _ground(p), "yaw": yaw, "radius": MONUMENT_RADII[variant], "blocks": true})


func _landmark(result: Dictionary, rng: RandomNumberGenerator, site: Dictionary, center: Vector2, zone: int, taken: Array) -> void:
	match int(site.get("variant", 0)):
		0: # Stone circle: standing stones in a ring round an offering chest.
			var stones: int = rng.randi_range(7, 9)
			for i in stones:
				var angle: float = TAU * float(i) / float(stones)
				var p: Vector2 = center + Vector2.from_angle(angle) * 11.0
				taken.append(p)
				_monument(result, p, 0, -angle)
			taken.append(center)
			result["crates"].append({"kind": "crate", "variant": 1, "x": center.x, "z": center.y, "y": _ground(center), "radius": 0.6, "blocks": true})
			_props(result, rng, center, 2, 4.0, 6.0, [8])
			_zombies(result, rng, center, 0 if zone == 0 else rng.randi_range(1, 3), 17.0, 26.0, zone, false)
		1: # Crystal grove: giant crystals and crystal ore to mine.
			for i in rng.randi_range(6, 9):
				var p: Vector2 = center + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(3.0, 15.0)
				if _usable(p, taken, 4.0):
					taken.append(p)
					_monument(result, p, 1, rng.randf() * TAU)
			_ore(result, rng, center, rng.randi_range(5, 7), 4.0, 19.0, zone)
			_zombies(result, rng, center, rng.randi_range(2, 4), 10.0, 24.0, zone, false)
		2: # Great tree: one giant with a camp of a hermit at its foot.
			taken.append(center)
			_monument(result, center, 2, rng.randf() * TAU)
			var foot: Vector2 = center + Vector2.from_angle(rng.randf() * TAU) * 6.0
			taken.append(foot)
			result["crates"].append({"kind": "crate", "variant": 2, "x": foot.x, "z": foot.y, "y": _ground(foot), "radius": 0.6, "blocks": true})
			_props(result, rng, center, rng.randi_range(3, 5), 6.0, 12.0, [2, 11, 12, 8])
			_npcs(result, rng, site, [["sitter", 1]], 7.0, 10.0)
			_zombies(result, rng, center, 0 if zone == 0 else rng.randi_range(0, 2), 18.0, 26.0, zone, false)
		3: # Old shrine: pillars round an altar chest and two braziers.
			for corner in [Vector2(-7, -7), Vector2(7, -7), Vector2(7, 7), Vector2(-7, 7)]:
				var p: Vector2 = center + corner
				taken.append(p)
				_monument(result, p, 3, 0.0)
			taken.append(center)
			result["crates"].append({"kind": "crate", "variant": 3, "x": center.x, "z": center.y, "y": _ground(center), "radius": 0.6, "blocks": true})
			for side in [Vector2(-3.5, 0), Vector2(3.5, 0)]:
				var p: Vector2 = center + side
				result["props"].append({"kind": "prop", "variant": 8, "x": p.x, "z": p.y, "y": _ground(p), "yaw": 0.0, "scale": 1.5, "radius": PROP_RADII[8], "blocks": true})
			_npcs(result, rng, site, [["watch", 1]], 9.0, 12.0)
			_zombies(result, rng, center, rng.randi_range(1, 2), 14.0, 22.0, zone, false)
		_: # Battlefield: wreckage, broken walls, abandoned supplies and the dead that walk.
			_ruin_bits(result, rng, center, rng.randi_range(6, 10), 4.0, 20.0, taken)
			_props(result, rng, center, rng.randi_range(6, 9), 3.0, 20.0, MILITARY_PROPS)
			_crates(result, rng, center, rng.randi_range(3, 4), 3.0, 16.0, taken)
			_zombies(result, rng, center, rng.randi_range(4, 7) + zone, 4.0, 22.0, zone, true)


func _station(result: Dictionary, site: Dictionary) -> void:
	var p := Vector2(float(site["station_x"]), float(site["station_z"]))
	result["structures"].append({"kind": "workbench", "variant": 0, "scale": 1.0, "x": p.x, "z": p.y, "y": _ground(p), "yaw": 0.0, "radius": 0.9, "blocks": true})
	var trader_spot := p + Vector2(-2.2, 1.6)
	_add_npc(result, site, "trader", trader_spot, p, int(site["seed"]) + 11)


func _houses(result: Dictionary, rng: RandomNumberGenerator, center: Vector2, count: int, rmin: float, rmax: float, spacing: float, taken: Array, scale: float = BUILDING_SCALE, variant_limit: int = BUILDING_VARIANTS - 1) -> void:
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
		result["structures"].append({"kind": "building", "variant": _house_variant(rng, variant_limit), "scale": scale, "x": p.x, "z": p.y, "y": _ground(p), "yaw": yaw, "radius": scale * 0.62, "blocks": true})


func _fences(result: Dictionary, rng: RandomNumberGenerator, center: Vector2, count: int, rmin: float, rmax: float, variants: Array = [WALL_WOOD]) -> void:
	for i in count:
		var p := center + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(rmin, rmax)
		if world.is_water(p.x, p.y):
			continue
		result["structures"].append({"kind": "wall", "variant": variants[rng.randi() % variants.size()], "scale": WALL_SCALE, "x": p.x, "z": p.y, "y": _ground(p), "yaw": rng.randf() * PI, "radius": WALL_SCALE * 0.6, "blocks": true})


## A fence or palisade round a site with a few gaps for the way in.
func _ring_walls(result: Dictionary, rng: RandomNumberGenerator, center: Vector2, radius: float, coverage: float, variants: Array = [WALL_WOOD]) -> void:
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
		result["structures"].append({"kind": "wall", "variant": variants[rng.randi() % variants.size()], "scale": WALL_SCALE, "x": p.x, "z": p.y, "y": _ground(p), "yaw": -angle + PI * 0.5, "radius": WALL_SCALE * 0.6, "blocks": true})


func _towers(result: Dictionary, center: Vector2, offsets: Array, height_scale: float = 1.0, variant: int = 0) -> void:
	for offset in offsets:
		var p: Vector2 = center + offset
		if world.is_water(p.x, p.y):
			continue
		result["structures"].append({"kind": "tower", "variant": variant, "scale": 5.0 * height_scale, "x": p.x, "z": p.y, "y": _ground(p), "yaw": 0.0, "radius": 2.4, "blocks": true})


func _crates(result: Dictionary, rng: RandomNumberGenerator, center: Vector2, count: int, rmin: float, rmax: float, taken: Array) -> void:
	for attempt in count * 10:
		if result["crates"].size() >= count:
			break
		var p := center + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(rmin, rmax)
		if not _usable(p, taken, 4.5):
			continue
		taken.append(p)
		result["crates"].append({"kind": "crate", "variant": rng.randi_range(0, CRATE_VARIANTS - 1), "x": p.x, "z": p.y, "y": _ground(p), "radius": 0.6, "blocks": true})


func _props(result: Dictionary, rng: RandomNumberGenerator, center: Vector2, count: int, rmin: float, rmax: float, pool: Array = RUSTIC_PROPS) -> void:
	for i in count:
		var p := center + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(rmin, rmax)
		if world.is_water(p.x, p.y) or p.length() < Defs.HUB_SAFE_RADIUS + 8.0:
			continue
		var variant: int = pool[rng.randi() % pool.size()]
		result["props"].append({"kind": "prop", "variant": variant, "x": p.x, "z": p.y, "y": _ground(p), "yaw": rng.randf() * TAU, "scale": 1.5, "radius": PROP_RADII[variant], "blocks": true})


## Broken walls, pillars and heaps of rubble of a ruined place.
func _ruin_bits(result: Dictionary, rng: RandomNumberGenerator, center: Vector2, count: int, rmin: float, rmax: float, taken: Array) -> void:
	var placed := 0
	for attempt in count * 6:
		if placed >= count:
			break
		var p := center + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(rmin, rmax)
		if not _usable(p, taken, 6.0):
			continue
		taken.append(p)
		placed += 1
		var variant: int = rng.randi_range(0, RUIN_RADII.size() - 1)
		result["structures"].append({"kind": "ruin", "variant": variant, "scale": 1.0, "x": p.x, "z": p.y, "y": _ground(p), "yaw": rng.randf() * TAU, "radius": RUIN_RADII[variant], "blocks": true})


func _windmill(result: Dictionary, rng: RandomNumberGenerator, center: Vector2, rmin: float, rmax: float, taken: Array) -> void:
	for attempt in 20:
		var p := center + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(rmin, rmax)
		if not _usable(p, taken, 10.0):
			continue
		taken.append(p)
		result["structures"].append({"kind": "windmill", "variant": 0, "scale": 1.0, "x": p.x, "z": p.y, "y": _ground(p), "yaw": rng.randf() * TAU, "radius": 2.4, "blocks": true})
		return


## The big building in the middle of a village or fort.
func _town_center(result: Dictionary, rng: RandomNumberGenerator, center: Vector2, rmin: float, rmax: float, taken: Array) -> void:
	for attempt in 20:
		var p := center + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(rmin, rmax)
		if not _usable(p, taken, 14.0):
			continue
		taken.append(p)
		var yaw: float = -atan2(p.y - center.y, p.x - center.x) + PI * 0.5
		result["structures"].append({"kind": "building", "variant": TOWN_CENTER_VARIANT, "scale": 8.0, "x": p.x, "z": p.y, "y": _ground(p), "yaw": yaw, "radius": 8.0 * 0.62, "blocks": true})
		return


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
