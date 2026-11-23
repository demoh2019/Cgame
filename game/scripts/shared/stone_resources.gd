extends RefCounted
## Authoritative loose-stone visuals. Kept as plain data: dedicated servers do
## not load any art, while clients resolve each entry with ModelCatalog.
## These replace the old purely cosmetic rock and pebble scatters.

const MODELS := [
	{"nature": "Pebble_Round_1", "size": 0.35, "biomes": ["forest", "plains", "beach", "mountain", "swamp"]},
	{"nature": "Pebble_Square_2", "size": 0.35, "biomes": ["plains", "beach", "mountain"]},
	{"path": "res://assets/models/polyhaven/baked/boulder_group.res", "kind": "length", "size": 4.0, "biomes": ["plains", "mountain", "forest", "beach"], "anchor": "rare", "chance": 0.2, "per": [1, 1], "ring": [0.0, 0.0], "scale": [0.6, 1.4]},
	{"path": "res://assets/models/polyhaven/baked/rock_group.res", "kind": "length", "size": 2.2, "biomes": ["plains", "mountain", "forest", "beach", "swamp"], "anchor": "rock", "chance": 0.25, "per": [1, 1], "ring": [2.0, 4.0], "scale": [0.5, 1.5]},
	{"path": "res://assets/models/polyhaven/baked/stone_scatter.res", "kind": "length", "size": 1.5, "biomes": ["plains", "mountain", "forest", "beach", "swamp"], "anchor": "rock", "chance": 0.5, "per": [1, 1], "ring": [1.5, 3.5], "scale": [0.6, 1.6]},
	{"path": "res://assets/models/polyhaven/baked/boulder_05.res", "kind": "length", "size": 1.8, "biomes": ["plains", "mountain", "forest"], "anchor": "rare", "chance": 0.35, "per": [1, 1], "ring": [0.0, 0.0], "scale": [0.5, 1.8], "group": 3},
	{"path": "res://assets/models/polyhaven/baked/shore_rocks.res", "kind": "length", "size": 3.0, "biomes": ["beach"], "anchor": "rare", "chance": 0.6, "per": [1, 1], "ring": [0.0, 0.0], "scale": [0.6, 1.5]},
	{"path": "res://assets/models/polyhaven/baked/rock_7.res", "kind": "length", "size": 1.1, "biomes": ["plains", "forest", "mountain", "beach"], "anchor": "rock", "chance": 0.4, "per": [1, 1], "ring": [2.0, 4.0], "scale": [0.35, 1.9], "group": 2},
	{"path": "res://assets/models/polyhaven/baked/rock_9.res", "kind": "length", "size": 0.8, "biomes": ["forest", "plains", "mountain", "swamp"], "anchor": "rock", "chance": 0.5, "per": [1, 1], "ring": [1.0, 3.0], "scale": [0.3, 1.7], "group": 3},
	{"path": "res://assets/models/polyhaven/baked/mossy_rock_5.res", "kind": "length", "size": 1.4, "biomes": ["forest", "plains", "mountain", "beach"], "anchor": "rock", "chance": 0.3, "per": [1, 1], "ring": [2.0, 4.0], "scale": [0.4, 1.8], "group": 2},
	{"path": "loose/the_ancient_mystic_stone.glb", "node": "LP_Stone_Main_0", "kind": "height", "size": 2.4, "biomes": ["forest", "plains", "mountain"], "anchor": "rare", "chance": 0.1, "per": [1, 1], "ring": [0.0, 0.0]},
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
	{"path": "res://assets/models/kenney_ruins/graveyard/rocks-tall.glb", "kind": "length", "size": 1.4, "biomes": ["plains", "mountain", "forest"], "anchor": "ruin", "chance": 0.12, "per": [1, 2], "ring": [2.0, 12.0], "scale": [0.8, 1.2]},
	{"path": "res://assets/models/kenney_ruins/castle/rocks-large.glb", "kind": "length", "size": 2.0, "biomes": ["plains", "mountain", "forest"], "anchor": "ruin", "chance": 0.12, "per": [1, 2], "ring": [2.0, 12.0], "scale": [0.8, 1.2]},
]


## Only freestanding rocks are gathered; gravestones, walls and campfire props
## remain scenery because they are constructed objects rather than stone deposits.
static func is_loose_stone_entry(entry: Dictionary) -> bool:
	var filename: String = str(entry.get("path", "")).get_file().to_lower()
	if filename.begins_with("gravestone") or filename.contains("stone-wall") or filename.contains("campfire"):
		return false
	return filename.contains("rock") or filename.contains("stone") or filename.contains("boulder")


## Both nature-kit pebbles are truly hand-sized; every imported stone,
## including small rock_9 and stone_scatter, is a solid mineable model.
## Do not classify a 1.5-metre imported stone as a hand pickup by threshold.
## The same seeded selection runs on clients and dedicated servers.
static func pick_model(biome: String, small: bool, rng: RandomNumberGenerator) -> int:
	var choices: Array[int] = []
	for index in MODELS.size():
		var entry: Dictionary = MODELS[index]
		if not (biome in entry["biomes"]):
			continue
		if small != entry.has("nature"):
			continue
		choices.append(index)
	return choices[rng.randi_range(0, choices.size() - 1)] if not choices.is_empty() else -1
