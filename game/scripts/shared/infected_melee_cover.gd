extends RefCounted
## Prevent an infected's ordinary melee strike from passing through solid cover.
## Reuse the same authoritative blocker geometry as first-contact sight and
## projectile collision; special raid-boss swings retain encounter semantics.

const InfectedSight = preload("res://scripts/shared/infected_sight.gd")


static func clear_attack(world, origin: Vector3, target: Vector3,
		raid_boss: bool = false) -> bool:
	if world == null or not origin.is_finite() or not target.is_finite():
		return false
	# Boss cones/slams have their own telegraphs and collision rules; do
	# not silently change an existing raid encounter's basic melee pacing.
	if raid_boss:
		return true
	return InfectedSight.clear_path(world, origin, target)
