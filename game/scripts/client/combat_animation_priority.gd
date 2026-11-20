extends RefCounted
## Simulation-LOD-style visual priority. Authoritative combat never slows down;
## only the rate at which distant crowd skeletons are posed is adjusted.
## The native controller has a hard per-frame budget, and stock Godot uses
## the existing CharacterModel tier-1 full-rate (no costly foot IK) fallback.

const SLOTS := [0, 1, 4, 8]
const ZOMBIE_CHASE := 2
const ZOMBIE_ATTACK := 3


static func slots(quality: int) -> int:
	return SLOTS[clampi(quality, 0, SLOTS.size() - 1)]


static func wants_priority(kind: String, entity: Dictionary) -> bool:
	if kind != "zombie":
		return false
	# Boss telegraphs must never be visibly frame-skipped while on screen.
	if bool(entity.get("raid_boss", false)) or bool(entity.get("raid_enraged", false)):
		return true
	var state: int = int(entity.get("state", 0))
	# Every on-screen attack tell competes for the SAME bounded native
	# priority pool: a nearby runner's bite is more urgent than an older,
	# farther elite's idle pose. The engine chooses nearest visible actors.
	if state == ZOMBIE_ATTACK:
		return true
	if state == ZOMBIE_CHASE and bool(entity.get("elite", false)):
		return true
	# A brief stagger is a gameplay-critical hit reaction.
	return float(entity.get("stagger_seconds", 0.0)) > 0.0
