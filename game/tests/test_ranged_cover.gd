extends RefCounted
## Ranged attacks must not pass through procedural solids or player-built barricades.
## Check the geometric helper AND real GameServer dispatch with an owned weapon.

const RangedCover = preload("res://scripts/shared/ranged_cover.gd")
const GameServer = preload("res://scripts/server/game_server.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const Zombie = preload("res://scripts/shared/zombie.gd")


class StubWorld:
	extends RefCounted
	var solids: Array = []
	func blockers_near(_x: float, _z: float, _radius: float) -> Array:
		return solids


func _open_lane(world) -> Vector2:
	# Pick an actual unobstructed segment in the red zone so procedural
	# trees/rocks do not make the simulation regression depend on a magic spot.
	for offset in 45:
		var origin := Vector2(800.0, float(offset - 22) * 19.0)
		if world.zone_at(origin.x, origin.y) != 2 or world.is_water(origin.x, origin.y) 				or world.is_water(origin.x + 18.0, origin.y):
			continue
		if RangedCover.first_blocker_distance(world, origin, Vector2.RIGHT, 27.0) == INF:
			return origin
	return Vector2.INF


func _at(world, place: Vector2) -> Vector3:
	return Vector3(place.x, world.height_at(place.x, place.y), place.y)


func run(t) -> void:
	t.current = "server ray geometry stops at first solid surface"
	var fake := StubWorld.new()
	var origin := Vector2.ZERO
	var direction := Vector2.RIGHT
	t.eq(RangedCover.first_blocker_distance(fake, origin, direction, 40.0), INF,
		"empty world leaves the shot clear")
	fake.solids = [{"x": 10.0, "z": 0.0, "radius": 2.0, "blocks": true}]
	t.near(RangedCover.first_blocker_distance(fake, origin, direction, 40.0),
		8.0, 0.001, "shot stops at circle entry, not at object center")
	t.near(RangedCover.first_blocker_distance(fake, origin, Vector2(5.0, 0.0), 40.0),
		8.0, 0.001, "nonunit direction cannot bypass geometry")
	fake.solids.append({"x": 6.0, "z": 0.0, "radius": 1.0, "blocks": true})
	t.near(RangedCover.first_blocker_distance(fake, origin, direction, 40.0),
		5.0, 0.001, "nearest obstacle wins independent of candidate order")
	fake.solids = [{"x": 10.0, "z": 3.0, "radius": 2.0, "blocks": true}]
	t.eq(RangedCover.first_blocker_distance(fake, origin, direction, 40.0),
		INF, "off-axis cover does not block bullets")
	fake.solids = [{"x": -10.0, "z": 0.0, "radius": 2.0, "blocks": true}]
	t.eq(RangedCover.first_blocker_distance(fake, origin, direction, 40.0),
		INF, "object behind shooter does not block")
	fake.solids = [{"x": 45.0, "z": 0.0, "radius": 2.0, "blocks": true}]
	t.eq(RangedCover.first_blocker_distance(fake, origin, direction, 40.0),
		INF, "object beyond weapon range does not block")
	fake.solids = [{"x": 10.0, "z": 0.0, "radius": 2.0, "blocks": false}]
	t.eq(RangedCover.first_blocker_distance(fake, origin, direction, 40.0),
		INF, "nonblocking scenery is ignored")
	fake.solids = [{"x": 10.0, "z": 0.0, "radius": NAN, "blocks": true}]
	t.eq(RangedCover.first_blocker_distance(fake, origin, direction, 40.0),
		INF, "corrupt radii cannot corrupt hit resolution")
	fake.solids = [{"x": 0.0, "z": 0.0, "radius": 1.0, "blocks": true}]
	t.near(RangedCover.first_blocker_distance(fake, origin, direction, 40.0),
		0.0, 0.001, "shot starting inside solid cover fails closed")
	t.near(RangedCover.first_blocker_distance(fake, origin, Vector2.ZERO, 40.0),
		0.0, 0.001, "zero direction cannot bypass solids")
	t.near(RangedCover.first_blocker_distance(fake, origin, direction, NAN),
		0.0, 0.001, "nonfinite range is refused")
	fake.solids = [{"x": 10.0, "z": 10.0, "radius": 2.0, "blocks": true}]
	t.near(RangedCover.first_blocker_distance(fake, origin, Vector2.ONE, 40.0),
		sqrt(200.0) - 2.0, 0.001, "diagonal shots use a genuine circular intersection")

	t.current = "real procedural world and built cover gate PvE firearm shots"
	var world := WorldGen.new(713)
	var lane := _open_lane(world)
	t.check(lane.is_finite(), "a safe open red-zone test firing lane exists")
	if not lane.is_finite():
		return
	var server := GameServer.new(world, 713)
	var shooter = server.add_player(711, "Marksman")
	shooter.position = _at(world, lane)
	shooter.inventory.add("suppressed_pistol", 1)
	shooter.inventory.add("ammo_9mm", 5)
	t.check(shooter.inventory.equip("suppressed_pistol"), "weapon is physically equipped")
	var target_place: Vector2 = lane + Vector2(16.0, 0.0)
	var infected := Zombie.new(server.new_id(), "brute", _at(world, target_place))
	server.zombies[infected.id] = infected
	var chosen: Dictionary = server._find_hit(shooter, lane, direction, 30.0, true)
	t.eq(int(chosen.get("id", -1)), infected.id,
		"live server can select a target through an open lane")
	var barrier_id := 960015
	world.add_dynamic_blocker(barrier_id, lane.x + 8.0, lane.y, 1.4)
	t.check(RangedCover.first_blocker_distance(world, lane, direction, 30.0) < 8.0,
		"a real world barricade is detected")
	t.check(server._find_hit(shooter, lane, direction, 30.0, true).is_empty(),
		"ray cannot acquire infected behind a built barricade")
	var hp_before: float = infected.health
	var fire: Dictionary = server.cmd_attack(shooter.id, 1.0, 0.0)
	t.check(bool(fire.get("ok", false)) and not bool(fire.get("hit", true)),
		"shot is valid but hits the wall rather than infected")
	t.near(infected.health, hp_before, 0.001,
		"covered infected takes no firearm damage")
	t.eq(shooter.inventory.count("ammo_9mm"), 4, "shooting a wall still costs one cartridge")
	shooter.attack_timer = 0.0
	var energy_before: float = shooter.combat_energy
	var special: Dictionary = server.cmd_skill(shooter.id, 1.0, 0.0)
	t.check(bool(special.get("ok", false)) and not bool(special.get("hit", true)),
		"charged projectile cannot pierce a wall")
	t.near(infected.health, hp_before, 0.001, "wall blocks charged damage")
	t.check(shooter.combat_energy < energy_before, "charged shot still consumes real energy")
	t.eq(shooter.inventory.count("ammo_9mm"), 3,
		"charged shot into cover consumes exactly one round")
	world.remove_dynamic_blocker(barrier_id)
	t.eq(int(server._find_hit(shooter, lane, direction, 30.0, true).get("id", -1)),
		infected.id, "destroyed barricade immediately restores line of fire")
	shooter.attack_timer = 0.0
	var clear_fire: Dictionary = server.cmd_attack(shooter.id, 1.0, 0.0)
	t.check(bool(clear_fire.get("hit", false)), "firearm hits after cover removal")
	t.check(infected.health < hp_before, "real post-removal shot damages infected")

	t.current = "PvP receives the same cover while melee stays independent"
	server.zombies.erase(infected.id)
	var defender = server.add_player(712, "Rival")
	defender.position = _at(world, target_place)
	t.eq(int(server._find_hit(shooter, lane, direction, 30.0, true).get("id", -1)),
		defender.id, "danger-zone PvP acquires enemy behind clear lane")
	world.add_dynamic_blocker(barrier_id, lane.x + 8.0, lane.y, 1.4)
	t.check(server._find_hit(shooter, lane, direction, 30.0, true).is_empty(),
		"built barricade protects enemy players as well as infected")
	shooter.inventory.add("club_1", 1)
	t.check(shooter.inventory.equip("club_1"), "switch to melee equipment")
	var near_enemy := Zombie.new(server.new_id(), "walker", _at(world, lane + Vector2(1.6, 0.0)))
	server.zombies[near_enemy.id] = near_enemy
	t.eq(int(server._find_hit(shooter, lane, direction, 2.5, false).get("id", -1)),
		near_enemy.id, "long-range cover does not suppress ordinary close melee")
	world.remove_dynamic_blocker(barrier_id)
