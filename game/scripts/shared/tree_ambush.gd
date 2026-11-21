extends RefCounted
## Tree ambushers: some infected wait crouched up in a tree and drop onto whoever walks under,
## landing right in front of them with a hit. Damage or a close noise wakes them early.

const PERCH_HEIGHT := 3.4
const TREE_SEARCH := 10.0 # A spawn can climb a tree this close.
const TRIGGER_RANGE := 8.5 # Horizontal distance at which a percher leaps.
const LAND_HIT_RANGE := 2.0
const LAND_OFFSET := 1.1 # Lands this far in front of the target.


## Deterministic per spawn: never in the green zone, more often deeper out.
static func chance(zone: int) -> float:
	return [0.0, 0.18, 0.28, 0.32][clampi(zone, 0, 3)]


static func rolls(spawn_id: int, zone: int, world_seed: int) -> bool:
	var h: int = hash([spawn_id, world_seed, "perch"])
	return float(absi(h) % 1000) / 1000.0 < chance(zone)


## The nearest tree node of the chunk within reach of the spawn, or {}.
static func tree_near(nodes: Array, x: float, z: float) -> Dictionary:
	var best: Dictionary = {}
	var best_d := TREE_SEARCH
	for node in nodes:
		if str(node.get("kind", "")) != "tree":
			continue
		var d: float = Vector2(float(node["x"]) - x, float(node["z"]) - z).length()
		if d < best_d:
			best_d = d
			best = node
	return best


static func damage(zone: int) -> float:
	return 14.0 + 5.0 * float(clampi(zone, 0, 3))
