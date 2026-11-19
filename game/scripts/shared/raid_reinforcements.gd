extends RefCounted
## Session-only reinforcements for the existing party boss, not a new boss.
## Only server-confirmed health and server-owned positions may trigger adds.
const Movement = preload("res://scripts/shared/movement.gd")

const FIRST_THRESHOLD := 0.65
const SECOND_THRESHOLD := 0.30
const MAX_PHASE := 2
const MAX_WAVE := 2
const MIN_PLAYER_DISTANCE := 7.0
const MIN_INFECTED_DISTANCE := 3.5
const MIN_BETWEEN_ADDS := 5.0
const RADII := [9.0, 12.0, 15.0]
const ANGLES := 16


static func next_phase(hp: float, max_hp: float, completed: int) -> int:
	if not is_finite(hp) or not is_finite(max_hp) or hp <= 0.0 or max_hp <= 0.0:
		return 0
	if completed == 0 and hp / max_hp <= FIRST_THRESHOLD:
		return 1
	if completed == 1 and hp / max_hp <= SECOND_THRESHOLD:
		return 2
	return 0


static func kinds(phase: int) -> Array[String]:
	if phase == 1:
		return ["runner", "runner"]
	if phase == 2:
		return ["brute", "runner"]
	return []


## Bounded deterministic search on walkable terrain, same PvP risk zone.
static func sites(world, players: Dictionary, zombies: Dictionary,
		center: Vector3, phase: int, count: int) -> Array[Vector2]:
	var found: Array[Vector2] = []
	if not center.is_finite() or phase < 1 or phase > MAX_PHASE or count <= 0:
		return found
	var origin := Vector2(center.x, center.z)
	var zone: int = world.zone_at(origin.x, origin.y)
	if zone < 2 or world.is_safe(origin.x, origin.y):
		return found
	for radius in RADII:
		for index in ANGLES:
			var angle: float = float((index + phase * 5) % ANGLES) * TAU / ANGLES
			var point := origin + Vector2.from_angle(angle) * radius
			if world.zone_at(point.x, point.y) != zone or world.is_safe(point.x, point.y) 					or world.is_water(point.x, point.y) or not Movement._is_free(world, point):
				continue
			var clear := true
			for player in players.values():
				if player.survival.alive and player.position.is_finite() 						and point.distance_to(Vector2(player.position.x, player.position.z)) < MIN_PLAYER_DISTANCE:
					clear = false
					break
			if not clear:
				continue
			for enemy in zombies.values():
				if enemy.is_alive() and point.distance_to(Vector2(enemy.position.x, enemy.position.z)) < MIN_INFECTED_DISTANCE:
					clear = false
					break
			if not clear:
				continue
			for other in found:
				if point.distance_to(other) < MIN_BETWEEN_ADDS:
					clear = false
					break
			if clear:
				found.append(point)
				if found.size() >= mini(count, MAX_WAVE):
					return found
	return found
