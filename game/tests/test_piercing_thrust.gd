extends RefCounted
## Server-side multi-hit line piercing without changing other weapon skills.

const Defs = preload("res://scripts/shared/defs.gd")
const Combat = preload("res://scripts/shared/combat.gd")
const GameServer = preload("res://scripts/server/game_server.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const Zombie = preload("res://scripts/shared/zombie.gd")


func _point(world, x: float, z: float) -> Vector3:
	return Vector3(x, world.height_at(x, z), z)


func run(t) -> void:
	t.current = "pierce targets and other weapon safeguards"
	t.eq(int(Combat.active_skill("spear_1").get("pierce_targets", 0)), 3, "spear pierces three")
	t.eq(int(Combat.active_skill("club_1").get("pierce_targets", 1)), 1, "club unchanged")
	t.eq(int(Combat.active_skill("pistol").get("pierce_targets", 1)), 1, "pistol unchanged")
	var world := WorldGen.new(613)
	var server := GameServer.new(world, 74)
	var player = server.add_player(904, "Polearm")
	player.inventory.add("spear_1", 1)
	t.check(player.inventory.equip("spear_1"), "must own equipped spear")
	player.position = _point(world, 200.0, 200.0)
	var targets: Array = []
	for dist in [2.0, 3.0, 3.8, 4.3]:
		var x: float = 200.0 + dist
		var mob := Zombie.new(server.new_id(), "brute", _point(world, x, 200.0))
		server.zombies[mob.id] = mob
		targets.append(mob)
	var off_line := Zombie.new(server.new_id(), "brute", _point(world, 202.0, 202.0))
	server.zombies[off_line.id] = off_line
	var behind := Zombie.new(server.new_id(), "brute", _point(world, 199.0, 200.0))
	server.zombies[behind.id] = behind
	t.eq(server.cmd_skill(904, 0.0, 0.0).get("reason", ""), "no_direction", "aim validated")
	t.near(player.combat_energy, 100.0, 0.001, "invalid aim free")
	var result: Dictionary = server.cmd_skill(904, 1.0, 0.0)
	t.check(result.get("ok", false), "legitimate attack accepted")
	t.eq(int(result.get("hits", 0)), 3, "exactly three forward targets hit")
	var hp: float = float(Defs.ZOMBIES["brute"]["health"])
	for i in 3:
		t.near(targets[i].health, hp - Combat.weapon_damage("spear_1") * 1.45,
			0.001, "target receives exactly one hit")
	t.near(targets[3].health, hp, 0.001, "fourth target untouched")
	t.near(off_line.health, hp, 0.001, "side target untouched")
	t.near(behind.health, hp, 0.001, "rear target untouched")
	t.near(player.combat_energy, 75.0, 0.001, "25 energy charged once")
	t.near(player.skill_timer, 5.5, 0.001, "existing cooldown retained")
	t.eq(server.cmd_skill(904, 1.0, 0.0).get("reason", ""), "cooldown", "cannot spam")

	t.current = "piercing cannot bypass protected settlement"
	server.zombies.clear()
	player.attack_timer = 0.0
	player.skill_timer = 0.0
	player.combat_energy = 100.0
	var opponent = server.add_player(905, "Opponent")
	player.position = _point(world, 8.0, 0.0)
	opponent.position = _point(world, 10.0, 0.0)
	var safe: Dictionary = server.cmd_skill(904, 1.0, 0.0)
	t.check(safe.get("ok", false) and not safe.get("hit", true), "safe hub blocks PvP")
	t.near(opponent.survival.health, Defs.MAX_HEALTH, 0.001, "safe player unharmed")
	player.attack_timer = 0.0
	player.skill_timer = 0.0
	player.combat_energy = 100.0
	player.position = _point(world, 700.0, 0.0)
	opponent.position = _point(world, 702.0, 0.0)
	t.check(server.cmd_skill(904, 1.0, 0.0).get("hit", false), "red zone hit permitted")
	t.check(opponent.survival.health < Defs.MAX_HEALTH, "server applies PvP damage")
