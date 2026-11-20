extends RefCounted
## GPU geometry budgets for the world's already-batched MultiMeshes.
## GeometryInstance3D LOD bias uses imported mesh LODs where available.
## Visibility ranges cheaply cull far, non-critical decorations as a batch.
## Game objects and their collision/loot server state are never removed.

const PRESETS := [
	{"tree": 112.0, "rock": 94.0, "bush": 66.0, "prop": 72.0,
		"decor_scale": 0.55, "lod_bias": 0.70},
	{"tree": 160.0, "rock": 136.0, "bush": 104.0, "prop": 118.0,
		"decor_scale": 0.80, "lod_bias": 1.0},
	{"tree": 205.0, "rock": 184.0, "bush": 145.0, "prop": 160.0,
		"decor_scale": 1.0, "lod_bias": 1.20},
	{"tree": 260.0, "rock": 224.0, "bush": 185.0, "prop": 205.0,
		"decor_scale": 1.2, "lod_bias": 1.50},
]


static func preset(quality: int) -> Dictionary:
	return PRESETS[clampi(quality, 0, PRESETS.size() - 1)].duplicate(true)


## Dither distance, only for high-fidelity foliage; low tiers keep zero
## extra fragment work. Culling remains the existing MultiMesh end range.
static func foliage_fade_width(quality: int) -> float:
	return [0.0, 0.0, 14.0, 22.0][clampi(quality, 0, 3)]


static func category(kind: String) -> String:
	if kind.begins_with("tree:") or kind == "tree":
		return "tree"
	if kind.begins_with("rock:") or kind == "rock" or kind.begins_with("ore:") or kind == "ore":
		return "rock"
	if kind == "bush" or kind == "berry":
		return "bush"
	if kind.begins_with("prop:") or kind.begins_with("crate"):
		return "prop"
	if kind.begins_with("decor:"):
		return "decor"
	return "landmark"


static func range_for(kind: String, quality: int, base_distance: float = 0.0) -> float:
	var limits: Dictionary = preset(quality)
	if base_distance > 0.0:
		return maxf(24.0, base_distance * float(limits["decor_scale"]))
	var group: String = category(kind)
	# Settlements, defensive walls, monuments and workshops remain visible
	# for navigation no matter which user-facing graphics level is selected.
	if not limits.has(group):
		return 0.0
	return float(limits[group])


static func apply(instance: MultiMeshInstance3D, kind: String, quality: int,
		base_distance: float = 0.0) -> void:
	if instance == null:
		return
	var limits: Dictionary = preset(quality)
	instance.lod_bias = float(limits["lod_bias"])
	instance.visibility_range_end = range_for(kind, quality, base_distance)
	# Hysteresis, not alpha transparency: avoiding a translucent overlap
	# keeps fill rate low and helps reduce popping at LOD thresholds.
	instance.visibility_range_end_margin = 12.0 if instance.visibility_range_end > 0.0 else 0.0
