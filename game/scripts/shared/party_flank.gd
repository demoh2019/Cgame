extends RefCounted
## Coordinated PvE flanking for existing party tanks + melee damage dealers.
## The infected must be fighting a DIFFERENT, close, living party member.
## No client commands, attacker-chosen targets, persistence or PvP effects.
const Defs = preload("res://scripts/shared/defs.gd")
const Zombie = preload("res://scripts/shared/zombie.gd")

const MAX_MELEE_DISTANCE := 3.2
const MAX_TANK_DISTANCE := 10.0
const MAX_HEIGHT := 3.0
const REAR_DOT := -0.55
const DAMAGE_BONUS := 0.18
const BOSS_DAMAGE_BONUS := 0.10


static func qualifies(attacker, infected, players: Dictionary, parties, world) -> bool:
	if attacker == null or infected == null or parties == null or world == null or \
			not attacker.survival.alive or not infected.is_alive() or \
			attacker.mounted or not attacker.position.is_finite() or \
			not infected.position.is_finite():
		return false
	# Stale or synthetic target IDs on idle infected do not form a fight.
	if infected.state != Zombie.State.CHASE and infected.state != Zombie.State.ATTACK:
		return false
	var weapon_id: String = attacker.inventory.weapon
	if weapon_id.is_empty() or attacker.inventory.count(weapon_id) < 1 or \
			str(Defs.item(weapon_id).get("weapon", "")) != "melee":
		return false
	var party_id: int = parties.group_of(attacker.id)
	if party_id <= 0 or infected.target_id <= 0 or infected.target_id == attacker.id or \
			party_id != parties.group_of(infected.target_id):
		return false
	var tank = players.get(infected.target_id)
	if tank == null or not tank.survival.alive or tank.mounted or \
			not tank.position.is_finite():
		return false
	if world.is_safe(attacker.position.x, attacker.position.z) or \
			world.is_safe(tank.position.x, tank.position.z) or \
			world.is_safe(infected.position.x, infected.position.z):
		return false
	var zone: int = world.zone_at(infected.position.x, infected.position.z)
	if world.zone_at(attacker.position.x, attacker.position.z) != zone or \
			world.zone_at(tank.position.x, tank.position.z) != zone:
		return false
	if absf(attacker.position.y - infected.position.y) > MAX_HEIGHT or \
			absf(tank.position.y - infected.position.y) > MAX_HEIGHT:
		return false
	var from_enemy_to_tank := Vector2(tank.position.x - infected.position.x,
		tank.position.z - infected.position.z)
	var from_enemy_to_attacker := Vector2(attacker.position.x - infected.position.x,
		attacker.position.z - infected.position.z)
	var front_length: float = from_enemy_to_tank.length_squared()
	var flank_length: float = from_enemy_to_attacker.length_squared()
	if not is_finite(front_length) or not is_finite(flank_length) or \
			front_length < 0.04 or front_length > MAX_TANK_DISTANCE * MAX_TANK_DISTANCE or \
			flank_length < 0.04 or flank_length > MAX_MELEE_DISTANCE * MAX_MELEE_DISTANCE:
		return false
	return from_enemy_to_tank.normalized().dot(
		from_enemy_to_attacker.normalized()) <= REAR_DOT


static func damage(base_damage: float, boss: bool) -> float:
	if not is_finite(base_damage) or base_damage <= 0.0:
		return 0.0
	return base_damage * (1.0 + (BOSS_DAMAGE_BONUS if boss else DAMAGE_BONUS))
