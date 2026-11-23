extends RefCounted
## Gameplay-sized fallen wood: authoritative, independently seeded nodes.
## The server only reads this compact manifest; the client optionally draws
## the corresponding scans. Other stones already use shared StoneResources.

const MODELS := [
	{"path": "res://assets/models/polyhaven/baked/old_log.res", "kind": "length",
		"size": 4.5, "resource": "tree", "biomes": ["forest", "swamp", "plains"],
		"radius_factor": 0.5},
	{"path": "res://assets/models/polyhaven/baked/fallen_trunk.res", "kind": "length",
		"size": 5.0, "resource": "tree", "biomes": ["forest", "swamp", "plains"],
		"radius_factor": 0.5},
	{"path": "res://assets/models/polyhaven/baked/dead_trunk.res", "kind": "length",
		"size": 4.0, "resource": "tree", "biomes": ["forest", "swamp"],
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


## A conservative circle encloses a fallen tree regardless of the axes in its
## source scan. This prevents clipping even when downloaded art differs.
static func radius(variant: int, size_scale: float) -> float:
	if variant < 0 or variant >= MODELS.size():
		return 0.0
	var entry: Dictionary = MODELS[variant]
	return float(entry["size"]) * float(entry["radius_factor"]) * size_scale
