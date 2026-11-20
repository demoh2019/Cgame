extends RefCounted
## The models of the downloaded packs, cut to size. Most packs are collections (one file, dozens of objects, each far from the
## origin and in its own units), so every model is baked once into its own mesh: the node's transform applied, scaled to a
## target size in meters, and moved so that its bottom centre sits at the origin. The result can go straight into a MultiMesh.
## Lists are filtered to what is actually installed: a missing pack just shortens a list, and an empty list means "use the
## Kenney fallback". Which entry a house or prop takes is `variant % available.size()`, so the world data never has to know.

const PACKS := "res://assets/packs/"

# kind: "footprint" (longest horizontal side), "height" or "length" (longest horizontal side too, for walls and fences).
# tex: a texture to put on every surface (the Highlands FBX files carry no usable material); node: the object inside a collection.
const HOUSES := [
	{"path": "village/EA03_Village_OutBuilding_Shed_01a.glb", "kind": "footprint", "size": 7.0},
	{"path": "highlands/SM_Hut.fbx", "kind": "footprint", "size": 7.0, "tex": "highlands/T_Hut_diffuse.png"},
	{"path": "highlands/SM_Barracks.fbx", "kind": "footprint", "size": 7.0, "tex": "highlands/T_Barracks_diffuse.png"},
	{"path": "props/AllAssets_with_texture.glb", "node": "Stylized Hut01", "kind": "footprint", "size": 7.0},
	{"path": "village/EA03_Village_OutBuilding_Cubby_01d.glb", "kind": "footprint", "size": 7.0},
	{"path": "highlands/SM_Hut.fbx", "kind": "footprint", "size": 6.2, "tex": "highlands/T_Hut_diffuse.png"},
	{"path": "props/AllAssets_with_texture.glb", "node": "Stylized Hut02", "kind": "footprint", "size": 7.0},
	{"path": "highlands/SM_TownCenter.fbx", "kind": "footprint", "size": 7.0, "tex": "highlands/T_TownCenter_diffuse.png"},
	{"path": "village/EA03_Village_OutBuilding_PentHouse_01a.glb", "kind": "footprint", "size": 7.0},
]
const TOWN_CENTER_VARIANT := 7 # Index in HOUSES: the big building in the middle of a village.

const TOWERS := [
	{"path": "highlands/SM_WatchTower.fbx", "kind": "height", "size": 8.0, "tex": "highlands/T_WatchTower_diffuse.png"},
	{"path": "highlands/SM_Tower.fbx", "kind": "height", "size": 7.0, "tex": "highlands/T_Tower_diffuse.png"},
	{"path": "village/EA03_Village_Tover_01a.glb", "kind": "height", "size": 9.0},
]

const WALLS := [
	{"path": "village/EA03_Fence_Wall_01b.glb", "kind": "length", "size": 3.8},
	{"path": "highlands/SM_WallMid.fbx", "kind": "length", "size": 3.8, "tex": "highlands/T_WallMid_diffuse.png"},
	{"path": "highlands/SM_WoodFence.fbx", "kind": "length", "size": 3.8, "tex": "highlands/T_Props_diffuse.png"},
	{"path": "props/AllAssets_with_texture.glb", "node": "FenceWood_H01", "kind": "length", "size": 3.8},
	{"path": "props/AllAssets_with_texture.glb", "node": "Wall_Stone01", "kind": "length", "size": 3.8},
]
const WALL_STONE := 1 # Indices of WALLS for forts and cities, and for farms and villages.
const WALL_WOOD := 2

# Things standing about: variant is an index into this list. `radius` is what blocks movement; the server learns it from the
# prop's own record, so a big heap of rubble can be wide and a barrel narrow.
const PROPS := [
	{"path": "village/EA03_Prop_Container_Barrel_01d.glb", "kind": "height", "size": 1.0, "radius": 0.45},
	{"path": "village/EA03_Prop_Container_Crate_01a.glb", "kind": "height", "size": 0.8, "radius": 0.45},
	{"path": "village/EA03_Prop_Town_Bench_01a.glb", "kind": "length", "size": 1.8, "radius": 0.6},
	{"path": "village/EA03_Prop_Tabble_02a.glb", "kind": "length", "size": 1.4, "radius": 0.6},
	{"path": "village/EA03_Prop_Container_Basket_01a.glb", "kind": "height", "size": 0.7, "radius": 0.35},
	{"path": "village/EA03_Prop_Stool_01a.glb", "kind": "height", "size": 0.6, "radius": 0.3},
	{"path": "highlands/SM_Barrel.fbx", "kind": "height", "size": 1.1, "radius": 0.5, "tex": "highlands/T_Props_diffuse.png"},
	{"path": "highlands/SM_WoodCrate.fbx", "kind": "height", "size": 0.9, "radius": 0.5, "tex": "highlands/T_Props_diffuse.png"},
	{"path": "props/AllAssets_with_texture.glb", "node": "Brazier", "kind": "length", "size": 1.3, "radius": 0.6},
	{"path": "props/AllAssets_with_texture.glb", "node": "Market03", "kind": "length", "size": 5.0, "radius": 2.4},
	{"path": "props/AllAssets_with_texture.glb", "node": "Streetlamp01", "kind": "height", "size": 4.2, "radius": 0.4},
	{"path": "props/AllAssets_with_texture.glb", "node": "Bench01", "kind": "length", "size": 2.2, "radius": 0.7},
	{"path": "props/AllAssets_with_texture.glb", "node": "Trunk02", "kind": "length", "size": 2.6, "radius": 0.9},
	{"path": "dungeon/barrel_small_stack.gltf", "kind": "height", "size": 1.4, "radius": 0.7},
	{"path": "dungeon/crates_stacked.gltf", "kind": "height", "size": 1.5, "radius": 0.8},
	{"path": "dungeon/keg_decorated.gltf", "kind": "height", "size": 1.1, "radius": 0.5},
	{"path": "dungeon/table_medium_tablecloth.gltf", "kind": "length", "size": 1.8, "radius": 0.9},
	{"path": "dungeon/torch_lit.gltf", "kind": "height", "size": 1.6, "radius": 0.2},
	{"path": "dungeon/bed_decorated.gltf", "kind": "length", "size": 2.2, "radius": 1.0},
	{"path": "dungeon/shelf_large.gltf", "kind": "length", "size": 2.0, "radius": 0.9},
	{"path": "res://assets/models/polyhaven/baked/fire_pit.res", "kind": "length", "size": 1.6, "radius": 0.8},
	{"path": "res://assets/models/polyhaven/baked/wine_barrel.res", "kind": "height", "size": 1.0, "radius": 0.45},
	{"path": "res://assets/models/polyhaven/baked/barrel_pile.res", "kind": "length", "size": 3.6, "radius": 1.5},
	{"path": "res://assets/models/polyhaven/baked/bucket.res", "kind": "height", "size": 0.45, "radius": 0.25},
	{"path": "res://assets/models/polyhaven/baked/lantern.res", "kind": "height", "size": 0.6, "radius": 0.25},
	{"path": "res://assets/models/polyhaven/baked/horse_statue.res", "kind": "height", "size": 3.2, "radius": 1.3},
	# Poly Haven, second batch (indices 26-49): what the old world left behind.
	{"path": "res://assets/models/polyhaven/baked/oil_barrel.res", "kind": "height", "size": 0.95, "radius": 0.45},
	{"path": "res://assets/models/polyhaven/baked/fuel_barrel.res", "kind": "height", "size": 0.95, "radius": 0.45},
	{"path": "res://assets/models/polyhaven/baked/fire_barrel.res", "kind": "height", "size": 1.0, "radius": 0.5},
	{"path": "res://assets/models/polyhaven/baked/jerrycan.res", "kind": "height", "size": 0.5, "radius": 0.25},
	{"path": "res://assets/models/polyhaven/baked/jerrycan_green.res", "kind": "height", "size": 0.5, "radius": 0.25},
	{"path": "res://assets/models/polyhaven/baked/military_crate.res", "kind": "length", "size": 1.3, "radius": 0.6},
	{"path": "res://assets/models/polyhaven/baked/army_crate.res", "kind": "length", "size": 1.2, "radius": 0.55},
	{"path": "res://assets/models/polyhaven/baked/ammo_box.res", "kind": "length", "size": 0.5, "radius": 0.25},
	{"path": "res://assets/models/polyhaven/baked/tyre.res", "kind": "length", "size": 0.85, "radius": 0.4},
	{"path": "res://assets/models/polyhaven/baked/wheel_rim.res", "kind": "length", "size": 0.6, "radius": 0.3},
	{"path": "res://assets/models/polyhaven/baked/road_barrier.res", "kind": "length", "size": 2.4, "radius": 1.1},
	{"path": "res://assets/models/polyhaven/baked/trash_can.res", "kind": "height", "size": 1.0, "radius": 0.4},
	{"path": "res://assets/models/polyhaven/baked/trash_bag.res", "kind": "height", "size": 0.7, "radius": 0.35},
	{"path": "res://assets/models/polyhaven/baked/propane_tank.res", "kind": "height", "size": 1.3, "radius": 0.35},
	{"path": "res://assets/models/polyhaven/baked/generator.res", "kind": "length", "size": 1.0, "radius": 0.5},
	{"path": "res://assets/models/polyhaven/baked/street_lamp.res", "kind": "height", "size": 5.0, "radius": 0.3},
	{"path": "res://assets/models/polyhaven/baked/hydrant.res", "kind": "height", "size": 0.8, "radius": 0.25},
	{"path": "res://assets/models/polyhaven/baked/picnic_table.res", "kind": "length", "size": 2.0, "radius": 0.9},
	{"path": "res://assets/models/polyhaven/baked/plastic_crate.res", "kind": "height", "size": 0.35, "radius": 0.25},
	{"path": "res://assets/models/polyhaven/baked/cardboard_box.res", "kind": "height", "size": 0.5, "radius": 0.3},
	{"path": "res://assets/models/polyhaven/baked/wooden_crate.res", "kind": "height", "size": 0.8, "radius": 0.45},
	{"path": "res://assets/models/polyhaven/baked/metal_rack.res", "kind": "height", "size": 1.9, "radius": 0.8},
	{"path": "res://assets/models/polyhaven/baked/tool_cart.res", "kind": "height", "size": 1.0, "radius": 0.5},
	{"path": "res://assets/models/polyhaven/baked/bench.res", "kind": "length", "size": 1.6, "radius": 0.6},
]

# Bits of ruin for cities and bunkers: broken walls, pillars, rubble. Blocking, big.
const RUINS := [
	{"path": "dungeon/pillar_decorated.gltf", "kind": "height", "size": 4.2, "radius": 0.8},
	{"path": "dungeon/pillar.gltf", "kind": "height", "size": 4.0, "radius": 0.8},
	{"path": "dungeon/wall_broken.gltf", "kind": "length", "size": 4.0, "radius": 1.8},
	{"path": "dungeon/wall_cracked.gltf", "kind": "length", "size": 4.0, "radius": 1.8},
	{"path": "dungeon/wall_half.gltf", "kind": "length", "size": 2.2, "radius": 1.1},
	{"path": "dungeon/rubble_large.gltf", "kind": "length", "size": 6.0, "radius": 2.6},
	{"path": "dungeon/rubble_half.gltf", "kind": "length", "size": 3.5, "radius": 1.6},
	{"path": "dungeon/column.gltf", "kind": "height", "size": 1.8, "radius": 0.5},
	{"path": "dungeon/wall_doorway.gltf", "kind": "length", "size": 4.0, "radius": 1.9},
	{"path": "dungeon/stairs_wide.gltf", "kind": "length", "size": 5.0, "radius": 2.2},
]

# The big pieces of landmarks, by WorldPoi monument variant. Each variant lists models in order of preference.
const MONUMENTS := [
	[{"path": "loose/the_ancient_mystic_stone.glb", "node": "LP_Stone_Main_0", "kind": "height", "size": 4.2}, {"path": "dungeon/pillar.gltf", "kind": "height", "size": 4.0}],
	[{"path": "loose/crystal.glb", "kind": "height", "size": 4.6}, {"path": "loose/toon_style_-_crystal.glb", "node": "Crystal_Crystal_0", "kind": "height", "size": 4.6}],
	[{"path": "loose/stylized_hand_painted_trees.glb", "node": "Object_12", "kind": "height", "size": 21.0}, {"path": "nature/CommonTree_3.gltf", "kind": "height", "size": 21.0}],
	[{"path": "dungeon/pillar_decorated.gltf", "kind": "height", "size": 5.0}, {"path": "dungeon/pillar.gltf", "kind": "height", "size": 5.0}],
]

# Containers that hold loot: variant = crate id hash % size. Chests of three artists.
const CRATES := [
	{"path": "village/EA03_Prop_Container_Crate_01a.glb", "kind": "height", "size": 0.9},
	{"path": "dungeon/chest_gold.gltf", "kind": "length", "size": 1.2},
	{"path": "loose/low_poly_treasure_chest.glb", "kind": "length", "size": 1.1},
	{"path": "dungeon/chest.gltf", "kind": "length", "size": 1.2},
	{"path": "dungeon/box_large.gltf", "kind": "height", "size": 0.9},
	{"path": "res://assets/models/polyhaven/baked/crate.res", "kind": "length", "size": 1.2},
]

# Trees from the hand-painted collection (an addition to the nature kit) and the rocks and crystals.
const PAINTED_TREES := ["Object_6", "Object_8", "Object_10", "Object_12", "Object_14", "Object_16", "Object_18", "Object_20", "Object_22", "Object_24"]
const PAINTED_TREE_FILE := "loose/stylized_hand_painted_trees.glb"
const STONES := ["Mid_1_MID_0", "Mid_2_MID_0", "Mid_3_MID_0", "Mid_5_MID_0", "Big_2_BiG_0", "Big_3_BiG_0", "BIG_1_BiG_0", "Small_1_SMall_0"]
const STONE_FILE := "loose/stone_pack.glb"
const CRYSTALS := [
	{"path": "loose/crystal.glb", "kind": "height", "size": 1.9},
	{"path": "loose/toon_style_-_crystal.glb", "node": "Crystal_Crystal_0", "kind": "height", "size": 2.0},
	{"path": "loose/toon_style_-_crystal.glb", "node": "Crystal_001_Crystal_0", "kind": "height", "size": 1.8},
	{"path": "loose/toon_style_-_crystal.glb", "node": "Crystal_002_Crystal_0", "kind": "height", "size": 1.6},
]
const DECOR_EXTRA := [
	{"path": "res://assets/models/polyhaven/baked/fallen_trunk.res", "kind": "length", "size": 5.0, "biomes": ["forest", "swamp"], "count": 1},
	{"path": "res://assets/models/polyhaven/baked/stump_2.res", "kind": "length", "size": 1.3, "biomes": ["forest", "plains"], "count": 2},
	{"path": "res://assets/models/polyhaven/baked/rock_7.res", "kind": "length", "size": 1.2, "biomes": ["plains", "mountain", "beach"], "count": 3},
	{"path": "res://assets/models/polyhaven/baked/rock_9.res", "kind": "length", "size": 0.9, "biomes": ["forest", "plains", "mountain"], "count": 3},
	{"path": "res://assets/models/polyhaven/baked/dead_trunk.res", "kind": "length", "size": 4.0, "biomes": ["forest", "swamp"], "count": 2},
	{"path": "res://assets/models/polyhaven/baked/tree_stump.res", "kind": "length", "size": 1.5, "biomes": ["forest", "plains", "swamp"], "count": 3},
	{"path": "res://assets/models/polyhaven/baked/mossy_rock_5.res", "kind": "length", "size": 1.6, "biomes": ["forest", "plains", "mountain", "beach"], "count": 4},
	{"path": "loose/low_poly_tree_log_and_stump.glb", "node": "Object_7", "kind": "length", "size": 1.6, "biomes": ["forest", "swamp"], "count": 3},
	{"path": "loose/low_poly_tree_log_and_stump.glb", "node": "Object_11", "kind": "length", "size": 1.6, "biomes": ["forest", "plains"], "count": 3},
	{"path": "loose/the_ancient_mystic_stone.glb", "node": "LP_Stone_Main_0", "kind": "height", "size": 2.4, "biomes": ["forest", "plains", "mountain"], "count": 1},
	{"path": "loose/flowers_pack_1.glb", "node": "Plane_036_lowPoly_flor1_003_0", "kind": "height", "size": 0.9, "biomes": ["plains", "forest"], "count": 6},
	{"path": "loose/flowers_pack_1.glb", "node": "Plane_022_lowPoly_flor25_0", "kind": "height", "size": 0.9, "biomes": ["plains"], "count": 6},
	{"path": "loose/flowers_pack_1.glb", "node": "Plane_001_lowPoly_flor21_0", "kind": "height", "size": 1.0, "biomes": ["plains", "forest"], "count": 5},
]

static var _cache: Dictionary = {}
static var _available: Dictionary = {}


## Paths are relative to the downloaded packs unless they start with res:// (the Poly Haven models in the repository).
static func full_path(path: String) -> String:
	return path if path.begins_with("res://") else PACKS + path


static func exists(relative: String) -> bool:
	return ResourceLoader.exists(full_path(relative))


## The entries of a list whose files are installed, in list order.
static func available(list_name: String, list: Array) -> Array:
	if not _available.has(list_name):
		var found: Array = []
		for entry in list:
			if exists(String(entry["path"])) and (not entry.has("tex") or exists(String(entry["tex"]))):
				found.append(entry)
		_available[list_name] = found
	return _available[list_name]


## The entry for a variant number (variant % available), or {} when nothing of the list is installed.
static func pick(list_name: String, list: Array, variant: int) -> Dictionary:
	var found: Array = available(list_name, list)
	if found.is_empty():
		return {}
	return found[posmod(variant, found.size())]


static func entry_mesh(entry: Dictionary) -> Mesh:
	if entry.is_empty():
		return null
	var key := "%s|%s|%s" % [entry["path"], entry.get("node", ""), entry["size"]]
	if not _cache.has(key):
		_cache[key] = bake(String(entry["path"]), String(entry.get("node", "")), String(entry["kind"]), float(entry["size"]), String(entry.get("tex", "")))
	return _cache[key]


## One object of a model file, transformed, scaled and recentred. `node` empty takes the first mesh that is not a collision hull.
static func bake(path: String, node_name: String, kind: String, size: float, texture_path: String = "", yaw: float = 0.0) -> Mesh:
	var loaded: Resource = load(full_path(path))
	if loaded is Mesh:
		return _fit_mesh(loaded as Mesh, kind, size)
	var scene := loaded as PackedScene
	if scene == null:
		return null
	var root: Node = scene.instantiate()
	var source: MeshInstance3D = null
	for candidate in root.find_children("*", "MeshInstance3D", true, false):
		var instance := candidate as MeshInstance3D
		if instance.mesh == null or String(instance.name).begins_with("UCX_"):
			continue
		if node_name == "" or String(instance.name) == node_name:
			source = instance
			break
	if source == null:
		root.free()
		return null
	# The object's transform inside the file (position, rotation and scale of the node and its parents).
	var transform := Transform3D.IDENTITY
	var walker: Node = source
	while walker != null and walker != root:
		transform = (walker as Node3D).transform * transform
		walker = walker.get_parent()
	if yaw != 0.0:
		transform = Transform3D(Basis(Vector3.UP, yaw), Vector3.ZERO) * transform
	var box: AABB = transform * source.mesh.get_aabb()
	var longest: float = maxf(maxf(box.size.x, box.size.z), 0.0001)
	var factor: float = (size / maxf(box.size.y, 0.0001)) if kind == "height" else (size / longest)
	var offset := Vector3(-(box.position.x + box.size.x * 0.5), -box.position.y, -(box.position.z + box.size.z * 0.5))
	var baked := ArrayMesh.new()
	var texture: Texture2D = null
	if texture_path != "":
		texture = load(PACKS + texture_path) as Texture2D
	for surface in source.mesh.get_surface_count():
		var arrays: Array = source.mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var moved := PackedVector3Array()
		moved.resize(vertices.size())
		for i in vertices.size():
			moved[i] = ((transform * vertices[i]) + offset) * factor
		arrays[Mesh.ARRAY_VERTEX] = moved
		if arrays[Mesh.ARRAY_NORMAL] != null:
			var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			var turned := PackedVector3Array()
			turned.resize(normals.size())
			var normal_basis: Basis = transform.basis.inverse().transposed()
			for i in normals.size():
				turned[i] = (normal_basis * normals[i]).normalized()
			arrays[Mesh.ARRAY_NORMAL] = turned
		arrays[Mesh.ARRAY_TANGENT] = null # Tangents would need the same turning; the ground-level props do without normal maps.
		baked.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var material: Material = source.mesh.surface_get_material(surface)
		if texture != null:
			var painted := StandardMaterial3D.new()
			painted.albedo_texture = texture
			painted.roughness = 0.9
			painted.cull_mode = BaseMaterial3D.CULL_DISABLED
			material = painted
		elif material is BaseMaterial3D:
			# Source materials may carry normal maps and big metallic values that look wrong at this distance: keep it matte.
			material = (material as BaseMaterial3D).duplicate()
			(material as BaseMaterial3D).normal_enabled = false
			(material as BaseMaterial3D).metallic = minf((material as BaseMaterial3D).metallic, 0.2)
			if path.begins_with("dungeon/"):
				# KayKit's clean pastel stone reads as plastic next to the scanned props: weather it to a darker, warmer grey.
				(material as BaseMaterial3D).albedo_color = Color(0.68, 0.64, 0.58)
				(material as BaseMaterial3D).roughness = 1.0
		baked.surface_set_material(surface, material)
	root.free()
	return baked


## A ready mesh (already baked, materials kept) scaled to its size and stood on the origin. Keeps tangents, so normal maps work.
static func _fit_mesh(source: Mesh, kind: String, size: float) -> Mesh:
	var box: AABB = source.get_aabb()
	var longest: float = maxf(maxf(box.size.x, box.size.z), 0.0001)
	var factor: float = (size / maxf(box.size.y, 0.0001)) if kind == "height" else (size / longest)
	var offset := Vector3(-(box.position.x + box.size.x * 0.5), -box.position.y, -(box.position.z + box.size.z * 0.5))
	var fitted := ArrayMesh.new()
	for surface in source.get_surface_count():
		var arrays: Array = source.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		for i in vertices.size():
			vertices[i] = (vertices[i] + offset) * factor
		arrays[Mesh.ARRAY_VERTEX] = vertices
		fitted.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		fitted.surface_set_material(surface, source.surface_get_material(surface))
	return fitted


# Scanned rocks from Poly Haven, used before the stylised ones when present.
const SCANNED_ROCKS := ["boulder_01", "boulder_02", "boulder_04", "rock_7", "rock_9", "mossy_rock_1", "mossy_rock_2", "mossy_rock_3", "mossy_rock_4", "mossy_rock_5", "mossy_rock_6"]


static func scanned_rock(variant: int) -> Mesh:
	var name: String = SCANNED_ROCKS[posmod(variant, SCANNED_ROCKS.size())]
	var key := "scanned_rock|" + name
	if not _cache.has(key):
		var path: String = "res://assets/models/polyhaven/baked/%s.res" % name
		_cache[key] = bake(path, "", "length", 3.2 if name.begins_with("boulder") else 2.6) if ResourceLoader.exists(path) else null
	return _cache[key]


static func has_scanned_rocks() -> bool:
	return ResourceLoader.exists("res://assets/models/polyhaven/baked/boulder_01.res")


# --- Direct lookups for the special cases ---------------------------------------------------------------------------------

static func painted_tree(variant: int) -> Mesh:
	if not exists(PAINTED_TREE_FILE):
		return null
	var node: String = PAINTED_TREES[posmod(variant, PAINTED_TREES.size())]
	var key := "painted_tree|" + node
	if not _cache.has(key):
		_cache[key] = bake(PAINTED_TREE_FILE, node, "height", 7.0)
	return _cache[key]


static func stone(variant: int) -> Mesh:
	if not exists(STONE_FILE):
		return null
	var node: String = STONES[posmod(variant, STONES.size())]
	var key := "stone|" + node
	if not _cache.has(key):
		_cache[key] = bake(STONE_FILE, node, "length", 2.2 if node.begins_with("Small") else 3.0)
	return _cache[key]


## The model of a landmark piece, or null when none of its candidates is installed.
static func monument(variant: int) -> Mesh:
	if variant < 0 or variant >= MONUMENTS.size():
		return null
	for entry in MONUMENTS[variant]:
		if exists(String(entry["path"])):
			return entry_mesh(entry)
	return null


static func has_painted_trees() -> bool:
	return exists(PAINTED_TREE_FILE)


static func has_stones() -> bool:
	return exists(STONE_FILE)


## The windmill: body and sails are separate files that share one origin; the sails get the body's scale and offset so they
## fit, and are returned with the pivot they turn about.
static func windmill() -> Dictionary:
	if _cache.has("windmill"):
		return _cache["windmill"]
	var result := {}
	if exists("highlands/SM_Windmill.fbx") and exists("highlands/SM_Windmill_Sails.fbx") and exists("highlands/T_Windmill_diffuse.png"):
		var body_scene := load(PACKS + "highlands/SM_Windmill.fbx") as PackedScene
		var sails_scene := load(PACKS + "highlands/SM_Windmill_Sails.fbx") as PackedScene
		var body_root: Node = body_scene.instantiate()
		var sails_root: Node = sails_scene.instantiate()
		var body := _first_mesh(body_root)
		var sails := _first_mesh(sails_root)
		if body != null and sails != null:
			var box: AABB = body.mesh.get_aabb()
			var factor: float = 9.0 / maxf(box.size.y, 0.0001)
			var offset := Vector3(-(box.position.x + box.size.x * 0.5), -box.position.y, -(box.position.z + box.size.z * 0.5))
			var texture := load(PACKS + "highlands/T_Windmill_diffuse.png") as Texture2D
			result = {"body": _scaled(body.mesh, offset, factor, texture), "sails": _scaled(sails.mesh, offset, factor, texture)}
			var sail_box: AABB = sails.mesh.get_aabb()
			result["pivot"] = (sail_box.get_center() + offset) * factor
			# The sails turn about their thinnest axis.
			var axis := Vector3.FORWARD
			if sail_box.size.x <= sail_box.size.y and sail_box.size.x <= sail_box.size.z:
				axis = Vector3.RIGHT
			elif sail_box.size.y <= sail_box.size.z:
				axis = Vector3.UP
			result["axis"] = axis
		body_root.free()
		sails_root.free()
	_cache["windmill"] = result
	return result


static func _first_mesh(root: Node) -> MeshInstance3D:
	for candidate in root.find_children("*", "MeshInstance3D", true, false):
		var instance := candidate as MeshInstance3D
		if instance.mesh != null and not String(instance.name).begins_with("UCX_"):
			return instance
	return null


static func _scaled(source: Mesh, offset: Vector3, factor: float, texture: Texture2D) -> Mesh:
	var result := ArrayMesh.new()
	for surface in source.get_surface_count():
		var arrays: Array = source.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var moved := PackedVector3Array()
		moved.resize(vertices.size())
		for i in vertices.size():
			moved[i] = (vertices[i] + offset) * factor
		arrays[Mesh.ARRAY_VERTEX] = moved
		arrays[Mesh.ARRAY_TANGENT] = null
		result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var material := StandardMaterial3D.new()
		material.albedo_texture = texture
		material.roughness = 0.9
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		result.surface_set_material(surface, material)
	return result
