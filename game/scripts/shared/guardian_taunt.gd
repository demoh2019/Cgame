extends RefCounted
## Classless party guardian: server-owned redirection of infected already
## pursuing allies. Client cannot choose a zombie or manipulate its hate.

const Defs = preload("res://scripts/shared/defs.gd")
const RADIUS := 12.0
const MAX_TARGETS := 3
const FOCUS_SECONDS := 3.0
const COOLDOWN := 20.0
const ENERGY_COST := 25.0


static func melee_equipped(inventory) -> bool:
	var id: String = inventory.weapon
	return id != "" and inventory.count(id) > 0 and 		str(Defs.item(id).get("weapon", "")) == "melee"


static func eligible_enemy(enemy, origin: Vector3, members: Array, world) -> bool:
	if not origin.is_finite() or not enemy.position.is_finite() or not enemy.is_alive():
		return false
	if enemy.target_id <= 0 or not members.has(enemy.target_id):
		return false
	if world.is_safe(origin.x, origin.z):
		return false
	if world.zone_at(origin.x, origin.z) != world.zone_at(enemy.position.x, enemy.position.z):
		return false
	var distance := Vector2(enemy.position.x - origin.x, enemy.position.z - origin.z).length_squared()
	return distance <= RADIUS * RADIUS and distance <= 		float(enemy.data["lose"]) * float(enemy.data["lose"])
