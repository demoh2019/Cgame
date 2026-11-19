extends RefCounted
## PvP combat-tag rules for full-loot server disconnects. Server time only;
## clients never provide tags, damage, last-hit timestamps or logout status.
const ZoneRisk = preload("res://scripts/shared/zone_risk.gd")

const TAG_SECONDS := 30.0


static func mark(player, now: float) -> void:
	if player == null or not player.survival.alive or not is_finite(now):
		return
	player.combat_tag_until = maxf(player.combat_tag_until, now + TAG_SECONDS)


static func remaining(expires: float, now: float) -> float:
	if not is_finite(expires) or not is_finite(now):
		return 0.0
	return clampf(expires - now, 0.0, TAG_SECONDS)


static func penalize_on_disconnect(player, zone: int, now: float) -> bool:
	return player != null and player.survival.alive and player.position.is_finite() \
		and ZoneRisk.full_loot(zone) and remaining(player.combat_tag_until, now) > 0.0
