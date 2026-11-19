extends RefCounted
## One server-owned group boss in dangerous zones. Not a second zombie AI:
## uses the existing Zombie brain, threat table and combat/loot paths.
## No RPC can ask for a spawn, a slam, a prize or a cooldown reset.

const Movement = preload("res://scripts/shared/movement.gd")
const Defs = preload("res://scripts/shared/defs.gd")

const MIN_ZONE := 2
const MIN_PARTICIPANTS := 2
const MAX_INFECTED := 90
const START_DELAY := 90.0
const COOLDOWN := 600.0
const MAX_ENCOUNTER_SECONDS := 240.0
const RALLY_RANGE := 20.0
const SPAWN_RADII := [22.0, 26.0, 30.0]
const SPAWN_ANGLES := 12
const MIN_SPAWN_TO_PLAYER := 12.0
const MIN_SPAWN_TO_LEADER := 18.0
const MAX_SPAWN_TO_LEADER := 32.0
const BOSS_HEALTH := 600.0
const BOSS_DAMAGE := 30.0
const BOSS_MASTERY_XP := 80
const SLAM_RADIUS := 5.0
const SLAM_DAMAGE := 34.0
const SLAM_WARNING := 2.0
const SLAM_COOLDOWN := 14.0
# Phase two at 35% HP, following classic party PvE boss encounter design.
const ENRAGE_HEALTH_FRACTION := 0.35
const ENRAGE_MELEE_MULTIPLIER := 1.35
const ENRAGE_SLAM_DAMAGE := 44.0
const ENRAGE_SLAM_COOLDOWN := 8.0


static func eligible_leader(world, players: Dictionary, parties) -> int:
	var group_ids: Array = parties.groups.keys()
	group_ids.sort()
	for group_id in group_ids:
		var group: Dictionary = parties.groups[group_id]
		var leader_id: int = int(group["leader"])
		var leader = players.get(leader_id)
		if leader == null or not leader.survival.alive or not leader.position.is_finite():
			continue
		var zone: int = world.zone_at(leader.position.x, leader.position.z)
		if zone < MIN_ZONE or world.is_safe(leader.position.x, leader.position.z):
			continue
		var count := 0
		var center := Vector2(leader.position.x, leader.position.z)
		for id in group["members"]:
			var member = players.get(id)
			if member == null or not member.survival.alive or not member.position.is_finite():
				continue
			var at := Vector2(member.position.x, member.position.z)
			if world.zone_at(at.x, at.y) == zone and not world.is_safe(at.x, at.y) \
					and center.distance_to(at) <= RALLY_RANGE:
				count += 1
		if count >= MIN_PARTICIPANTS:
			return leader_id
	return -1


## A deterministic bounded search instead of spawning enemies in players,
## walls, water, safe hubs, or across a risk-zone boundary.
static func spawn_site(world, players: Dictionary, leader: Vector3, offset: int = 0) -> Vector2:
	if not leader.is_finite():
		return Vector2.INF
	var origin := Vector2(leader.x, leader.z)
	var zone: int = world.zone_at(origin.x, origin.y)
	if zone < MIN_ZONE:
		return Vector2.INF
	for radius in SPAWN_RADII:
		for index in SPAWN_ANGLES:
			var angle := TAU * float((index + offset) % SPAWN_ANGLES) / float(SPAWN_ANGLES)
			var at: Vector2 = origin + Vector2.from_angle(angle) * radius
			if at.distance_to(origin) < MIN_SPAWN_TO_LEADER \
					or at.distance_to(origin) > MAX_SPAWN_TO_LEADER:
				continue
			if world.zone_at(at.x, at.y) != zone or world.is_safe(at.x, at.y) \
					or world.is_water(at.x, at.y) or not Movement._is_free(world, at):
				continue
			var crowded := false
			for member in players.values():
				if not member.survival.alive:
					continue
				if at.distance_to(Vector2(member.position.x, member.position.z)) < MIN_SPAWN_TO_PLAYER:
					crowded = true
					break
			if not crowded:
				return at
	return Vector2.INF


static func empower(boss) -> void:
	boss.data = boss.data.duplicate(true)
	boss.data["health"] = BOSS_HEALTH
	boss.data["damage"] = BOSS_DAMAGE
	boss.data["xp"] = BOSS_MASTERY_XP
	boss.data["notice"] = 30.0
	boss.data["lose"] = 48.0
	boss.health = BOSS_HEALTH
	boss.raid_boss = true


## Only an alive, server-owned raid boss may enter phase two.
## Its own stats dictionary is cloned, so unrelated brutes stay unchanged.
static func try_enrage(boss) -> bool:
	if not boss.raid_boss or boss.raid_enraged or not boss.is_alive():
		return false
	if not is_finite(boss.health) or boss.health > BOSS_HEALTH * ENRAGE_HEALTH_FRACTION:
		return false
	boss.data = boss.data.duplicate(true)
	boss.data["damage"] = BOSS_DAMAGE * ENRAGE_MELEE_MULTIPLIER
	boss.raid_enraged = true
	return true


static func slam_cooldown(boss) -> float:
	return ENRAGE_SLAM_COOLDOWN if boss.raid_enraged else SLAM_COOLDOWN


static func slam_damage(boss) -> float:
	return ENRAGE_SLAM_DAMAGE if boss.raid_enraged else SLAM_DAMAGE


static func treasure(zone: int) -> Dictionary:
	if zone < MIN_ZONE or zone > 3:
		return {}
	var tier: int = zone + 1
	return {
		"infected_core": 1 + tier,
		"silver": 25 * tier,
		"bar_%d" % tier: 2,
		"bandage": 2,
	}


static func in_slam(center: Vector2, victim: Vector3) -> bool:
	if not center.is_finite() or not victim.is_finite():
		return false
	var point := Vector2(victim.x, victim.z)
	return center.distance_squared_to(point) <= SLAM_RADIUS * SLAM_RADIUS
