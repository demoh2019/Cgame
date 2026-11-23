extends RefCounted
## Gameplay-sized scattered rocks and fallen wood. This catalog contains only
## deterministic metadata: server builds blockers without loading art, and
## clients render the same node IDs from whichever mesh packs are installed.
## Small pebbles, flowers, branches and grass remain passable cosmetics.

const MODELS := [
	{"path": "res://assets/models/polyhaven/baked/boulder_group.res", "kind": "length",
		"size": 4.0, "resource": "rock", "biomes": ["plains", "mountain", "forest", "beach"],
		"radius_factor": 0.47},
	{"path": "res://assets/models/polyhaven/baked/rock_group.res", "kind": "length",
		"size": 2.2, "resource": "rock", "biomes": ["plains", "mountain", "forest", "beach", "swamp"],
		"radius_factor": 0.46},
	{"path": "res://assets/models/polyhaven/baked/shore_rocks.res", "kind": "length",
		"size": 3.0, "resource": "rock", "biomes": ["beach"],
		"radius_factor": 0.46},
	{"path": "res://assets/models/polyhaven/baked/old_log.res", "kind": "length",
		"size": 4.5, "resource": "tree", "biomes": ["forest", "swamp", "plains"],
		"radius_factor": 0.5},
	{"path": "res://assets/models/polyhaven/baked/fallen_trunk.res", "kind": "length",
		"size": 5.0, "resource": "tree", "biomes": ["forest", "swamp", "plains"],
		"radius_factor": 0.5},
]


static func available_variants(biome: String) -> Array[int]:
	var result: Array[int] = []
	for i in MODELS.size():
		if biome in MODELS[i]["biomes"]:
			result.append(i)
	return result


static func is_promoted_path(path: String) -> bool:
	for entry in MODELS:
		if str(entry["path"]) == path:
			return true
	return false


static func radius(variant: int, size_scale: float) -> float:
	if variant < 0 or variant >= MODELS.size():
		return 0.0
	var entry: Dictionary = MODELS[variant]
	return float(entry["size"]) * float(entry["radius_factor"]) * size_scale
