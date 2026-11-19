extends RefCounted
## Paid expedition respite. Server checks live fire, combat, enemy proximity,
## inventory and the existing persistent 90-second rest cooldown.
const Defs = preload("res://scripts/shared/defs.gd")
const ZoneRisk = preload("res://scripts/shared/zone_risk.gd")
const CampRest = preload("res://scripts/shared/camp_rest.gd")

const INFECTED_RADIUS := 13.0
const HOSTILE_RADIUS := 10.0
const HEALTH := 12.0
const STAMINA := 30.0
const HUNGER := 8.0
const THIRST := 10.0


static func ration(inventory) -> String:
	for tier in range(1, Defs.MAX_TIER + 1):
		var food: String = "cooked_fish" if tier == 1 else "cooked_fish_%d" % tier
		if inventory.count(food) > 0:
			return food
	return "canned_food" if inventory.count("canned_food") > 0 else ""


static func has_supplies(inventory) -> bool:
	return inventory.count("water_bottle") > 0 and not ration(inventory).is_empty()


## Nearby zombies block all field healing. PvP opponents also block it where
## both characters are in legal full-loot combat zones. Real party members
## are not considered hostile, even while using the same field campfire.
static func danger(world, player, players: Dictionary, parties, zombies: Dictionary) -> String:
	var origin: Vector3 = player.position
	if not origin.is_finite():
		return "invalid_position"
	var here := Vector2(origin.x, origin.z)
	for enemy in zombies.values():
		if not enemy.is_alive() or not enemy.position.is_finite():
			continue
		var point := Vector2(enemy.position.x, enemy.position.z)
		if here.distance_squared_to(point) <= INFECTED_RADIUS * INFECTED_RADIUS:
			return "infected_near"
	var zone: int = world.zone_at(origin.x, origin.z)
	if not ZoneRisk.allows_pvp(zone):
		return ""
	var group_id: int = parties.group_of(player.id)
	for other in players.values():
		if other.id == player.id or not other.survival.alive or not other.position.is_finite():
			continue
		if group_id > 0 and parties.group_of(other.id) == group_id:
			continue
		if not ZoneRisk.can_pvp(zone, world.zone_at(other.position.x, other.position.z)):
			continue
		var point := Vector2(other.position.x, other.position.z)
		if here.distance_squared_to(point) <= HOSTILE_RADIUS * HOSTILE_RADIUS:
			return "enemy_player_near"
	return ""


## Atomic material debit. Hub rest remains more efficient than field rest.
static func recover(inventory, vitals) -> bool:
	if not CampRest.needs_recovery(vitals) or not has_supplies(inventory):
		return false
	var food: String = ration(inventory)
	var before: Dictionary = inventory.to_dict()
	if not inventory.remove("water_bottle", 1) or not inventory.remove(food, 1):
		inventory.load_dict(before)
		return false
	vitals.heal(HEALTH)
	vitals.stamina = minf(Defs.MAX_STAMINA, vitals.stamina + STAMINA)
	vitals.stamina_recovery_delay = 0.0
	vitals.eat(HUNGER)
	vitals.drink(THIRST)
	return true
