extends RefCounted
## Blood scent gives infected a short, bounded way to find bleeding survivors.
## Only the authoritative server supplies the actual wound severity to AI.

const Defs = preload("res://scripts/shared/defs.gd")

const MIN_BLEEDING := 12.0
const BASE_RANGE := 18.0
const RANGE_PER_BLEEDING := 0.12
const MAX_RANGE := 30.0


## Returns zero for treated, dead, protected or invalid survivors.
## The zombie brain further caps detection to the enemy's pursuit leash.
static func detection_radius(bleeding: float, alive: bool = true, safe: bool = false,
		masked: bool = false) -> float:
	if not alive or safe or masked or not is_finite(bleeding) or bleeding <= MIN_BLEEDING:
		return 0.0
	var severity: float = clampf(bleeding, 0.0, Defs.BLEEDING_MAX)
	return minf(MAX_RANGE, BASE_RANGE + severity * RANGE_PER_BLEEDING)
