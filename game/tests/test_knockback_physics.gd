extends RefCounted
## Collision-swept PvE impulse physics; no boss/PvP teleport exploit.
const Defs = preload("res://scripts/shared/defs.gd")
const Combat = preload("res://scripts/shared/combat.gd")
const Movement = preload("res://scripts/shared/movement.gd")
const Zombie = preload("res://scripts/shared/zombie.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const GameServer = preload("res://scripts/server/game_server.gd")


## Test-only fixed world for exact solid geometry and deep-water assertions.
class MockWorld:
	extends RefCounted
	var block_x: float = INF
	var water_x: float = INF

	func height_at(x: float, _z: float) -> float:
		return Defs.WATER_LEVEL - 2.0 if x >= water_x else Defs.WATER_LEVEL + 2.0

	func blockers_near(_x: float, _z: float, _radius: float) -> Array:
		if not is_finite(block_x):
			return []
		return [{"x": block_x, "z": 0.0, "radius": 0.35}]


func _at(world, x: float, z: float) -> Vector3:
	return Vector3(x, world.height_at(x, z), z)


func _open_site(world) -> Vector2:
	# Find a guaranteed two-metre obstacle-free sweep on the actual world.
	for x in range(180, 301, 6):
		for z in range(170, 291, 6):
			var target: Vector3 = _at(world, float(x) + 2.0, float(z))
			var after: Vector3 = Movement.sweep_displacement(world,
				target, Vector2(2.0, 0.0))
			if after.x - target.x > 1.5:
				return Vector2(float(x), float(z))
	return Vector2.INF


func run(t) -> void:
	t.current = "bounded shared movement sweeps prevent obstacle tunnelling"
	var synthetic := MockWorld.new()
	var start := Vector3(0.0, Defs.WATER_LEVEL + 2.0, 0.0)
	var clear: Vector3 = Movement.sweep_displacement(synthetic,
		start, Vector2(2.0, 0.0))
	t.near(clear.x, 2.0, 0.001, "unblocked impulse traverses exactly two metres")
	t.near(clear.z, 0.0, 0.001, "straight impulse does not drift")
	synthetic.block_x = 1.4
	var blocked: Vector3 = Movement.sweep_displacement(synthetic,
		start, Vector2(2.0, 0.0))
	t.check(blocked.x > 0.0 and blocked.x < 1.0,
		"solid obstacle stops swept impulse before its centre")
	t.near(blocked.z, 0.0, 0.001, "blocker cannot be bypassed sideways")
	synthetic.block_x = INF
	synthetic.water_x = 1.0
	var shore: Vector3 = Movement.sweep_displacement(synthetic,
		start, Vector2(2.0, 0.0))
	t.check(shore.x < 1.0 and shore.x > 0.0,
		"deep water prevents pushing infected into inaccessible terrain")
	synthetic.water_x = INF
	t.near(Movement.sweep_displacement(synthetic, start,
		Vector2(100.0, 0.0)).x, 3.0, 0.001,
		"untrusted oversized impulse cannot exceed engine cap")
	t.eq(Movement.sweep_displacement(synthetic, start, Vector2.INF),
		start, "nonfinite directions never teleport an enemy")
	t.eq(Movement.sweep_displacement(synthetic, start,
		Vector2(2.0, 0.0), NAN), start,
		"nonfinite maximum distance is refused")
	t.eq(Movement.sweep_displacement(synthetic, start,
		Vector2.ZERO), start, "zero impulse does not move anything")

	t.current = "enemy mass, snare, raid immunity and invalid impulse safety"
	var ordinary := Zombie.new(11, "brute",
		Vector3(1.0, Defs.WATER_LEVEL + 2.0, 0.0))
	var caster := Vector3(0.0, Defs.WATER_LEVEL + 2.0, 0.0)
	t.near(ordinary.apply_knockback(synthetic, caster, 2.0), 2.0,
		0.001, "ordinary infected absorbs full two-metre impulse")
	t.near(ordinary.position.x, 3.0, 0.001,
		"ordinary infected moves away, not toward attacker")
	var elite := Zombie.new(12, "brute",
		Vector3(1.0, Defs.WATER_LEVEL + 2.0, 0.0))
	elite.become_elite()
	t.near(elite.apply_knockback(synthetic, caster, 2.0), 1.0,
		0.001, "elite mass halves push distance")
	var rooted := Zombie.new(13, "brute",
		Vector3(1.0, Defs.WATER_LEVEL + 2.0, 0.0))
	t.check(rooted.apply_snare(2.0), "existing traps can anchor a zombie")
	t.near(rooted.apply_knockback(synthetic, caster, 2.0), 0.0, 0.001,
		"rooted infected resists forced movement")
	var boss := Zombie.new(14, "brute",
		Vector3(1.0, Defs.WATER_LEVEL + 2.0, 0.0))
	boss.raid_boss = true
	t.near(boss.apply_knockback(synthetic, caster, 2.0), 0.0,
		0.001, "raid bosses cannot be repositioned by a survivor")
	t.near(boss.position.x, 1.0, 0.001,
		"raid boss stands on its original safe position")
	t.near(ordinary.apply_knockback(synthetic, caster, INF), 0.0,
		0.001, "nonfinite knockback is rejected")
	t.near(ordinary.apply_knockback(synthetic, caster, 6.0), 0.0,
		0.001, "oversized knockback is rejected")
	t.near(ordinary.apply_knockback(synthetic, ordinary.position, 2.0),
		0.0, 0.001, "same-position attacks cannot pick a forged direction")
	ordinary.take_damage(100000.0)
	t.near(ordinary.apply_knockback(synthetic, caster, 2.0), 0.0,
		0.001, "dead infected never move from further blows")

	t.current = "real hammer ability uses hit resolution and authoritative push"
	t.near(float(Combat.active_skill("sledgehammer_1").get(
		"knockback_meters", 0.0)), 2.0, 0.001,
		"knockback magnitude is derived from carried equipment")
	t.eq(Combat.active_skill("machete_1").has("knockback_meters"), false,
		"unrelated melee skill cannot shove enemies")
	var world := WorldGen.new(2345)
	var origin: Vector2 = _open_site(world)
	t.check(origin.is_finite(), "real world has open terrain for impulse integration")
	if not origin.is_finite():
		return
	var sim := GameServer.new(world, 2345)
	var warrior = sim.add_player(771, "ImpulseWarrior")
	warrior.inventory.add("sledgehammer_1", 1)
	t.check(warrior.inventory.equip("sledgehammer_1"),
		"server requires physically owned hammer")
	warrior.position = _at(world, origin.x, origin.y)
	var brute := Zombie.new(sim.new_id(), "brute",
		_at(world, origin.x + 2.0, origin.y))
	sim.zombies[brute.id] = brute
	var previous_x: float = brute.position.x
	var strike: Dictionary = sim.cmd_skill(warrior.id, 1.0, 0.0)
	t.check(strike.get("ok", false) and strike.get("hit", false),
		"only actual server-confirmed ability hits impart impulse")
	t.eq(strike.get("hits", 0), 1, "push does not add extra damage targets")
	t.check(brute.position.x > previous_x + 1.5,
		"hit really displaces the target in the simulated world")
	t.check(brute.position.x <= previous_x + 2.01,
		"target displacement never exceeds skill cap")
	t.near(brute.stagger_seconds, 1.3, 0.001,
		"physical push preserves existing concussion stun")
	t.near(warrior.combat_energy, 65.0, 0.001,
		"push does not create a free extra ability")
	t.near(warrior.skill_timer, 9.0, 0.001,
		"existing hammer cooldown is respected")
	t.eq(sim.cmd_skill(warrior.id, 1.0, 0.0).get("reason", ""),
		"cooldown", "replayed input cannot teleport target again")
	var replicated: bool = false
	for observed in sim.snapshot_for(warrior.id)["zombies"]:
		if int(observed["id"]) == brute.id:
			replicated = true
			t.near(float(observed["x"]), brute.position.x, 0.001,
				"ordinary world snapshots replicate pushed position")
	t.check(replicated, "pushed enemy is still present in snapshots")
	var announced: bool = false
	for event in sim.drain_events():
		if event.get("type", "") == "knockback" and int(event.get("id", -1)) == brute.id:
			announced = true
			t.check(float(event.get("distance", 0.0)) <= 2.01,
				"server effect contains bounded actual displacement")
	t.check(announced, "server publishes one authentic impact movement event")

	t.current = "raid boss and phantom hammer cannot grant free force"
	sim.zombies.clear()
	var raid := Zombie.new(sim.new_id(), "brute",
		_at(world, origin.x + 2.0, origin.y))
	raid.raid_boss = true
	sim.zombies[raid.id] = raid
	warrior.skill_timer = 0.0
	warrior.attack_timer = 0.0
	var old_position: Vector3 = raid.position
	t.check(sim.cmd_skill(warrior.id, 1.0, 0.0).get("hit", false),
		"raid boss can be hit without being pushed")
	t.near(raid.position.x, old_position.x, 0.001,
		"raid boss does not budge after a hit")
	t.near(raid.position.z, old_position.z, 0.001,
		"raid boss never slides from physical crowd control")
	warrior.skill_timer = 0.0
	warrior.attack_timer = 0.0
	warrior.combat_energy = 100.0
	t.check(warrior.inventory.remove("sledgehammer_1", 1),
		"hammer can be dropped while equipped")
	t.eq(sim.cmd_skill(warrior.id, 1.0, 0.0).get("reason", ""),
		"no_skill", "phantom equipped hammer is rejected")
	t.near(warrior.combat_energy, 100.0, 0.001,
		"phantom ability cannot spend energy or push enemy")
