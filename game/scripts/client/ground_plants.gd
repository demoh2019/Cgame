extends RefCounted
## Photoscanned ground plants (Poly Haven, CC0) scattered among the procedural grass near the
## camera: grass clumps, dandelions, celandine, nettles, weeds, periwinkle, ferns, shrubs, moss
## and wildflowers. Baked one mesh per variant by tools/bake_polyhaven.gd -- --plants.
## Each 16 m grass tile gets one MultiMesh per species (one variant per tile, so neighbouring
## tiles differ), drawn only up close; the procedural grass carries the carpet beyond.

const Defs = preload("res://scripts/shared/defs.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")

const FOLDER := "res://assets/models/polyhaven/baked/plants/"
const DRAW_DISTANCE := 34.0
const TILE := 16.0

## Quality multiplier on counts: Low 0 (off), Medium 0.55, High 1, Ultra 1.35.
static var density_scale: float = 1.0

# species: biomes, instances per 16 m tile at full density, scale range, clustered (flowers grow in patches).
const SPECIES := {
	"grass_medium_01": {"biomes": ["plains", "forest", "swamp", "mountain"], "count": 70, "scale": [1.6, 3.2], "cluster": false},
	"grass_medium_02": {"biomes": ["plains", "forest", "swamp"], "count": 40, "scale": [1.4, 2.6], "cluster": false},
	"dandelion_01": {"biomes": ["plains", "forest"], "count": 22, "scale": [1.3, 2.0], "cluster": true},
	"celandine_01": {"biomes": ["forest", "swamp", "plains"], "count": 18, "scale": [1.3, 2.0], "cluster": true},
	"nettle_plant": {"biomes": ["forest", "swamp", "plains"], "count": 14, "scale": [2.6, 4.2], "cluster": true},
	"weed_plant_02": {"biomes": ["plains", "beach", "mountain", "forest"], "count": 20, "scale": [1.4, 2.4], "cluster": false},
	"periwinkle_plant": {"biomes": ["forest", "swamp"], "count": 14, "scale": [1.3, 2.0], "cluster": true},
	"shrub_sorrel_01": {"biomes": ["forest", "plains", "swamp"], "count": 16, "scale": [1.6, 2.6], "cluster": true},
	"moss_01": {"biomes": ["forest", "swamp", "mountain"], "count": 26, "scale": [2.0, 4.0], "cluster": false},
	"fern_02": {"biomes": ["forest", "swamp"], "count": 10, "scale": [0.9, 1.6], "cluster": true},
	"shrub_02": {"biomes": ["forest", "plains", "swamp"], "count": 2, "scale": [0.7, 1.1], "cluster": false},
	"shrub_03": {"biomes": ["plains", "forest", "mountain"], "count": 8, "scale": [1.4, 2.4], "cluster": false},
	"shrub_04": {"biomes": ["plains", "beach", "mountain"], "count": 5, "scale": [1.0, 1.8], "cluster": false},
	"flower_empodium": {"biomes": ["plains"], "count": 14, "scale": [1.2, 1.8], "cluster": true},
	"flower_gazania": {"biomes": ["plains", "beach"], "count": 14, "scale": [1.2, 1.9], "cluster": true},
	"flower_ursinia": {"biomes": ["plains"], "count": 14, "scale": [1.2, 1.8], "cluster": true},
	"flower_stinkkruid": {"biomes": ["plains", "beach"], "count": 10, "scale": [1.2, 1.8], "cluster": true},
	"flower_heliophila": {"biomes": ["plains"], "count": 8, "scale": [1.0, 1.6], "cluster": true},
}

static var _manifest: Dictionary = {}
static var _meshes: Dictionary = {}


static func variants(species: String) -> Array:
	if _manifest.is_empty():
		var text := FileAccess.get_file_as_string(FOLDER + "manifest.json")
		var parsed: Variant = JSON.parse_string(text) if not text.is_empty() else null
		_manifest = parsed if parsed is Dictionary else {"": []}
	return _manifest.get(species, [])


static func mesh(file: String) -> Mesh:
	if not _meshes.has(file):
		_meshes[file] = load(FOLDER + file) if ResourceLoader.exists(FOLDER + file) else null
	return _meshes[file]


static func quality_scale(level: int) -> float:
	return [0.0, 0.55, 1.0, 1.35][clampi(level, 0, 3)]


## The plants of one 16 m tile of a chunk, given the grass source sampler.
## `sample(lx, lz)` returns {"ok": bool, "h": float, "biome": String} for chunk-local coordinates.
static func build_tile(origin: Vector2, tile: int, tiles_per_side: int, sample: Callable) -> Array:
	var result: Array = []
	if density_scale <= 0.0:
		return result
	var tile_x: float = float(tile % tiles_per_side) * TILE
	var tile_z: float = float(tile / tiles_per_side) * TILE
	var rng := RandomNumberGenerator.new()
	rng.seed = WorldGen.mix(int(origin.x), int(origin.y), 4421, tile)
	for species in SPECIES:
		var info: Dictionary = SPECIES[species]
		var choices: Array = variants(species)
		if choices.is_empty():
			continue
		var choice: Dictionary = choices[rng.randi() % choices.size()]
		var plant_mesh: Mesh = mesh(str(choice["file"]))
		if plant_mesh == null:
			continue
		var wanted: int = int(round(float(info["count"]) * density_scale * rng.randf_range(0.5, 1.4)))
		if wanted <= 0:
			continue
		var centers: Array = []
		if bool(info["cluster"]):
			for c in rng.randi_range(1, 3):
				centers.append(Vector2(tile_x + rng.randf() * TILE, tile_z + rng.randf() * TILE))
		var transforms: Array = []
		var low := INF
		var high := -INF
		for attempt in wanted * 2:
			if transforms.size() >= wanted:
				break
			var lx: float
			var lz: float
			if centers.is_empty():
				lx = tile_x + rng.randf() * TILE
				lz = tile_z + rng.randf() * TILE
			else:
				var center: Vector2 = centers[rng.randi() % centers.size()]
				var offset := Vector2.from_angle(rng.randf() * TAU) * (rng.randf() * rng.randf() * 3.5)
				lx = clampf(center.x + offset.x, tile_x, tile_x + TILE - 0.01)
				lz = clampf(center.y + offset.y, tile_z, tile_z + TILE - 0.01)
			var here: Dictionary = sample.call(lx, lz)
			if not bool(here.get("ok", false)) or not (str(here["biome"]) in info["biomes"]):
				continue
			var s: float = rng.randf_range(float(info["scale"][0]), float(info["scale"][1]))
			var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.85, 1.15), s))
			var h: float = float(here["h"])
			transforms.append(Transform3D(basis, Vector3(lx, h - 0.03, lz)))
			low = minf(low, h)
			high = maxf(high, h)
		if transforms.is_empty():
			continue
		var multimesh := MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.mesh = plant_mesh
		multimesh.instance_count = transforms.size()
		for i in transforms.size():
			multimesh.set_instance_transform(i, transforms[i])
		var instance := MultiMeshInstance3D.new()
		instance.name = "Plants_" + species
		instance.multimesh = multimesh
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		instance.visibility_range_end = DRAW_DISTANCE
		instance.visibility_range_end_margin = 6.0
		instance.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		var top: float = plant_mesh.get_aabb().size.y * float(info["scale"][1]) + 0.5
		instance.custom_aabb = AABB(Vector3(tile_x - 1.0, low - 0.3, tile_z - 1.0), Vector3(TILE + 2.0, high - low + top, TILE + 2.0))
		result.append(instance)
	return result
