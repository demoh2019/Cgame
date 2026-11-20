extends RefCounted
## Paid non-full-loot return to a safe settlement. All decisions are server-side.
const ZoneRisk = preload("res://scripts/shared/zone_risk.gd")
const Movement = preload("res://scripts/shared/movement.gd")
const ITEM_ID := "return_charm"
const CHANNEL_SECONDS := 8.0
const COOLDOWN_SECONDS := 300.0
const NEAR_ENEMY := 20.0
const MAX_MOVEMENT := 0.45


static func has_enemy(position: Vector3, zombies: Dictionary) -> bool:
	if not position.is_finite():
		return true
	for z in zombies.values():
		if z.is_alive() and z.position.is_finite():
			if Vector2(position.x, position.z).distance_squared_to(
					Vector2(z.position.x, z.position.z)) <= NEAR_ENEMY * NEAR_ENEMY:
				return true
	return false


static func start_reason(world, player, zombies: Dictionary, now: float) -> String:
	if player == null or not player.survival.alive:
		return "dead"
	if not player.position.is_finite() or not is_finite(now):
		return "invalid_position"
	var point := Vector2(player.position.x, player.position.z)
	if world.is_safe(point.x, point.y) or point.length() < 65.0:
		return "already_home"
	if ZoneRisk.full_loot(world.zone_at(point.x, point.y)):
		return "full_loot_zone"
	if not player.recall.is_empty():
		return "channeling"
	if player.recall_ready_at > now:
		return "cooldown"
	if player.combat_tag_until > now or player.defense_until > now or \
			player.attack_timer > 0.0 or player.skill_timer > 0.0 or \
			player.dodge_timer > 0.0 or player.noise_timer > 0.0 or \
			not player.action.is_empty():
		return "in_combat"
	if player.inventory.count(ITEM_ID) == 0:
		return "not_carried"
	if has_enemy(player.position, zombies):
		return "infected_nearby"
	return ""


static func cancel_reason(world, player, zombies: Dictionary, now: float) -> String:
	if player == null or not player.survival.alive:
		return "dead"
	if not is_finite(now) or not player.position.is_finite():
		return "invalid_position"
	var origin: Vector3 = player.recall.get("origin", Vector3.INF)
	if not origin.is_finite() or Vector2(origin.x, origin.z).distance_to(
			Vector2(player.position.x, player.position.z)) > MAX_MOVEMENT:
		return "moved"
	if world.is_safe(player.position.x, player.position.z) or \
			ZoneRisk.full_loot(world.zone_at(player.position.x, player.position.z)):
		return "unsafe_zone"
	if player.combat_tag_until > now or player.defense_until > now or \
			player.attack_timer > 0.0 or player.skill_timer > 0.0 or \
			player.dodge_timer > 0.0 or player.noise_timer > 0.0 or \
			not player.action.is_empty():
		return "in_combat"
	if player.survival.health < float(player.recall.get("health", player.survival.health)):
		return "hurt"
	if has_enemy(player.position, zombies):
		return "infected_nearby"
	return ""


static func destination(world) -> Vector3:
	for radius in [14.0, 18.0, 22.0]:
		for angle in 24:
			var p := Vector2.from_angle(TAU * float(angle) / 24.0) * radius
			if world.is_safe(p.x, p.y) and not world.is_water(p.x, p.y) and \
					world.normal_at(p.x, p.y).y > 0.7 and Movement._is_free(world, p):
				return Vector3(p.x, world.height_at(p.x, p.y), p.y)
	return Vector3.INF
