extends RefCounted
## Live server-spawned raid minions grant their boss temporary resistance.
## Never accepts an RPC, persists state or changes damage against players.
const PERCENT_PER_GUARD := 12
const MAX_EFFECTIVE_GUARDS := 2


static func living_count(boss, active_boss_id: int, guard_ids: Array[int],
		zombies: Dictionary) -> int:
	if boss == null or boss.id != active_boss_id or not boss.raid_boss or not boss.is_alive():
		return 0
	var seen: Dictionary = {}
	var count: int = 0
	for enemy_id in guard_ids:
		if seen.has(enemy_id):
			continue
		seen[enemy_id] = true
		var guard = zombies.get(enemy_id)
		if guard != null and guard != boss and not guard.raid_boss and guard.is_alive():
			count += 1
	return count


static func reduction_percent(guards: int) -> int:
	return mini(maxi(guards, 0), MAX_EFFECTIVE_GUARDS) * PERCENT_PER_GUARD


static func absorb(damage: float, boss, active_boss_id: int,
		guard_ids: Array[int], zombies: Dictionary) -> float:
	if not is_finite(damage) or damage <= 0.0:
		return 0.0
	return damage * (1.0 - float(reduction_percent(
		living_count(boss, active_boss_id, guard_ids, zombies))) / 100.0)
