extends RefCounted
## The models of the downloaded packs, cut to size. Most packs are collections (one file, dozens of objects, each far from the
## origin and in its own units), so every model is baked once into its own mesh: the node's transform applied, scaled to a
## target size in meters, and moved so that its bottom centre sits at the origin. The result can go straight into a MultiMesh.
## Lists are filtered to what is actually installed: a missing pack just shortens a list, and an empty list means "use the
## Kenney fallback". Which entry a house or prop takes is `variant % available.size()`, so the world data never has to know.

const PACKS := "res://assets/packs/"
const MeshLOD = preload("res://scripts/client/mesh_lod_preservation.gd")
const MeshPBR = preload("res://scripts/client/mesh_pbr_preservation.gd")
const StoneMicrodetail = preload("res://scripts/client/graphics_stone_microdetail.gd")

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

# Player-built walls by tier: timber planks, a cobble fence, a stone wall, a tall village stone wall. Baked to the width of
# the wall's footprint (about two metres).
const BARRICADE_MODELS := [
	{"path": "village/EA03_Fence_Plank_02a.glb", "kind": "length", "size": 2.0},
	{"path": "village/EA03_Fence_Cobble_01a.glb", "kind": "length", "size": 2.0},
	{"path": "props/AllAssets_with_texture.glb", "node": "Wall_Stone01", "kind": "length", "size": 2.0},
	{"path": "village/EA03_Fence_Wall_01b.glb", "kind": "length", "size": 2.0},
]


## The wall model of a tier (1..4), or null when its pack is missing.
static func barricade_mesh(tier: int) -> Mesh:
	var entry: Dictionary = BARRICADE_MODELS[clampi(tier, 1, BARRICADE_MODELS.size()) - 1]
	return entry_mesh(entry) if exists(String(entry["path"])) else null


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
	# Village pack, second look (indices 50-55): cooking, firewood, hay, a cart wheel, a drying hide, a chest.
	{"path": "village/EA03_Prop_Container_Chest_02a.glb", "kind": "length", "size": 1.1, "radius": 0.5},
	{"path": "village/EA_Items_House_cauldron_soup_01a.glb", "kind": "height", "size": 1.0, "radius": 0.6},
	{"path": "village/EA03_Items_House_Firewood_01a.glb", "kind": "length", "size": 1.8, "radius": 0.8},
	{"path": "village/EA03_Prop_Container_Bale_01a.glb", "kind": "length", "size": 1.6, "radius": 0.8},
	{"path": "village/EA03_Prop_Village_Whell_01d.glb", "kind": "height", "size": 1.2, "radius": 0.4},
	{"path": "village/EA03_Prop_Town_AnimalSkin_01b.glb", "kind": "height", "size": 1.8, "radius": 0.5},
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
	# Kenney CC0 kits (castle, graveyard, fantasy town, survival): broken walls, tower stumps, crypts,
	# wrecked siege engines, camps. Keep in step with WorldPoi.RUIN_RADII.
	{"path": "res://assets/models/kenney_ruins/castle/wall-half.glb", "kind": "length", "size": 4.0, "radius": 1.8},
	{"path": "res://assets/models/kenney_ruins/castle/wall-corner-half.glb", "kind": "length", "size": 4.0, "radius": 1.8},
	{"path": "res://assets/models/kenney_ruins/castle/wall-pillar.glb", "kind": "height", "size": 4.5, "radius": 0.9},
	{"path": "res://assets/models/kenney_ruins/castle/wall-narrow.glb", "kind": "length", "size": 4.0, "radius": 1.2},
	{"path": "res://assets/models/kenney_ruins/castle/tower-square-base.glb", "kind": "height", "size": 4.5, "radius": 2.4},
	{"path": "res://assets/models/kenney_ruins/castle/tower-hexagon-base.glb", "kind": "height", "size": 4.5, "radius": 2.4},
	{"path": "res://assets/models/kenney_ruins/castle/siege-tower-demolished.glb", "kind": "height", "size": 5.0, "radius": 2.2},
	{"path": "res://assets/models/kenney_ruins/castle/siege-trebuchet-demolished.glb", "kind": "length", "size": 5.0, "radius": 2.2},
	{"path": "res://assets/models/kenney_ruins/castle/siege-ballista-demolished.glb", "kind": "length", "size": 3.5, "radius": 1.5},
	{"path": "res://assets/models/kenney_ruins/castle/stairs-stone.glb", "kind": "length", "size": 3.5, "radius": 1.6},
	{"path": "res://assets/models/kenney_ruins/graveyard/stone-wall-damaged.glb", "kind": "length", "size": 4.0, "radius": 1.8},
	{"path": "res://assets/models/kenney_ruins/graveyard/brick-wall-end.glb", "kind": "length", "size": 3.0, "radius": 1.4},
	{"path": "res://assets/models/kenney_ruins/graveyard/column-large.glb", "kind": "height", "size": 4.0, "radius": 0.8},
	{"path": "res://assets/models/kenney_ruins/graveyard/pillar-obelisk.glb", "kind": "height", "size": 4.5, "radius": 0.7},
	{"path": "res://assets/models/kenney_ruins/graveyard/crypt-small.glb", "kind": "height", "size": 3.6, "radius": 2.0},
	{"path": "res://assets/models/kenney_ruins/graveyard/crypt.glb", "kind": "height", "size": 4.5, "radius": 2.6},
	{"path": "res://assets/models/kenney_ruins/graveyard/altar-stone.glb", "kind": "length", "size": 2.6, "radius": 1.2},
	{"path": "res://assets/models/kenney_ruins/town/wall-broken.glb", "kind": "length", "size": 4.0, "radius": 1.8},
	{"path": "res://assets/models/kenney_ruins/town/wall-wood-broken.glb", "kind": "length", "size": 4.0, "radius": 1.8},
	{"path": "res://assets/models/kenney_ruins/town/pillar-stone.glb", "kind": "height", "size": 3.5, "radius": 0.7},
	{"path": "res://assets/models/kenney_ruins/town/chimney-base.glb", "kind": "height", "size": 3.0, "radius": 1.0},
	{"path": "res://assets/models/kenney_ruins/town/fountain-round.glb", "kind": "length", "size": 4.0, "radius": 2.0},
	{"path": "res://assets/models/kenney_ruins/survival/tent.glb", "kind": "length", "size": 3.2, "radius": 1.6},
	{"path": "res://assets/models/kenney_ruins/survival/structure-canvas.glb", "kind": "length", "size": 3.5, "radius": 1.7},
	{"path": "res://assets/models/kenney_ruins/survival/structure-metal.glb", "kind": "length", "size": 3.5, "radius": 1.7},
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
# Ready-to-ship Kenney trees (CC0, self-contained glTF). They are fallback variants even without optional art packs.
const BUILTIN_TREES := [
	{"path": "res://assets/models/kenney_expanded/nature/tree-oak.glb", "kind": "height", "size": 9.0},
	{"path": "res://assets/models/kenney_expanded/nature/tree-detailed.glb", "kind": "height", "size": 9.5},
	{"path": "res://assets/models/kenney_expanded/nature/tree-pinedefaulta.glb", "kind": "height", "size": 10.0},
	{"path": "res://assets/models/kenney_expanded/nature/tree-pineroundb.glb", "kind": "height", "size": 8.0},
	{"path": "res://assets/models/kenney_expanded/nature/tree-default-fall.glb", "kind": "height", "size": 8.5},
	{"path": "res://assets/models/kenney_expanded/nature/tree-pinetalla-detailed.glb", "kind": "height", "size": 11.0},
]

const DECOR_EXTRA := [
	# What a thousand years leave on the ground, each where it belongs (see ChunkView.DECOR): branches, bark, roots and
	# old logs around trees; scree around rocks; boulders as rare accents; painted flowers in the meadows.
	# "scale": random size range; "group": how many smaller copies lie around the first one.
	{"path": "res://assets/models/polyhaven/baked/branches.res", "kind": "length", "size": 1.6, "biomes": ["forest", "swamp", "plains"], "anchor": "tree", "chance": 0.18, "per": [1, 1], "ring": [1.0, 3.5], "scale": [0.5, 1.5]},
	{"path": "res://assets/models/polyhaven/baked/stick_1.res", "kind": "length", "size": 1.2, "biomes": ["forest", "plains", "swamp"], "anchor": "tree", "chance": 0.2, "per": [1, 2], "ring": [0.8, 3.0], "scale": [0.4, 1.4], "group": 2},
	{"path": "res://assets/models/polyhaven/baked/stick_2.res", "kind": "length", "size": 1.5, "biomes": ["forest", "swamp", "plains"], "anchor": "tree", "chance": 0.12, "per": [1, 1], "ring": [1.0, 3.5], "scale": [0.5, 1.5]},
	{"path": "res://assets/models/polyhaven/baked/bark_debris.res", "kind": "length", "size": 0.9, "biomes": ["forest", "swamp"], "anchor": "tree", "chance": 0.1, "per": [1, 1], "ring": [0.5, 2.0], "scale": [0.6, 1.4]},
	{"path": "res://assets/models/polyhaven/baked/old_log.res", "kind": "length", "size": 4.5, "biomes": ["forest", "swamp", "plains"], "anchor": "tree", "chance": 0.03, "per": [1, 1], "ring": [3.0, 6.0], "scale": [0.7, 1.4]},
	{"path": "res://assets/models/polyhaven/baked/roots.res", "kind": "length", "size": 2.0, "biomes": ["forest", "swamp"], "anchor": "tree", "chance": 0.06, "per": [1, 1], "ring": [0.2, 0.8], "scale": [0.6, 1.4]},
	{"path": "res://assets/models/polyhaven/baked/pine_roots.res", "kind": "length", "size": 1.6, "biomes": ["forest", "mountain"], "anchor": "tree", "chance": 0.06, "per": [1, 1], "ring": [0.2, 0.8], "scale": [0.6, 1.4]},
	{"path": "res://assets/models/polyhaven/baked/single_root.res", "kind": "length", "size": 1.2, "biomes": ["forest", "plains"], "anchor": "tree", "chance": 0.08, "per": [1, 1], "ring": [0.3, 1.0], "scale": [0.6, 1.4]},
	{"path": "res://assets/models/polyhaven/baked/boulder_group.res", "kind": "length", "size": 4.0, "biomes": ["plains", "mountain", "forest", "beach"], "anchor": "rare", "chance": 0.2, "per": [1, 1], "ring": [0.0, 0.0], "scale": [0.6, 1.4]},
	{"path": "res://assets/models/polyhaven/baked/rock_group.res", "kind": "length", "size": 2.2, "biomes": ["plains", "mountain", "forest", "beach", "swamp"], "anchor": "rock", "chance": 0.25, "per": [1, 1], "ring": [2.0, 4.0], "scale": [0.5, 1.5]},
	{"path": "res://assets/models/polyhaven/baked/stone_scatter.res", "kind": "length", "size": 1.5, "biomes": ["plains", "mountain", "forest", "beach", "swamp"], "anchor": "rock", "chance": 0.5, "per": [1, 1], "ring": [1.5, 3.5], "scale": [0.6, 1.6]},
	{"path": "res://assets/models/polyhaven/baked/boulder_05.res", "kind": "length", "size": 1.8, "biomes": ["plains", "mountain", "forest"], "anchor": "rare", "chance": 0.35, "per": [1, 1], "ring": [0.0, 0.0], "scale": [0.5, 1.8], "group": 3},
	{"path": "res://assets/models/polyhaven/baked/shore_rocks.res", "kind": "length", "size": 3.0, "biomes": ["beach"], "anchor": "rare", "chance": 0.6, "per": [1, 1], "ring": [0.0, 0.0], "scale": [0.6, 1.5]},
	{"path": "res://assets/models/polyhaven/baked/fallen_trunk.res", "kind": "length", "size": 5.0, "biomes": ["forest", "swamp", "plains"], "anchor": "tree", "chance": 0.03, "per": [1, 1], "ring": [3.0, 6.0], "scale": [0.7, 1.3]},
	{"path": "res://assets/models/polyhaven/baked/stump_2.res", "kind": "length", "size": 1.3, "biomes": ["forest", "plains"], "anchor": "tree", "chance": 0.05, "per": [1, 1], "ring": [3.0, 7.0]},
	{"path": "res://assets/models/polyhaven/baked/rock_7.res", "kind": "length", "size": 1.1, "biomes": ["plains", "forest", "mountain", "beach"], "anchor": "rock", "chance": 0.4, "per": [1, 1], "ring": [2.0, 4.0], "scale": [0.35, 1.9], "group": 2},
	{"path": "res://assets/models/polyhaven/baked/rock_9.res", "kind": "length", "size": 0.8, "biomes": ["forest", "plains", "mountain", "swamp"], "anchor": "rock", "chance": 0.5, "per": [1, 1], "ring": [1.0, 3.0], "scale": [0.3, 1.7], "group": 3},
	{"path": "res://assets/models/polyhaven/baked/dead_trunk.res", "kind": "length", "size": 4.0, "biomes": ["forest", "swamp"], "anchor": "tree", "chance": 0.03, "per": [1, 1], "ring": [3.0, 6.0]},
	{"path": "res://assets/models/polyhaven/baked/tree_stump.res", "kind": "length", "size": 1.5, "biomes": ["forest", "plains", "swamp"], "anchor": "tree", "chance": 0.06, "per": [1, 1], "ring": [3.0, 7.0]},
	{"path": "res://assets/models/polyhaven/baked/mossy_rock_5.res", "kind": "length", "size": 1.4, "biomes": ["forest", "plains", "mountain", "beach"], "anchor": "rock", "chance": 0.3, "per": [1, 1], "ring": [2.0, 4.0], "scale": [0.4, 1.8], "group": 2},
	{"path": "loose/low_poly_tree_log_and_stump.glb", "node": "Object_7", "kind": "length", "size": 1.6, "biomes": ["forest", "swamp"], "anchor": "tree", "chance": 0.04, "per": [1, 1], "ring": [2.5, 6.0]},
	{"path": "loose/low_poly_tree_log_and_stump.glb", "node": "Object_11", "kind": "length", "size": 1.6, "biomes": ["forest", "plains"], "anchor": "tree", "chance": 0.04, "per": [1, 1], "ring": [2.5, 6.0]},
	{"path": "loose/the_ancient_mystic_stone.glb", "node": "LP_Stone_Main_0", "kind": "height", "size": 2.4, "biomes": ["forest", "plains", "mountain"], "anchor": "rare", "chance": 0.1, "per": [1, 1], "ring": [0.0, 0.0]},
	{"path": "loose/flowers_pack_1.glb", "node": "Plane_036_lowPoly_flor1_003_0", "kind": "height", "size": 0.9, "biomes": ["plains", "forest"], "anchor": "meadow", "chance": 0.8, "per": [3, 6], "ring": [1.0, 5.0]},
	{"path": "loose/flowers_pack_1.glb", "node": "Plane_022_lowPoly_flor25_0", "kind": "height", "size": 0.9, "biomes": ["plains"], "anchor": "meadow", "chance": 0.8, "per": [3, 6], "ring": [1.0, 5.0]},
	{"path": "loose/flowers_pack_1.glb", "node": "Plane_001_lowPoly_flor21_0", "kind": "height", "size": 1.0, "biomes": ["plains", "forest"], "anchor": "meadow", "chance": 0.8, "per": [3, 6], "ring": [1.0, 5.0]},
	# Kenney Nature Kit: flowers, mushrooms and woodland clutter. All sizes are in metres after baking.
	{"path": "res://assets/models/kenney_expanded/nature/flower-purpleb.glb", "kind": "height", "size": 0.45, "biomes": ["forest", "plains"], "anchor": "meadow", "chance": 0.65, "per": [2, 4], "ring": [0.4, 5.0], "scale": [0.8, 1.2]},
	{"path": "res://assets/models/kenney_expanded/nature/flower-redb.glb", "kind": "height", "size": 0.4, "biomes": ["plains", "forest"], "anchor": "meadow", "chance": 0.48, "per": [2, 3], "ring": [0.5, 4.5], "scale": [0.7, 1.3]},
	{"path": "res://assets/models/kenney_expanded/nature/flower-yellowb.glb", "kind": "height", "size": 0.5, "biomes": ["plains", "forest"], "anchor": "meadow", "chance": 0.6, "per": [2, 4], "ring": [0.5, 5.5], "scale": [0.7, 1.2]},
	{"path": "res://assets/models/kenney_expanded/nature/mushroom-redgroup.glb", "kind": "height", "size": 0.4, "biomes": ["forest", "swamp"], "anchor": "tree", "chance": 0.12, "per": [1, 2], "ring": [0.5, 2.3], "scale": [0.7, 1.2]},
	{"path": "res://assets/models/kenney_expanded/nature/mushroom-tangroup.glb", "kind": "height", "size": 0.35, "biomes": ["forest", "swamp"], "anchor": "tree", "chance": 0.16, "per": [1, 2], "ring": [0.4, 2.0], "scale": [0.6, 1.3]},
	{"path": "res://assets/models/kenney_expanded/nature/plant-bushdetailed.glb", "kind": "height", "size": 1.2, "biomes": ["forest", "plains", "swamp"], "anchor": "tree", "chance": 0.13, "per": [1, 2], "ring": [1.4, 4.0], "scale": [0.8, 1.3]},
	{"path": "res://assets/models/kenney_expanded/nature/plant-bushlarge.glb", "kind": "height", "size": 1.5, "biomes": ["forest", "plains"], "anchor": "tree", "chance": 0.1, "per": [1, 1], "ring": [1.8, 4.5], "scale": [0.8, 1.2]},
	{"path": "res://assets/models/kenney_expanded/nature/stump-old.glb", "kind": "height", "size": 0.75, "biomes": ["forest", "plains", "swamp"], "anchor": "tree", "chance": 0.09, "per": [1, 1], "ring": [3.0, 6.5], "scale": [0.7, 1.3]},
	{"path": "res://assets/models/kenney_expanded/nature/log-stack.glb", "kind": "length", "size": 1.8, "biomes": ["forest", "plains"], "anchor": "tree", "chance": 0.04, "per": [1, 1], "ring": [4.0, 7.0], "scale": [0.8, 1.3]},
	{"path": "res://assets/models/kenney_expanded/nature/campfire-stones.glb", "kind": "length", "size": 1.5, "biomes": ["forest", "plains"], "anchor": "rare", "chance": 0.05, "per": [1, 1], "ring": [0.0, 0.0], "scale": [0.8, 1.1]},
	# Abandoned and zombie-infested ruins receive localized remnants, not uniform open-world scatter.
	{"path": "res://assets/models/kenney_expanded/graveyard/gravestone-broken.glb", "kind": "height", "size": 0.9, "biomes": ["forest", "plains", "swamp"], "anchor": "ruin", "chance": 0.24, "per": [1, 2], "ring": [4.0, 9.0], "scale": [0.8, 1.3]},
	{"path": "res://assets/models/kenney_expanded/graveyard/gravestone-cross-large.glb", "kind": "height", "size": 1.5, "biomes": ["forest", "plains"], "anchor": "ruin", "chance": 0.14, "per": [1, 1], "ring": [5.0, 9.0], "scale": [0.8, 1.2]},
	{"path": "res://assets/models/kenney_expanded/graveyard/gravestone-round.glb", "kind": "height", "size": 0.85, "biomes": ["forest", "plains", "swamp"], "anchor": "ruin", "chance": 0.18, "per": [1, 1], "ring": [4.5, 8.0], "scale": [0.8, 1.2]},
	{"path": "res://assets/models/kenney_expanded/graveyard/grave-border.glb", "kind": "length", "size": 1.8, "biomes": ["forest", "plains"], "anchor": "ruin", "chance": 0.1, "per": [1, 1], "ring": [4.0, 8.0], "scale": [0.9, 1.2]},
	{"path": "res://assets/models/kenney_expanded/graveyard/coffin-old.glb", "kind": "length", "size": 1.6, "biomes": ["forest", "plains", "swamp"], "anchor": "ruin", "chance": 0.13, "per": [1, 1], "ring": [3.5, 7.0], "scale": [0.8, 1.2]},
	{"path": "res://assets/models/kenney_expanded/graveyard/fence-damaged.glb", "kind": "length", "size": 2.5, "biomes": ["forest", "plains"], "anchor": "ruin", "chance": 0.14, "per": [1, 2], "ring": [5.0, 9.0], "scale": [0.9, 1.2]},
	{"path": "res://assets/models/kenney_expanded/graveyard/bench-damaged.glb", "kind": "length", "size": 1.8, "biomes": ["forest", "plains"], "anchor": "ruin", "chance": 0.09, "per": [1, 1], "ring": [5.0, 8.0], "scale": [0.8, 1.2]},
	{"path": "res://assets/models/kenney_expanded/graveyard/pine-fall.glb", "kind": "height", "size": 6.0, "biomes": ["forest", "swamp"], "anchor": "ruin", "chance": 0.05, "per": [1, 1], "ring": [7.0, 11.0], "scale": [0.7, 1.0]},
	{"path": "res://assets/models/kenney_expanded/castle/siege-catapult-demolished.glb", "kind": "length", "size": 4.0, "biomes": ["plains", "forest"], "anchor": "ruin", "chance": 0.035, "per": [1, 1], "ring": [8.0, 13.0], "scale": [0.8, 1.2]},
	{"path": "res://assets/models/kenney_expanded/castle/siege-ram-demolished.glb", "kind": "length", "size": 3.0, "biomes": ["plains", "forest"], "anchor": "ruin", "chance": 0.04, "per": [1, 1], "ring": [7.0, 12.0], "scale": [0.8, 1.2]},
	# Kenney Nature Kit (CC0): wildflowers, mushrooms, stumps, logs, bushes, rocks, old campfires.
	{"path": "res://assets/models/kenney_nature/flower_yellowA.glb", "kind": "height", "size": 0.35, "biomes": ["plains", "forest"], "anchor": "meadow", "chance": 0.18, "per": [2, 5], "ring": [0.5, 5.0], "scale": [0.8, 1.3]},
	{"path": "res://assets/models/kenney_nature/flower_yellowB.glb", "kind": "height", "size": 0.35, "biomes": ["plains", "forest"], "anchor": "meadow", "chance": 0.18, "per": [2, 5], "ring": [0.5, 5.0], "scale": [0.8, 1.3]},
	{"path": "res://assets/models/kenney_nature/flower_yellowC.glb", "kind": "height", "size": 0.35, "biomes": ["plains", "forest"], "anchor": "meadow", "chance": 0.18, "per": [2, 5], "ring": [0.5, 5.0], "scale": [0.8, 1.3]},
	{"path": "res://assets/models/kenney_nature/flower_purpleA.glb", "kind": "height", "size": 0.35, "biomes": ["plains", "forest"], "anchor": "meadow", "chance": 0.18, "per": [2, 5], "ring": [0.5, 5.0], "scale": [0.8, 1.3]},
	{"path": "res://assets/models/kenney_nature/flower_purpleB.glb", "kind": "height", "size": 0.35, "biomes": ["plains", "forest"], "anchor": "meadow", "chance": 0.18, "per": [2, 5], "ring": [0.5, 5.0], "scale": [0.8, 1.3]},
	{"path": "res://assets/models/kenney_nature/flower_purpleC.glb", "kind": "height", "size": 0.35, "biomes": ["plains", "forest"], "anchor": "meadow", "chance": 0.18, "per": [2, 5], "ring": [0.5, 5.0], "scale": [0.8, 1.3]},
	{"path": "res://assets/models/kenney_nature/flower_redA.glb", "kind": "height", "size": 0.35, "biomes": ["plains", "forest"], "anchor": "meadow", "chance": 0.18, "per": [2, 5], "ring": [0.5, 5.0], "scale": [0.8, 1.3]},
	{"path": "res://assets/models/kenney_nature/flower_redB.glb", "kind": "height", "size": 0.35, "biomes": ["plains", "forest"], "anchor": "meadow", "chance": 0.18, "per": [2, 5], "ring": [0.5, 5.0], "scale": [0.8, 1.3]},
	{"path": "res://assets/models/kenney_nature/flower_redC.glb", "kind": "height", "size": 0.35, "biomes": ["plains", "forest"], "anchor": "meadow", "chance": 0.18, "per": [2, 5], "ring": [0.5, 5.0], "scale": [0.8, 1.3]},
	{"path": "res://assets/models/kenney_nature/mushroom_red.glb", "kind": "height", "size": 0.3, "biomes": ["forest", "swamp"], "anchor": "tree", "chance": 0.08, "per": [1, 3], "ring": [0.4, 1.8], "scale": [0.8, 1.3]},
	{"path": "res://assets/models/kenney_nature/mushroom_redGroup.glb", "kind": "height", "size": 0.3, "biomes": ["forest", "swamp"], "anchor": "tree", "chance": 0.08, "per": [1, 3], "ring": [0.4, 1.8], "scale": [0.8, 1.3]},
	{"path": "res://assets/models/kenney_nature/mushroom_tan.glb", "kind": "height", "size": 0.3, "biomes": ["forest", "swamp"], "anchor": "tree", "chance": 0.08, "per": [1, 3], "ring": [0.4, 1.8], "scale": [0.8, 1.3]},
	{"path": "res://assets/models/kenney_nature/mushroom_tanGroup.glb", "kind": "height", "size": 0.3, "biomes": ["forest", "swamp"], "anchor": "tree", "chance": 0.08, "per": [1, 3], "ring": [0.4, 1.8], "scale": [0.8, 1.3]},
	{"path": "res://assets/models/kenney_nature/mushroom_redTall.glb", "kind": "height", "size": 0.3, "biomes": ["forest", "swamp"], "anchor": "tree", "chance": 0.08, "per": [1, 3], "ring": [0.4, 1.8], "scale": [0.8, 1.3]},
	{"path": "res://assets/models/kenney_nature/mushroom_tanTall.glb", "kind": "height", "size": 0.3, "biomes": ["forest", "swamp"], "anchor": "tree", "chance": 0.08, "per": [1, 3], "ring": [0.4, 1.8], "scale": [0.8, 1.3]},
	{"path": "res://assets/models/kenney_nature/stump_old.glb", "kind": "height", "size": 0.7, "biomes": ["forest", "swamp", "plains"], "anchor": "tree", "chance": 0.04, "per": [1, 1], "ring": [3.0, 7.0], "scale": [0.8, 1.3]},
	{"path": "res://assets/models/kenney_nature/stump_oldTall.glb", "kind": "height", "size": 0.7, "biomes": ["forest", "swamp", "plains"], "anchor": "tree", "chance": 0.04, "per": [1, 1], "ring": [3.0, 7.0], "scale": [0.8, 1.3]},
	{"path": "res://assets/models/kenney_nature/stump_roundDetailed.glb", "kind": "height", "size": 0.7, "biomes": ["forest", "swamp", "plains"], "anchor": "tree", "chance": 0.04, "per": [1, 1], "ring": [3.0, 7.0], "scale": [0.8, 1.3]},
	{"path": "res://assets/models/kenney_nature/stump_squareDetailed.glb", "kind": "height", "size": 0.7, "biomes": ["forest", "swamp", "plains"], "anchor": "tree", "chance": 0.04, "per": [1, 1], "ring": [3.0, 7.0], "scale": [0.8, 1.3]},
	{"path": "res://assets/models/kenney_nature/log.glb", "kind": "length", "size": 2.2, "biomes": ["forest", "swamp", "plains"], "anchor": "tree", "chance": 0.035, "per": [1, 1], "ring": [3.0, 8.0], "scale": [0.8, 1.3]},
	{"path": "res://assets/models/kenney_nature/log_large.glb", "kind": "length", "size": 2.2, "biomes": ["forest", "swamp", "plains"], "anchor": "tree", "chance": 0.035, "per": [1, 1], "ring": [3.0, 8.0], "scale": [0.8, 1.3]},
	{"path": "res://assets/models/kenney_nature/log_stack.glb", "kind": "length", "size": 2.2, "biomes": ["forest", "swamp", "plains"], "anchor": "tree", "chance": 0.035, "per": [1, 1], "ring": [3.0, 8.0], "scale": [0.8, 1.3]},
	{"path": "res://assets/models/kenney_nature/plant_bush.glb", "kind": "height", "size": 0.9, "biomes": ["forest", "swamp", "plains"], "anchor": "tree", "chance": 0.06, "per": [1, 2], "ring": [1.5, 5.0], "scale": [0.8, 1.3]},
	{"path": "res://assets/models/kenney_nature/plant_bushDetailed.glb", "kind": "height", "size": 0.9, "biomes": ["forest", "swamp", "plains"], "anchor": "tree", "chance": 0.06, "per": [1, 2], "ring": [1.5, 5.0], "scale": [0.8, 1.3]},
	{"path": "res://assets/models/kenney_nature/plant_bushLarge.glb", "kind": "height", "size": 0.9, "biomes": ["forest", "swamp", "plains"], "anchor": "tree", "chance": 0.06, "per": [1, 2], "ring": [1.5, 5.0], "scale": [0.8, 1.3]},
	{"path": "res://assets/models/kenney_nature/plant_bushSmall.glb", "kind": "height", "size": 0.9, "biomes": ["forest", "swamp", "plains"], "anchor": "tree", "chance": 0.06, "per": [1, 2], "ring": [1.5, 5.0], "scale": [0.8, 1.3]},
	{"path": "res://assets/models/kenney_nature/plant_bushTriangle.glb", "kind": "height", "size": 0.9, "biomes": ["forest", "swamp", "plains"], "anchor": "tree", "chance": 0.06, "per": [1, 2], "ring": [1.5, 5.0], "scale": [0.8, 1.3]},
	{"path": "res://assets/models/kenney_nature/plant_flatTall.glb", "kind": "height", "size": 0.5, "biomes": ["forest", "swamp", "plains"], "anchor": "meadow", "chance": 0.08, "per": [1, 3], "ring": [1.0, 6.0], "scale": [0.8, 1.3]},
	{"path": "res://assets/models/kenney_nature/plant_flatShort.glb", "kind": "height", "size": 0.5, "biomes": ["forest", "swamp", "plains"], "anchor": "meadow", "chance": 0.08, "per": [1, 3], "ring": [1.0, 6.0], "scale": [0.8, 1.3]},
	{"path": "res://assets/models/kenney_nature/grass_large.glb", "kind": "height", "size": 0.5, "biomes": ["forest", "swamp", "plains"], "anchor": "meadow", "chance": 0.08, "per": [1, 3], "ring": [1.0, 6.0], "scale": [0.8, 1.3]},
	{"path": "res://assets/models/kenney_nature/grass_leafsLarge.glb", "kind": "height", "size": 0.5, "biomes": ["forest", "swamp", "plains"], "anchor": "meadow", "chance": 0.08, "per": [1, 3], "ring": [1.0, 6.0], "scale": [0.8, 1.3]},
	{"path": "res://assets/models/kenney_nature/rock_tallA.glb", "kind": "height", "size": 1.4, "biomes": ["plains", "forest", "mountain", "beach"], "anchor": "rock", "chance": 0.06, "per": [1, 2], "ring": [2.0, 5.0], "scale": [0.8, 1.3]},
	{"path": "res://assets/models/kenney_nature/rock_tallC.glb", "kind": "height", "size": 1.4, "biomes": ["plains", "forest", "mountain", "beach"], "anchor": "rock", "chance": 0.06, "per": [1, 2], "ring": [2.0, 5.0], "scale": [0.8, 1.3]},
	{"path": "res://assets/models/kenney_nature/rock_tallE.glb", "kind": "height", "size": 1.4, "biomes": ["plains", "forest", "mountain", "beach"], "anchor": "rock", "chance": 0.06, "per": [1, 2], "ring": [2.0, 5.0], "scale": [0.8, 1.3]},
	{"path": "res://assets/models/kenney_nature/stone_tallA.glb", "kind": "height", "size": 1.4, "biomes": ["plains", "forest", "mountain", "beach"], "anchor": "rock", "chance": 0.06, "per": [1, 2], "ring": [2.0, 5.0], "scale": [0.8, 1.3]},
	{"path": "res://assets/models/kenney_nature/stone_tallC.glb", "kind": "height", "size": 1.4, "biomes": ["plains", "forest", "mountain", "beach"], "anchor": "rock", "chance": 0.06, "per": [1, 2], "ring": [2.0, 5.0], "scale": [0.8, 1.3]},
	{"path": "res://assets/models/kenney_nature/stone_tallF.glb", "kind": "height", "size": 1.4, "biomes": ["plains", "forest", "mountain", "beach"], "anchor": "rock", "chance": 0.06, "per": [1, 2], "ring": [2.0, 5.0], "scale": [0.8, 1.3]},
	{"path": "res://assets/models/kenney_nature/rock_largeA.glb", "kind": "length", "size": 2.2, "biomes": ["plains", "forest", "mountain", "beach"], "anchor": "rare", "chance": 0.08, "per": [1, 1], "ring": [0.0, 0.0], "scale": [0.8, 1.3]},
	{"path": "res://assets/models/kenney_nature/rock_largeC.glb", "kind": "length", "size": 2.2, "biomes": ["plains", "forest", "mountain", "beach"], "anchor": "rare", "chance": 0.08, "per": [1, 1], "ring": [0.0, 0.0], "scale": [0.8, 1.3]},
	{"path": "res://assets/models/kenney_nature/rock_largeF.glb", "kind": "length", "size": 2.2, "biomes": ["plains", "forest", "mountain", "beach"], "anchor": "rare", "chance": 0.08, "per": [1, 1], "ring": [0.0, 0.0], "scale": [0.8, 1.3]},
	{"path": "res://assets/models/kenney_nature/stone_largeA.glb", "kind": "length", "size": 2.2, "biomes": ["plains", "forest", "mountain", "beach"], "anchor": "rare", "chance": 0.08, "per": [1, 1], "ring": [0.0, 0.0], "scale": [0.8, 1.3]},
	{"path": "res://assets/models/kenney_nature/stone_largeB.glb", "kind": "length", "size": 2.2, "biomes": ["plains", "forest", "mountain", "beach"], "anchor": "rare", "chance": 0.08, "per": [1, 1], "ring": [0.0, 0.0], "scale": [0.8, 1.3]},
	{"path": "res://assets/models/kenney_nature/campfire_stones.glb", "kind": "length", "size": 1.3, "biomes": ["plains", "forest"], "anchor": "ruin", "chance": 0.08, "per": [1, 1], "ring": [3.0, 9.0], "scale": [0.8, 1.3]},
	{"path": "res://assets/models/kenney_nature/campfire_logs.glb", "kind": "length", "size": 1.3, "biomes": ["plains", "forest"], "anchor": "ruin", "chance": 0.08, "per": [1, 1], "ring": [3.0, 9.0], "scale": [0.8, 1.3]},
	{"path": "res://assets/models/kenney_nature/crop_pumpkin.glb", "kind": "length", "size": 1.3, "biomes": ["plains", "forest"], "anchor": "ruin", "chance": 0.08, "per": [1, 1], "ring": [3.0, 9.0], "scale": [0.8, 1.3]},
	# Clutter around ruins from the Kenney kits (no collision).
	{"path": "res://assets/models/kenney_ruins/graveyard/gravestone-broken.glb", "kind": "length", "size": 1.0, "biomes": ["plains", "forest", "swamp"], "anchor": "ruin", "chance": 0.12, "per": [1, 2], "ring": [2.0, 12.0], "scale": [0.8, 1.2]},
	{"path": "res://assets/models/kenney_ruins/graveyard/gravestone-debris.glb", "kind": "length", "size": 0.9, "biomes": ["plains", "forest", "swamp"], "anchor": "ruin", "chance": 0.12, "per": [1, 2], "ring": [2.0, 12.0], "scale": [0.8, 1.2]},
	{"path": "res://assets/models/kenney_ruins/graveyard/debris.glb", "kind": "length", "size": 1.4, "biomes": ["plains", "forest", "mountain", "swamp"], "anchor": "ruin", "chance": 0.12, "per": [1, 2], "ring": [2.0, 12.0], "scale": [0.8, 1.2]},
	{"path": "res://assets/models/kenney_ruins/graveyard/debris-wood.glb", "kind": "length", "size": 1.6, "biomes": ["plains", "forest", "swamp"], "anchor": "ruin", "chance": 0.12, "per": [1, 2], "ring": [2.0, 12.0], "scale": [0.8, 1.2]},
	{"path": "res://assets/models/kenney_ruins/graveyard/iron-fence-damaged.glb", "kind": "length", "size": 2.0, "biomes": ["plains", "forest", "swamp"], "anchor": "ruin", "chance": 0.12, "per": [1, 2], "ring": [2.0, 12.0], "scale": [0.8, 1.2]},
	{"path": "res://assets/models/kenney_ruins/graveyard/fence-damaged.glb", "kind": "length", "size": 2.0, "biomes": ["plains", "forest"], "anchor": "ruin", "chance": 0.12, "per": [1, 2], "ring": [2.0, 12.0], "scale": [0.8, 1.2]},
	{"path": "res://assets/models/kenney_ruins/graveyard/bench-damaged.glb", "kind": "length", "size": 1.6, "biomes": ["plains", "forest"], "anchor": "ruin", "chance": 0.12, "per": [1, 2], "ring": [2.0, 12.0], "scale": [0.8, 1.2]},
	{"path": "res://assets/models/kenney_ruins/graveyard/fire-basket.glb", "kind": "length", "size": 1.2, "biomes": ["plains", "forest", "mountain"], "anchor": "ruin", "chance": 0.12, "per": [1, 2], "ring": [2.0, 12.0], "scale": [0.8, 1.2]},
	{"path": "res://assets/models/kenney_ruins/graveyard/rocks-tall.glb", "kind": "length", "size": 1.4, "biomes": ["plains", "mountain", "forest"], "anchor": "ruin", "chance": 0.12, "per": [1, 2], "ring": [2.0, 12.0], "scale": [0.8, 1.2]},
	{"path": "res://assets/models/kenney_ruins/graveyard/cross-column.glb", "kind": "length", "size": 1.8, "biomes": ["plains", "forest", "swamp"], "anchor": "ruin", "chance": 0.12, "per": [1, 2], "ring": [2.0, 12.0], "scale": [0.8, 1.2]},
	{"path": "res://assets/models/kenney_ruins/town/fence-broken.glb", "kind": "length", "size": 2.0, "biomes": ["plains", "forest"], "anchor": "ruin", "chance": 0.12, "per": [1, 2], "ring": [2.0, 12.0], "scale": [0.8, 1.2]},
	{"path": "res://assets/models/kenney_ruins/town/cart.glb", "kind": "length", "size": 2.4, "biomes": ["plains", "forest"], "anchor": "ruin", "chance": 0.12, "per": [1, 2], "ring": [2.0, 12.0], "scale": [0.8, 1.2]},
	{"path": "res://assets/models/kenney_ruins/town/cart-high.glb", "kind": "length", "size": 2.4, "biomes": ["plains"], "anchor": "ruin", "chance": 0.12, "per": [1, 2], "ring": [2.0, 12.0], "scale": [0.8, 1.2]},
	{"path": "res://assets/models/kenney_ruins/town/stall-red.glb", "kind": "length", "size": 2.6, "biomes": ["plains"], "anchor": "ruin", "chance": 0.12, "per": [1, 2], "ring": [2.0, 12.0], "scale": [0.8, 1.2]},
	{"path": "res://assets/models/kenney_ruins/town/planks.glb", "kind": "length", "size": 1.6, "biomes": ["plains", "forest", "swamp"], "anchor": "ruin", "chance": 0.12, "per": [1, 2], "ring": [2.0, 12.0], "scale": [0.8, 1.2]},
	{"path": "res://assets/models/kenney_ruins/castle/rocks-large.glb", "kind": "length", "size": 2.0, "biomes": ["plains", "mountain", "forest"], "anchor": "ruin", "chance": 0.12, "per": [1, 2], "ring": [2.0, 12.0], "scale": [0.8, 1.2]},
	{"path": "res://assets/models/kenney_ruins/survival/campfire-pit.glb", "kind": "length", "size": 1.4, "biomes": ["plains", "forest", "mountain"], "anchor": "ruin", "chance": 0.12, "per": [1, 2], "ring": [2.0, 12.0], "scale": [0.8, 1.2]},
	{"path": "res://assets/models/kenney_ruins/survival/signpost.glb", "kind": "length", "size": 1.8, "biomes": ["plains", "forest"], "anchor": "ruin", "chance": 0.12, "per": [1, 2], "ring": [2.0, 12.0], "scale": [0.8, 1.2]},
	{"path": "res://assets/models/kenney_ruins/survival/box-large.glb", "kind": "length", "size": 1.0, "biomes": ["plains", "forest", "mountain"], "anchor": "ruin", "chance": 0.12, "per": [1, 2], "ring": [2.0, 12.0], "scale": [0.8, 1.2]},
	{"path": "res://assets/models/kenney_ruins/survival/barrel.glb", "kind": "length", "size": 1.0, "biomes": ["plains", "forest", "mountain"], "anchor": "ruin", "chance": 0.12, "per": [1, 2], "ring": [2.0, 12.0], "scale": [0.8, 1.2]},
	{"path": "res://assets/models/kenney_ruins/survival/chest.glb", "kind": "length", "size": 0.9, "biomes": ["plains", "forest", "mountain"], "anchor": "ruin", "chance": 0.12, "per": [1, 2], "ring": [2.0, 12.0], "scale": [0.8, 1.2]},
	{"path": "res://assets/models/kenney_ruins/survival/bedroll-frame.glb", "kind": "length", "size": 1.6, "biomes": ["plains", "forest"], "anchor": "ruin", "chance": 0.12, "per": [1, 2], "ring": [2.0, 12.0], "scale": [0.8, 1.2]},
	{"path": "res://assets/models/kenney_ruins/survival/resource-planks.glb", "kind": "length", "size": 1.4, "biomes": ["plains", "forest"], "anchor": "ruin", "chance": 0.12, "per": [1, 2], "ring": [2.0, 12.0], "scale": [0.8, 1.2]},
	{"path": "res://assets/models/kenney_ruins/survival/tree-log.glb", "kind": "length", "size": 2.4, "biomes": ["forest", "plains", "swamp"], "anchor": "ruin", "chance": 0.12, "per": [1, 2], "ring": [2.0, 12.0], "scale": [0.8, 1.2]},
	{"path": "res://assets/models/kenney_ruins/survival/fence-fortified.glb", "kind": "length", "size": 2.4, "biomes": ["plains", "forest", "mountain"], "anchor": "ruin", "chance": 0.12, "per": [1, 2], "ring": [2.0, 12.0], "scale": [0.8, 1.2]},
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
		# Baked .res props carry no LODs; give them generated ones so scattered copies are not full detail at range.
		var baked: Mesh = bake(String(entry["path"]), String(entry.get("node", "")), String(entry["kind"]), float(entry["size"]), String(entry.get("tex", "")))
		_cache[key] = MeshLOD.with_generated_lods(MeshLOD.with_triangle_budget(baked, triangle_budget(entry)))
		var named: Mesh = _cache[key]
		if named != null and named.resource_path == "" and named.resource_name == "":
			named.resource_name = String(entry["path"]).get_file() # Names the geometry in benchmark breakdowns.
	return _cache[key]


## Small scattered props (roots, bark, sticks under 2.5 m) were scanned at 1–3k triangles and hundreds are on
## screen at once; ~400 per metre keeps their silhouette. Larger models keep full detail (0 = no budget).
static func triangle_budget(entry: Dictionary) -> int:
	if entry.has("triangles"):
		return int(entry["triangles"])
	var size: float = float(entry.get("size", 0.0))
	if String(entry.get("kind", "")) == "footprint" or size <= 0.0 or size > 2.5:
		return 0
	return maxi(200, int(size * 400.0))


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
	# The importer LOD thresholds describe geometric error in source units.
	# Account for the node hierarchy's nonuniform scale conservatively.
	var world_scale: float = factor * maxf(
		maxf(transform.basis.x.length(), transform.basis.y.length()), transform.basis.z.length())
	var baked := ArrayMesh.new()
	var texture: Texture2D = null
	if texture_path != "":
		texture = load(PACKS + texture_path) as Texture2D
	for surface in source.mesh.get_surface_count():
		var arrays: Array = source.mesh.surface_get_arrays(surface)
		# Imported scenes can override materials per mesh instance.
		var material: Material = source.get_surface_override_material(surface)
		if material == null:
			material = source.mesh.surface_get_material(surface)
		# Generate MikkTSpace using original UVs, normals and model-space
		# positions. Applying the scene transform first would rotate twice.
		if texture == null and MeshPBR.needs_tangents(material):
			MeshPBR.ensure_tangents(arrays)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var moved := PackedVector3Array()
		moved.resize(vertices.size())
		for i in vertices.size():
			moved[i] = ((transform * vertices[i]) + offset) * factor
		arrays[Mesh.ARRAY_VERTEX] = moved
		var tangent_frame_valid: bool = MeshPBR.transform_frame(arrays, transform.basis)
		baked.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], MeshLOD.copy_lods(source.mesh, surface, world_scale))
		if texture != null:
			var painted := StandardMaterial3D.new()
			painted.albedo_texture = texture
			painted.roughness = 0.9
			painted.cull_mode = BaseMaterial3D.CULL_DISABLED
			material = painted
		else:
			# Preserve source roughness, metalness, normal maps and ORM textures.
			# Keep dungeon's intentional hand-painted palette as a separate opt-in.
			material = MeshPBR.material_for_bake(material, tangent_frame_valid,
				path.begins_with("dungeon/"), StoneMicrodetail.is_masonry_path(path))
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
		var material: Material = source.surface_get_material(surface)
		if MeshPBR.needs_tangents(material):
			# Baked .res meshes are a live path for rocks and world decoration.
			# Never attach a normal-mapped material to tangentless geometry.
			var valid_frame: bool = MeshPBR.ensure_tangents(arrays)
			material = MeshPBR.material_for_bake(material, valid_frame)
		fitted.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], MeshLOD.copy_lods(source, surface, factor))
		fitted.surface_set_material(surface, material)
	return fitted


# Scanned rocks from Poly Haven, used before the stylised ones when present.
const SCANNED_ROCKS := ["boulder_01", "boulder_02", "boulder_04", "mossy_rock_1", "mossy_rock_2", "mossy_rock_3", "mossy_rock_4", "mossy_rock_5", "mossy_rock_6"]


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
		result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], MeshLOD.copy_lods(source, surface, factor))
		var material := StandardMaterial3D.new()
		material.albedo_texture = texture
		material.roughness = 0.9
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		result.surface_set_material(surface, material)
	return result
