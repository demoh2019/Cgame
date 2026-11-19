extends RefCounted

const Defs = preload("res://scripts/shared/defs.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const Zombie = preload("res://scripts/shared/zombie.gd")


func _players(position: Vector3, alive := true, safe := false, noise := 0.0) -> Dictionary:
	return {1: {"position": position, "alive": alive, "safe": safe, "noise": noise}}


func run(t) -> void:
	var world := WorldGen.new(42)
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	# A flat spot far from the hub, away from trees: use the hub itself for predictable ground.
	var ground := WorldGen.HUB_HEIGHT

	t.current = "notice and chase"
	var z := Zombie.new(1, "walker", Vector3(0, ground, 0))
	var players := _players(Vector3(10, ground, 0))
	for i in 10:
		z.think(world, players, 0.1, rng)
	t.eq(z.state, Zombie.State.CHASE, "a walker 10 m away notices the player")
	t.eq(z.target_id, 1, "it targets that player")
	var start_x := z.position.x
	for i in 20:
		z.think(world, players, 0.1, rng)
	t.check(z.position.x > start_x + 2.0, "it walks toward the player")
	t.check(z.position.x < start_x + Defs.ZOMBIES["walker"]["speed"] * 2.0 + 0.5, "at walker speed, not faster")

	t.current = "ignores the far"
	z = Zombie.new(2, "walker", Vector3(0, ground, 0))
	players = _players(Vector3(60, ground, 0))
	for i in 20:
		z.think(world, players, 0.1, rng)
	t.check(z.state != Zombie.State.CHASE, "a player 60 m away is not noticed")

	t.current = "noise attracts infected"
	z = Zombie.new(80, "walker", Vector3(0, ground, 0))
	players = _players(Vector3(20, ground, 0))
	for i in 5:
		z.think(world, players, 0.1, rng)
	t.check(z.state != Zombie.State.CHASE, "quiet survivor outside vision is ignored")
	players = _players(Vector3(20, ground, 0), true, false, Defs.SPRINT_NOISE_RADIUS)
	for i in 5:
		z.think(world, players, 0.1, rng)
	t.eq(z.state, Zombie.State.CHASE, "loud sprint makes survivor detectable")
	z = Zombie.new(81, "walker", Vector3(0, ground, 0))
	players = _players(Vector3(30, ground, 0), true, false, Defs.GUNSHOT_NOISE_RADIUS)
	for i in 5:
		z.think(world, players, 0.1, rng)
	t.eq(z.state, Zombie.State.CHASE, "gunshot attracts walker beyond sprint radius")
	z = Zombie.new(82, "walker", Vector3(0, ground, 0))
	players = _players(Vector3(30, ground, 0), true, true, Defs.GUNSHOT_NOISE_RADIUS)
	for i in 5:
		z.think(world, players, 0.1, rng)
	t.check(z.state != Zombie.State.CHASE, "safe hub prevents aggression despite gunshots")

	t.current = "runner is faster"
	var runner := Zombie.new(3, "runner", Vector3(0, ground, 0))
	var walker := Zombie.new(4, "walker", Vector3(0, ground, 0))
	players = _players(Vector3(14, ground, 0))
	for i in 20:
		runner.think(world, players, 0.1, rng)
		walker.think(world, players, 0.1, rng)
	t.check(runner.position.x > walker.position.x + 2.0, "a runner outpaces a walker")

	t.current = "attack"
	z = Zombie.new(5, "walker", Vector3(0, ground, 0))
	players = _players(Vector3(1.2, ground, 0))
	var hits := 0
	var damage := 0.0
	var first_hit_time := -1.0
	for i in 80:
		var r := z.think(world, players, 0.05, rng)
		if not r.is_empty():
			hits += 1
			damage += r["damage"]
			if first_hit_time < 0.0:
				first_hit_time = i * 0.05
	t.eq(z.state, Zombie.State.ATTACK, "it attacks when close")
	t.check(hits >= 2 and hits <= 4, "hits are paced by the cooldown (%d hits in 4 s)" % hits)
	t.near(damage / hits, float(Defs.ZOMBIES["walker"]["damage"]), 0.0001, "each hit does the zombie's damage")

	t.current = "safe zone and the dead"
	z = Zombie.new(6, "walker", Vector3(0, ground, 0))
	players = _players(Vector3(2, ground, 0), true, true)
	for i in 30:
		t.check(z.think(world, players, 0.1, rng).is_empty(), "no damage to a player in the safe zone")
	t.check(z.state != Zombie.State.CHASE and z.state != Zombie.State.ATTACK, "a safe player is ignored")
	players = _players(Vector3(2, ground, 0), false, false)
	for i in 30:
		t.check(z.think(world, players, 0.1, rng).is_empty(), "no damage to a dead player")

	t.current = "losing interest"
	z = Zombie.new(7, "walker", Vector3(0, ground, 0))
	players = _players(Vector3(10, ground, 0))
	for i in 5:
		z.think(world, players, 0.1, rng)
	t.eq(z.state, Zombie.State.CHASE, "chasing")
	players = _players(Vector3(300, ground, 0))
	for i in 20:
		z.think(world, players, 0.1, rng)
	t.check(z.state != Zombie.State.CHASE, "it gives up when the player is far away")

	t.current = "damage and death"
	z = Zombie.new(8, "walker", Vector3(0, ground, 0))
	t.check(not z.take_damage(10.0), "a small hit does not kill")
	t.eq(z.state, Zombie.State.CHASE, "a hit makes it hostile")
	t.near(z.health, 35.0, 0.0001, "health goes down")
	t.check(z.take_damage(100.0), "a big hit kills")
	t.check(not z.is_alive(), "dead")
	t.check(not z.take_damage(5.0), "the dead cannot die twice")
	t.check(z.think(world, _players(Vector3(1, ground, 0)), 0.1, rng).is_empty(), "the dead do not think")

	t.current = "types"
	for type in Defs.ZOMBIES:
		var zombie := Zombie.new(9, type, Vector3(0, ground, 0))
		t.near(zombie.health, float(Defs.ZOMBIES[type]["health"]), 0.0001, "%s health" % type)
	t.check(float(Defs.ZOMBIES["brute"]["health"]) > float(Defs.ZOMBIES["walker"]["health"]) * 3.0, "brutes are tough")
