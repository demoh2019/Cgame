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
# "size": [min, max] scale with a long tail ("big": share of instances drawn from [max, max * 1.8]).
# "files": explicit baked meshes (relative to baked/) for scanned props such as rocks and sticks.
const SPECIES := {
	# Lush green carpet: crossed photo cards of the dense tufts photographed in the grass_medium_01 atlas.
	# ~16 triangles a tuft, so thousands per tile; this is what covers the terrain.
	"lush_grass": {"cards": true, "biomes": ["plains", "forest", "swamp", "mountain", "beach"], "count": 1600, "scale": [0.6, 1.5],
		"big": 0.1, "cluster": false, "variants": 5, "distance": 72.0},
	# The grass carpet itself: the most common, everywhere, many variants, every size from short tufts to big clumps.
	"grass_medium_01": {"biomes": ["plains", "forest", "swamp", "mountain", "beach"], "count": 260, "scale": [1.2, 4.4], "big": 0.2,
		"cluster": false, "variants": 6, "distance": 60.0},
	"grass_medium_02": {"biomes": ["plains", "forest", "swamp", "mountain"], "count": 120, "scale": [1.2, 4.0], "big": 0.2,
		"cluster": false, "variants": 4, "distance": 60.0},
	"dandelion_01": {"biomes": ["plains", "forest"], "count": 40, "scale": [1.1, 2.4], "cluster": true, "variants": 2},
	"celandine_01": {"biomes": ["forest", "swamp", "plains"], "count": 34, "scale": [1.1, 2.4], "cluster": true, "variants": 2},
	"nettle_plant": {"biomes": ["forest", "swamp", "plains"], "count": 30, "scale": [2.4, 5.5], "big": 0.15, "cluster": true, "variants": 2},
	"weed_plant_02": {"biomes": ["plains", "beach", "mountain", "forest"], "count": 40, "scale": [1.2, 3.0], "cluster": false, "variants": 2},
	"periwinkle_plant": {"biomes": ["forest", "swamp"], "count": 30, "scale": [1.1, 2.4], "cluster": true, "variants": 2},
	"shrub_sorrel_01": {"biomes": ["forest", "plains", "swamp"], "count": 30, "scale": [1.4, 3.2], "cluster": true},
	"moss_01": {"biomes": ["forest", "swamp", "mountain"], "count": 50, "scale": [2.0, 5.0], "cluster": false},
	"fern_02": {"biomes": ["forest", "swamp"], "count": 22, "scale": [0.7, 2.0], "big": 0.15, "cluster": true, "variants": 2},
	"shrub_02": {"biomes": ["forest", "plains", "swamp"], "count": 5, "scale": [0.5, 1.2], "big": 0.2, "cluster": false, "variants": 2},
	"shrub_03": {"biomes": ["plains", "forest", "mountain"], "count": 18, "scale": [1.2, 3.2], "cluster": false, "variants": 2},
	"shrub_04": {"biomes": ["plains", "beach", "mountain"], "count": 10, "scale": [0.8, 2.4], "cluster": false},
	"flower_empodium": {"biomes": ["plains"], "count": 26, "scale": [1.1, 2.0], "cluster": true, "variants": 2},
	"flower_gazania": {"biomes": ["plains", "beach"], "count": 26, "scale": [1.1, 2.2], "cluster": true, "variants": 2},
	"flower_ursinia": {"biomes": ["plains"], "count": 26, "scale": [1.1, 2.0], "cluster": true, "variants": 2},
	"flower_stinkkruid": {"biomes": ["plains", "beach"], "count": 18, "scale": [1.1, 2.0], "cluster": true},
	"flower_heliophila": {"biomes": ["plains"], "count": 14, "scale": [0.9, 1.8], "cluster": true},
	# Scanned stones, sticks, branches, bark and roots lying in the grass, every size.
	"pebbles": {"files": ["rock_9.res", "stone_scatter.res", "rock_7.res"],
		"biomes": ["plains", "forest", "swamp", "mountain", "beach"], "count": 70, "scale": [0.04, 0.22], "cluster": true,
		"variants": 3, "distance": 32.0},
	"stones": {"files": ["rock_7.res", "rock_9.res", "mossy_rock_1.res", "mossy_rock_3.res", "mossy_rock_5.res", "stone_scatter.res"],
		"biomes": ["plains", "forest", "swamp", "mountain", "beach"], "count": 34, "scale": [0.15, 0.7], "big": 0.12, "cluster": false,
		"variants": 4, "distance": 80.0},
	# Knee-high boulders (no collision, so they stay below a survivor's knees).
	"boulders": {"files": ["boulder_01.res", "boulder_02.res", "boulder_04.res", "boulder_05.res", "mossy_rock_2.res",
		"mossy_rock_4.res", "mossy_rock_6.res"], "biomes": ["plains", "forest", "mountain", "beach", "swamp"], "count": 4,
		"scale": [0.18, 0.45], "cluster": false, "variants": 2, "distance": 140.0},
	"wood": {"files": ["stick_1.res", "stick_2.res", "branches.res", "bark_debris.res", "single_root.res", "pine_roots.res"],
		"biomes": ["forest", "swamp", "plains"], "count": 40, "scale": [0.3, 1.2], "big": 0.1, "cluster": false, "variants": 4,
		"distance": 55.0},
}

static var _manifest: Dictionary = {}
static var _meshes: Dictionary = {}


static func variants(species: String) -> Array:
	if _manifest.is_empty():
		var text := FileAccess.get_file_as_string(FOLDER + "manifest.json")
		var parsed: Variant = JSON.parse_string(text) if not text.is_empty() else null
		_manifest = parsed if parsed is Dictionary else {"": []}
	return _manifest.get(species, [])


## Pixel regions (x, y, w, h) of dense grass tufts in the 1024 px grass_medium_01 atlas.
# Cleaned atlas (only the tuft itself, built from those regions): five 512x256 rows stacked vertically.
const CARD_ATLAS := "res://assets/models/polyhaven/grass_medium_01/textures/grass_tufts_atlas.png"
const CARD_REGIONS := [Rect2(210, 790, 290, 112), Rect2(620, 784, 220, 106), Rect2(30, 900, 170, 124),
	Rect2(256, 900, 260, 110), Rect2(580, 890, 240, 130)]
const CARD_HEIGHT := 0.5
static var _card_material: StandardMaterial3D


static func card_material() -> StandardMaterial3D:
	if _card_material == null:
		_card_material = StandardMaterial3D.new()
		_card_material.albedo_texture = load(CARD_ATLAS) as Texture2D
		_card_material.albedo_color = Color(0.86, 1.12, 0.66) # Fresh, saturated green from the olive scan.
		_card_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		_card_material.alpha_scissor_threshold = 0.35
		_card_material.cull_mode = BaseMaterial3D.CULL_DISABLED
		_card_material.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT_WRAP
		_card_material.roughness = 0.85
		_card_material.backlight_enabled = true
		_card_material.backlight = Color(0.3, 0.42, 0.12)
		_card_material.vertex_color_use_as_albedo = true # Darker roots inside the tuft (baked AO).
	return _card_material


## One tuft: five photo cards fanned around the root (random angles) and leaning outward,
## with roots darkened by vertex colour, so it reads as a round, deep tuft from any side.
## Normals lean up so the cards light like a soft mass instead of showing flat faces.
static func card_mesh(region_index: int) -> Mesh:
	var region: Rect2 = CARD_REGIONS[region_index]
	var row := 1.0 / float(CARD_REGIONS.size())
	var uv0 := Vector2(0.0, row * float(region_index))
	var uv1 := Vector2(1.0, row * float(region_index + 1))
	var height := CARD_HEIGHT
	var half_width := height * region.size.x / region.size.y * 0.5
	var rng := RandomNumberGenerator.new()
	rng.seed = 9001 + region_index
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var cards := 5
	for k in cards:
		var angle := PI * float(k) / float(cards) + rng.randf_range(-0.2, 0.2)
		var side := Vector3(cos(angle), 0.0, sin(angle)) * half_width * rng.randf_range(0.8, 1.05)
		var facing := Vector3(-sin(angle), 0.0, cos(angle))
		if rng.randf() < 0.5:
			facing = -facing
		var lean := facing * height * rng.randf_range(0.12, 0.3) # Tops splay outward.
		var offset := facing * rng.randf_range(0.0, 0.06)
		var tall := height * rng.randf_range(0.85, 1.1)
		var normal := (Vector3.UP * 0.75 + facing * 0.25).normalized()
		var root_shade := Color(0.64, 0.66, 0.58)
		var corners := [[offset - side, Vector2(uv0.x, uv1.y), root_shade], [offset + side, Vector2(uv1.x, uv1.y), root_shade],
			[offset + side + lean + Vector3.UP * tall, Vector2(uv1.x, uv0.y), Color.WHITE],
			[offset - side + lean + Vector3.UP * tall, Vector2(uv0.x, uv0.y), Color.WHITE]]
		for tri in [[0, 1, 2], [0, 2, 3]]:
			for i in tri:
				surface.set_normal(normal)
				surface.set_color(corners[i][2])
				surface.set_uv(corners[i][1])
				surface.add_vertex(corners[i][0])
	var result := surface.commit()
	result.surface_set_material(0, card_material())
	return result


static func mesh(file: String, dry: bool = false) -> Mesh:
	if file.begins_with("#card"):
		if not _meshes.has(file):
			_meshes[file] = card_mesh(int(file.substr(5)))
		return _meshes[file]
	var key := file + ("|dry" if dry else "")
	if not _meshes.has(key):
		var loaded: Mesh = load(FOLDER + file) if ResourceLoader.exists(FOLDER + file) else null
		if loaded != null and not file.begins_with("../"):
			var id: String = file.get_basename().rsplit("_", true, 1)[0]
			loaded = _foliage_ready(loaded, _alpha_texture(id, dry))
		_meshes[key] = loaded
	return _meshes[key]


## The RGBA diffuse built by tools/fetch_polyhaven_alpha.sh (the glTF's JPEG has no leaf mask).
static func _alpha_texture(id: String, dry: bool) -> Texture2D:
	var base := "res://assets/models/polyhaven/%s/textures/%s_" % [id, id]
	var path := base + ("dry_alpha.png" if dry else "diff_alpha.png")
	if not ResourceLoader.exists(path):
		path = base + "diff_alpha.png"
	return load(path) as Texture2D if ResourceLoader.exists(path) else null


## Scanned leaf cards need foliage shading: lit from both sides, light shining through,
## soft wrap diffuse, and a lower alpha cut so thin blades survive the distant mipmaps
## instead of crumbling into dark specks.
static func _foliage_ready(source: Mesh, albedo_with_alpha: Texture2D) -> Mesh:
	var copy: Mesh = source.duplicate()
	for surface in copy.get_surface_count():
		var material: Material = copy.surface_get_material(surface)
		if not (material is BaseMaterial3D):
			continue
		var leaf: BaseMaterial3D = (material as BaseMaterial3D).duplicate()
		if albedo_with_alpha != null:
			# Real leaf mask: without it the black atlas background showed as black blade tips.
			leaf.albedo_texture = albedo_with_alpha
			leaf.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		leaf.cull_mode = BaseMaterial3D.CULL_DISABLED
		leaf.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT_WRAP
		leaf.specular_mode = BaseMaterial3D.SPECULAR_SCHLICK_GGX
		leaf.roughness = maxf(leaf.roughness, 0.7)
		leaf.albedo_color = leaf.albedo_color * Color(1.18, 1.18, 1.12)
		if leaf.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR or leaf.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA:
			leaf.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
			leaf.alpha_scissor_threshold = 0.3
		leaf.backlight_enabled = true
		leaf.backlight = Color(0.32, 0.38, 0.16)
		copy.surface_set_material(surface, leaf)
	return copy


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
		var choices: Array = []
		if bool(info.get("cards", false)):
			for c in CARD_REGIONS.size():
				choices.append({"file": "#card%d" % c})
		elif info.has("files"):
			for file in info["files"]:
				choices.append({"file": "../" + str(file)})
		else:
			choices = variants(species)
		if choices.is_empty():
			continue
		var per_tile: int = mini(int(info.get("variants", 1)), choices.size())
		var first: int = rng.randi() % choices.size()
		for v in per_tile:
			var choice: Dictionary = choices[(first + v * 7) % choices.size()]
			# Some grass tiles carry the scanned dry colouring for natural straw-and-green variety.
			var dry: bool = species.begins_with("grass_") and rng.randf() < 0.3
			var plant_mesh: Mesh = mesh(str(choice["file"]), dry)
			if plant_mesh == null:
				continue
			var spread: float = rng.randf_range(0.95, 1.05) if bool(info.get("cards", false)) else rng.randf_range(0.6, 1.3)
			var wanted: int = int(round(float(info["count"]) / float(per_tile) * density_scale * spread))
			if wanted <= 0:
				continue
			var instance: MultiMeshInstance3D = _scatter(species, info, plant_mesh, wanted, tile_x, tile_z, rng, sample)
			if instance != null:
				result.append(instance)
	return result


static func _scatter(species: String, info: Dictionary, plant_mesh: Mesh, wanted: int, tile_x: float, tile_z: float,
		rng: RandomNumberGenerator, sample: Callable) -> MultiMeshInstance3D:
	if true:
		var centers: Array = []
		# The carpet covers the ground evenly: a jittered grid leaves no bald patches.
		var grid: bool = bool(info.get("cards", false))
		var grid_side: int = maxi(1, int(ceil(sqrt(float(wanted)))))
		var grid_cell: float = TILE / float(grid_side)
		if bool(info["cluster"]):
			for c in rng.randi_range(1, 3):
				centers.append(Vector2(tile_x + rng.randf() * TILE, tile_z + rng.randf() * TILE))
		var transforms: Array = []
		var low := INF
		var high := -INF
		for attempt in wanted * 2:
			if transforms.size() >= wanted and not grid:
				break
			var lx: float
			var lz: float
			if grid:
				if attempt >= grid_side * grid_side:
					break
				lx = tile_x + (float(attempt % grid_side) + rng.randf()) * grid_cell
				lz = tile_z + (float(attempt / grid_side) + rng.randf()) * grid_cell
			elif centers.is_empty():
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
			var s: float = lerpf(float(info["scale"][0]), float(info["scale"][1]), pow(rng.randf(), 1.6))
			if rng.randf() < float(info.get("big", 0.0)):
				s = float(info["scale"][1]) * rng.randf_range(1.0, 1.8) # The odd huge clump or boulder.
			var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.85, 1.15), s))
			var h: float = float(here["h"])
			transforms.append(Transform3D(basis, Vector3(lx, h - 0.03, lz)))
			low = minf(low, h)
			high = maxf(high, h)
		if transforms.is_empty():
			return null
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
		instance.visibility_range_end = float(info.get("distance", DRAW_DISTANCE))
		# No fade: a fading range forces the whole multimesh into the slow transparent pass.
		var top: float = plant_mesh.get_aabb().size.y * float(info["scale"][1]) * 1.8 + 0.5
		instance.custom_aabb = AABB(Vector3(tile_x - 1.0, low - 0.3, tile_z - 1.0), Vector3(TILE + 2.0, high - low + top, TILE + 2.0))
		return instance
	return null
