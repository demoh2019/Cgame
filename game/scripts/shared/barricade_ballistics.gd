extends RefCounted
## PvP siege gunfire damages only real server-created barricades.
## Existing wall tiers, HP, rebuilding and obstacle removal remain authoritative.

const Structures = preload("res://scripts/shared/structures.gd")
const ZoneRisk = preload("res://scripts/shared/zone_risk.gd")

const DAMAGE_FRACTION := 0.6
const MAX_RAW_DAMAGE := 48.0


static func can_damage(attacker, wall: Dictionary,
		attacker_zone: int, wall_zone: int) -> bool:
	if attacker == null or wall.is_empty() or not ZoneRisk.can_pvp(attacker_zone, wall_zone):
		return false
	if Structures.can_manage(wall, attacker.id, attacker.user_id):
		return false # Neither the guest owner nor the account owner can farm damage.
	var owner_guild: String = str(wall.get("owner_guild", ""))
	if owner_guild != "" and owner_guild == attacker.guild_id:
		return false # Authenticated guildmates cannot grief each other's walls.
	return true


## Convert verified equipped-weapon damage into structure damage.
## The usual tier resistance is applied separately by damage_barricade().
static func raw_damage(verified_weapon_damage: float) -> float:
	if not is_finite(verified_weapon_damage) or verified_weapon_damage <= 0.0:
		return 0.0
	return clampf(verified_weapon_damage * DAMAGE_FRACTION, 1.0, MAX_RAW_DAMAGE)
