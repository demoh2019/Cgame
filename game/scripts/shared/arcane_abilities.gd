extends RefCounted
## Classless spells every survivor can cast, independent of the equipped weapon.
## Arcane Bolt: a cheap, fast magic projectile (ranged, no ammo, costs combat energy).
## Cataclysm: the ultimate — a long-cooldown blast around the caster that hits every
## infected in range (PvE only, so it can never wipe out players in a crowd).
## The server owns every number here; clients only send an aim direction.

const BOLT_ENERGY_COST := 18.0
const BOLT_COOLDOWN := 1.1
const BOLT_ATTACK_LOCK := 0.35
const BOLT_RANGE := 24.0
const BOLT_BASE_DAMAGE := 16.0

const ULTIMATE_ENERGY_COST := 60.0
const ULTIMATE_COOLDOWN := 45.0
const ULTIMATE_ATTACK_LOCK := 1.0
const ULTIMATE_RADIUS := 7.0
const ULTIMATE_BASE_DAMAGE := 70.0
const ULTIMATE_MAX_TARGETS := 12
const ULTIMATE_STAGGER_SECONDS := 1.2


## Bolt damage grows with the survivor's ranged training, like other ranged attacks.
static func bolt_damage(ranged_bonus: float) -> float:
	return BOLT_BASE_DAMAGE * (1.0 + maxf(0.0, ranged_bonus))


## Full damage at the centre falling to half at the edge of the blast.
static func ultimate_damage(distance: float, melee_bonus: float) -> float:
	if distance < 0.0 or distance > ULTIMATE_RADIUS:
		return 0.0
	var falloff: float = lerpf(1.0, 0.5, clampf(distance / ULTIMATE_RADIUS, 0.0, 1.0))
	return ULTIMATE_BASE_DAMAGE * falloff * (1.0 + maxf(0.0, melee_bonus))


## Shared cast checks. Returns "" when the cast may start, otherwise the refusal reason.
static func refusal(alive: bool, mounted: bool, locked: bool, cooldown: float, energy: float, cost: float) -> String:
	if not alive:
		return "dead"
	if mounted:
		return "mounted"
	if locked:
		return "attack_lock"
	if cooldown > 0.0:
		return "cooldown"
	if energy < cost:
		return "no_energy"
	return ""
