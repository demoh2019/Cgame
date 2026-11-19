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
