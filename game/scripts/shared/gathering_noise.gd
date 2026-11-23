extends RefCounted
## Noisy resource gathering: a real server-completed harvest can betray the
## survivor to infected. No client-provided noise radius or target positions.
##
## Hard work (chopping and mining) cannot be silenced by crouching; careful
## low-profile foraging trades reach for quietness.

const SOUND_SECONDS := 1.1
## Small pickups are audible at close range, but much quieter than mining.
const PEBBLE_RADIUS := 3.0
const BRANCH_RADIUS := 5.0
const TREE_RADIUS := 25.0
const ROCK_RADIUS := 24.0
const ORE_RADIUS := 28.0
const BUSH_RADIUS := 8.0
const BERRY_RADIUS := 6.0
const CROUCHED_FORAGING_FACTOR := 0.55


static func radius(kind: String, crouching: bool, collected: int) -> float:
	if collected <= 0:
		return 0.0
	match kind:
		"pebble":
			return PEBBLE_RADIUS * (CROUCHED_FORAGING_FACTOR if crouching else 1.0)
		"branch":
			return BRANCH_RADIUS * (CROUCHED_FORAGING_FACTOR if crouching else 1.0)
		"tree":
			return TREE_RADIUS
		"rock":
			return ROCK_RADIUS
		"ore":
			return ORE_RADIUS
		"bush":
			return BUSH_RADIUS * (CROUCHED_FORAGING_FACTOR if crouching else 1.0)
		"berry":
			return BERRY_RADIUS * (CROUCHED_FORAGING_FACTOR if crouching else 1.0)
	return 0.0
