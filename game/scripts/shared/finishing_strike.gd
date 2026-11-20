extends RefCounted
## Deterministic, equipment-only PvE finisher. The player supplies no target
## health, hit multiplier, boss status, or threshold. This helper is pure.

const THRESHOLD := 0.35
const NORMAL_MULTIPLIER := 2.0
const ELITE_MULTIPLIER := 1.5
const RAID_BOSS_MULTIPLIER := 1.2


## Called only for a real infected hit, BEFORE base damage is applied.
## Do not reward finishing dead, overhealed, or nonfinite enemies.
static func multiplier(health: float, max_health: float,
		is_elite: bool, is_raid_boss: bool) -> float:
	if not is_finite(health) or not is_finite(max_health):
		return 1.0
	if max_health <= 0.0 or health <= 0.0 or health > max_health:
		return 1.0
	if health / max_health > THRESHOLD:
		return 1.0
	if is_raid_boss:
		return RAID_BOSS_MULTIPLIER
	if is_elite:
		return ELITE_MULTIPLIER
	return NORMAL_MULTIPLIER
