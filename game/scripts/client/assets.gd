extends RefCounted
## Loads and caches the imported Kenney models and the meshes derived from them.

const Split = preload("res://scripts/client/mesh_split.gd")

const ROOT := "res://assets/kenney/"
const BUILDINGS := ["city/building-small-a", "city/building-small-b", "city/building-small-c", "city/building-small-d", "city/building-garage"]
const TREE_SCALE := 7.0 # The source trees are about 0.4 m tall on a 1 m tile.

static var _cache: Dictionary = {}


static func scene(path: String) -> PackedScene:
	if not _cache.has(path):
		_cache[path] = load(ROOT + path + ".glb")
	return _cache[path]


static func instance(path: String) -> Node:
	return scene(path).instantiate()


## The first mesh of a model (all of Kenney's props are a single mesh).
static func mesh(path: String) -> Mesh:
	var key := "mesh:" + path
	if not _cache.has(key):
		var root := instance(path)
		var found: Array = root.find_children("*", "MeshInstance3D", true, false)
		_cache[key] = (found[0] as MeshInstance3D).mesh if not found.is_empty() else null
		root.free()
	return _cache[key]


static func building_mesh(variant: int) -> Mesh:
	return mesh(BUILDINGS[posmod(variant, BUILDINGS.size())])


## Individual trees cut out of the "grass with trees" tiles: an array of Mesh, origin at the foot of the trunk.
static func tree_meshes() -> Array:
	if not _cache.has("trees"):
		var result: Array = []
		for path in ["city/grass-trees", "city/grass-trees-tall"]:
			for part in Split.split(mesh(path), 0.1, 0.05):
				result.append(part["mesh"])
		_cache["trees"] = result
	return _cache["trees"]


static func sound(name: String) -> AudioStream:
	var key := "sound:" + name
	if not _cache.has(key):
		_cache[key] = load(ROOT + "sounds/" + name + ".ogg")
	return _cache[key]


# --- The model packs imported from the artist's downloads (game/tools/import_downloads.sh) ---------------------------
# They are not part of the repository (their licences forbid redistributing the files), so everything below
# reports "not available" when they are missing and the callers fall back to the Kenney set above.

const PACKS := "res://assets/packs/"
const BUILDING_FILES := ["village/EA03_Village_OutBuilding_Shed_01a", "village/EA03_Village_OutBuilding_Cubby_01d", "village/EA03_Village_OutBuilding_PentHouse_01a", "village/EA03_Village_OutBuilding_WoodRoof_01b", "village/EA03_Village_Tover_01a"]
const BUILDING_FOOTPRINT := 7.0 # Longest side of a house in meters (the server collides with a circle of 3.7 m).
const WALL_LENGTH := 3.8
const TREE_FILES := ["CommonTree_1", "CommonTree_2", "CommonTree_3", "CommonTree_4", "CommonTree_5", "Pine_1", "Pine_2", "Pine_3", "Pine_4", "Pine_5"]
const ROCK_FILES := ["Rock_Medium_1", "Rock_Medium_2", "Rock_Medium_3"]
const CHARACTER_NAMES := ["Elf_Male", "Elf_Female", "Orc_Male", "Orc_Female"]


static func pack_exists(relative: String) -> bool:
	return ResourceLoader.exists(PACKS + relative)


static func has_nature() -> bool:
	return pack_exists("nature/CommonTree_1.gltf") and pack_exists("nature/Rock_Medium_1.gltf") and pack_exists("nature/Bush_Common.gltf")


static func has_village() -> bool:
	return pack_exists("village/EA03_Village_Tover_01a.glb") and pack_exists("village/EA03_Prop_Container_Crate_01a.glb")


static func has_characters() -> bool:
	return pack_exists("characters/Orc_Male.glb") and pack_exists("animations/UAL1_Standard.glb") and pack_exists("animations/UAL2_Standard.glb")


## The first mesh of a pack model (all of the props are one mesh with one or two surfaces).
static func pack_mesh(relative: String) -> Mesh:
	var key := "pack:" + relative
	if not _cache.has(key):
		var scene := load(PACKS + relative) as PackedScene
		var found: Mesh = null
		if scene != null:
			var root := scene.instantiate()
			var meshes: Array = root.find_children("*", "MeshInstance3D", true, false)
			if not meshes.is_empty():
				found = (meshes[0] as MeshInstance3D).mesh
			root.free()
		_cache[key] = found
	return _cache[key]


static func nature_mesh(file: String) -> Mesh:
	return pack_mesh("nature/" + file + ".gltf")


static func village_mesh(file: String) -> Mesh:
	return pack_mesh("village/" + file + ".glb")


## Scale that makes a mesh's longest horizontal side `target` meters.
static func fit_scale(mesh: Mesh, target: float) -> float:
	var box := mesh.get_aabb()
	return target / maxf(maxf(box.size.x, box.size.z), 0.01)


static func pack_building(variant: int) -> Dictionary:
	var file: String = BUILDING_FILES[posmod(variant, BUILDING_FILES.size())]
	var mesh := pack_mesh(file + ".glb")
	return {"mesh": mesh, "scale": fit_scale(mesh, BUILDING_FOOTPRINT)}


## All animations of both libraries on one AnimationLibrary. Their tracks address "Armature/Skeleton3D:<bone>",
## and every character of the Fantasy Races kit has exactly that skeleton, so they play on any of them.
static func animation_library() -> AnimationLibrary:
	if not _cache.has("animation_library"):
		var library := AnimationLibrary.new()
		for file in ["UAL1_Standard", "UAL2_Standard"]:
			var scene := load(PACKS + "animations/" + file + ".glb") as PackedScene
			if scene == null:
				continue
			var root := scene.instantiate()
			for player in root.find_children("*", "AnimationPlayer", true, false):
				for full_name in (player as AnimationPlayer).get_animation_list():
					# The player lists animations of a named library as "Library/Name": keep the plain name.
					var animation_name := StringName(String(full_name).get_slice("/", String(full_name).get_slice_count("/") - 1))
					if animation_name == &"RESET" or library.has_animation(animation_name):
						continue
					var animation: Animation = (player as AnimationPlayer).get_animation(full_name).duplicate()
					if String(animation_name).ends_with("_Loop") or animation_name == &"Farm_Harvest":
						animation.loop_mode = Animation.LOOP_LINEAR
					library.add_animation(animation_name, animation)
					# Godot's glTF importer drops the "_Loop" suffix and loops those animations itself; keep the
					# artist's names usable as well.
					if animation.loop_mode != Animation.LOOP_NONE and not String(animation_name).ends_with("_Loop"):
						var loop_name := StringName(String(animation_name) + "_Loop")
						if not library.has_animation(loop_name):
							library.add_animation(loop_name, animation)
			root.free()
		_cache["animation_library"] = library
	return _cache["animation_library"]
