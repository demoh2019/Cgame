extends RefCounted
## Nonlethal consent-only sparring. Never trust client-side duel permissions.
const RaidLoot = preload("res://scripts/shared/raid_loot.gd")

const INVITE_SECONDS := 20.0
const INVITE_COOLDOWN := 8.0
const MATCH_SECONDS := 120.0
const MAX_INVITE_DISTANCE := 8.0
const MAX_SEPARATION := 25.0


static func invitation_reason(world, first, second, now: float) -> String:
	if first == null or second == null or first == second or not is_finite(now):
		return "invalid_player"
	if first.id <= 0 or second.id <= 0 or not first.survival.alive or not second.survival.alive:
		return "dead"
	if not first.position.is_finite() or not second.position.is_finite():
		return "invalid_position"
	if world.zone_at(first.position.x, first.position.z) != 0 or \
			world.zone_at(second.position.x, second.position.z) != 0:
		return "safe_hub_only"
	if Vector2(first.position.x, first.position.z).distance_to(
			Vector2(second.position.x, second.position.z)) > MAX_INVITE_DISTANCE:
		return "too_far"
	if first.combat_tag_until > now or second.combat_tag_until > now:
		return "in_combat"
	if RaidLoot.token(first) == RaidLoot.token(second):
		return "same_account"
	return ""


static func active_for(duels: Dictionary, world, attacker, victim, now: float) -> bool:
	if attacker == null or victim == null or attacker == victim or not is_finite(now):
		return false
	var duel: Dictionary = duels.get(attacker.id, {})
	if duel.is_empty() or duels.get(victim.id, {}) != duel:
		return false
	var a: int = int(duel.get("a", -1))
	var b: int = int(duel.get("b", -1))
	if not ((attacker.id == a and victim.id == b) or (attacker.id == b and victim.id == a)):
		return false
	if now >= float(duel["until"]) or not attacker.survival.alive or not victim.survival.alive:
		return false
	if not attacker.position.is_finite() or not victim.position.is_finite():
		return false
	if world.zone_at(attacker.position.x, attacker.position.z) != 0 or \
			world.zone_at(victim.position.x, victim.position.z) != 0:
		return false
	return Vector2(attacker.position.x, attacker.position.z).distance_to(
		Vector2(victim.position.x, victim.position.z)) <= MAX_SEPARATION
