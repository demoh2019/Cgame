extends RefCounted
## Real AI, server damage, snapshot and destructible-cover attack regression.

const Defs = preload("res://scripts/shared/defs.gd")
const Cover = preload("res://scripts/shared/infected_melee_cover.gd")
const Zombie = preload("res://scripts/shared/zombie.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const GameServer = preload("res://scripts/server/game_server.gd")
const CoverTest = preload("res://tests/test_ranged_cover.gd")


class MockWorld:
	extends RefCounted
	var blockers: Array = []

	func blockers_near(_x: float, _z: float, _radius: float) -> Array:
		return blockers

	func height_at(_x: float, _z: float) -> float:
		return WorldGen.HUB_HEIGHT


func _actors(pos: Vector3) -> Dictionary:
	return {42: {"position": pos, "alive": true, "safe": false, "noise": 0.0}}


func _at(world, site: Vector2) -> Vector3:
	return Vector3(site.x, world.height_at(site.x, site.y), site.y)


func run(t) -> void:
	t.current = "melee line of fire uses solid world geometry, not player input"
	var world := MockWorld.new()
	var origin := Vector3(0.0, WorldGen.HUB_HEIGHT, 0.0)
	var victim := Vector3(1.5, WorldGen.HUB_HEIGHT, 0.0)
	t.check(Cover.clear_attack(world, origin, victim), "unobstructed claw path permits melee")
	world.blockers = [{"x": 0.75, "z": 0.0, "radius": 0.2, "blocks": true}]
	t.check(not Cover.clear_attack(world, origin, victim),
		"thin solid wall blocks melee in range")
	t.check(Cover.clear_attack(world, origin, victim, true),
		"raid boss keeps its established special melee rules")
	t.check(not Cover.clear_attack(null, origin, victim),
		"missing world cannot authorize an attack")
	t.check(not Cover.clear_attack(world, Vector3.INF, victim, true),
		"raid boss bypass never accepts invalid attacker positions")
	t.check(not Cover.clear_attack(world, origin, Vector3(NAN, 0.0, 0.0)),
		"nonfinite victim positions cannot be hit")
	world.blockers = [{"x": 0.75, "z": 0.0, "radius": 0.2, "blocks": false}]
	t.check(Cover.clear_attack(world, origin, victim),
		"nonblocking decoration cannot protect against claws")
	world.blockers = [{"x": 0.75, "z": 2.0, "radius": 0.2, "blocks": true}]
	t.check(Cover.clear_attack(world, origin, victim),
		"off-axis obstacles do not shield melee")

	t.current = "alerted walker chips at cover instead of dealing phantom damage"
	world.blockers = [{"x": 0.75, "z": 0.0, "radius": 0.2, "blocks": true}]
	var rng := RandomNumberGenerator.new()
	rng.seed = 409
	var zombie := Zombie.new(901, "walker", origin)
	t.check(zombie.receive_pack_alert(42, _actors(victim)),
		"real pack warning can reach an enemy behind nearby cover")
	var old_cooldown: float = zombie.attack_timer
	var result: Dictionary = zombie.think(world, _actors(victim), 0.05, rng)
	t.check(result.is_empty(), "blocked melee never emits a damage hit")
	t.check(zombie.melee_blocked, "brain remembers an obstructed attempted attack")
	t.eq(zombie.state, Zombie.State.CHASE, "blocked melee retains pursuit state")
	t.near(zombie.attack_timer, old_cooldown, 0.001,
		"failed claw does not consume the attack cooldown")
	for frame in 6:
		t.check(zombie.think(world, _actors(victim), 0.05, rng).is_empty(),
			"subsequent blocked ticks cannot inflict wounds")
	t.check(zombie.stuck_time >= 0.12,
		"blocked hunter builds ordinary obstacle-bashing contact")
	t.check(zombie.position.x < 0.15,
		"short approach is allowed but real collision prevents wall tunnelling")
	world.blockers.clear()
	result = zombie.think(world, _actors(victim), 0.05, rng)
	t.eq(int(result.get("hit", -1)), 42, "clearing cover immediately restores a real strike")
	t.check(not zombie.melee_blocked, "cover warning clears as soon as the path opens")
	t.check(zombie.attack_timer > 0.0, "real hit starts the normal cooldown")
	t.check(zombie.think(world, _actors(victim), 0.05, rng).is_empty(),
		"normal cooldown still prevents duplicate attacks")
	zombie.take_damage(999.0)
	t.check(not zombie.melee_blocked, "dead infected loses blocked state")
	t.check(zombie.think(world, _actors(victim), 0.05, rng).is_empty(),
		"dead infected cannot strike regardless of cover")

	t.current = "brutes, runners, elites and spitter close claws honor cover"
	for enemy_type in ["walker", "runner", "brute", "spitter"]:
		world.blockers = [{"x": 0.75, "z": 0.0, "radius": 0.2, "blocks": true}]
		var enemy := Zombie.new(910 + int(Defs.ZOMBIES[enemy_type]["xp"]), enemy_type, origin)
		t.check(enemy.receive_pack_alert(42, _actors(victim)),
			"each infected species can receive a genuine alert")
		var observed: Dictionary = enemy.think(world, _actors(victim), 0.05, rng)
		t.check(observed.is_empty(), "no species claws through a solid barrier")
		t.check(enemy.melee_blocked, "all species expose blocked contact")
	enemy_type_test_elite(t, world, rng, origin, victim)

	t.current = "authoritative game server and nearby client snapshot"
	var live_world := WorldGen.new(713)
	var lane: Vector2 = CoverTest.new()._open_lane(live_world)
	t.check(lane.is_finite(), "find real unblocked dangerous-zone combat lane")
	if not lane.is_finite():
		return
	var sim := GameServer.new(live_world, 713)
	var survivor = sim.add_player(42, "Wall Defender")
	survivor.position = _at(live_world, lane + Vector2(1.5, 0.0))
	var attacker := Zombie.new(sim.new_id(), "walker", _at(live_world, lane))
	sim.zombies[attacker.id] = attacker
	t.check(attacker.receive_pack_alert(42, _actors(survivor.position)),
		"server zombie is genuinely alerted to a live survivor")
	var blocker_id := 986123
	live_world.add_dynamic_blocker(blocker_id, lane.x + 0.75, lane.y, 0.2)
	var health_before: float = survivor.survival.health
	sim._tick_zombies(0.05)
	t.near(survivor.survival.health, health_before, 0.001,
		"authoritative server refuses claw damage across real dynamic cover")
	t.near(survivor.survival.infection, 0.0, 0.001,
		"blocked strike cannot sneak an infection through the wall")
	t.near(survivor.survival.bleeding, 0.0, 0.001,
		"blocked strike cannot create a bleeding injury")
	t.check(attacker.melee_blocked, "server brain marks blocked contact")
	var snap: Array = sim.snapshot_for(survivor.id)["zombies"]
	t.eq(snap.size(), 1, "blocked infected remains visible to nearby player")
	t.eq(bool(snap[0].get("melee_blocked", false)), true,
		"client receives bounded obstruction cue instead of a hidden target ID")
	t.check(not snap[0].has("target_id") and not snap[0].has("threat"),
		"network state never exposes private PvE hate tables")
	live_world.remove_dynamic_blocker(blocker_id)
	sim._tick_zombies(0.05)
	t.check(survivor.survival.health < health_before,
		"real server melee damage works after barricade is destroyed")
	snap = sim.snapshot_for(survivor.id)["zombies"]
	t.eq(bool(snap[0].get("melee_blocked", true)), false,
		"network obstruction indicator clears after successful contact")


func enemy_type_test_elite(t, world, rng, origin: Vector3, victim: Vector3) -> void:
	var elite := Zombie.new(999, "runner", origin)
	elite.become_elite()
	t.check(elite.receive_pack_alert(42, _actors(victim)), "elite preserves pack aggro")
	t.check(elite.think(world, _actors(victim), 0.05, rng).is_empty(),
		"elite infected also cannot reach through solid walls")
	t.check(elite.melee_blocked, "elite has a blocked status for visual feedback")
	var boss := Zombie.new(1000, "brute", origin)
	boss.raid_boss = true
	t.check(boss.receive_pack_alert(42, _actors(victim)), "raid boss receives combat target")
	t.eq(int(boss.think(world, _actors(victim), 0.05, rng).get("hit", -1)), 42,
		"raid boss special encounter claws keep original cover behavior")
