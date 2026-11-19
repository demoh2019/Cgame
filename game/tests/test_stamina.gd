extends RefCounted
## Exhaustion, food/water interactions, server authority and save compatibility.

const Defs = preload("res://scripts/shared/defs.gd")
const Survival = preload("res://scripts/shared/survival.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const GameServer = preload("res://scripts/server/game_server.gd")


func run(t) -> void:
	t.current = "sprint stamina"
	var stats := Survival.new()
	t.near(stats.stamina, 100.0, 0.001, "starts fully rested")
	t.check(stats.try_sprint(0.1), "can sprint")
	t.near(stats.stamina, 98.2, 0.001, "cost charged")
	t.check(not stats.try_sprint(0.0), "zero delta rejected")
	t.check(not stats.try_sprint(10.0), "forged long delta rejected")
	stats.tick(0.4)
	t.near(stats.stamina, 98.2, 0.001, "regen delay")
	stats.tick(0.5)
	t.check(stats.stamina > 98.2, "rest regenerates stamina after delay")
	stats.stamina = 0.0
	t.check(not stats.try_sprint(0.1), "exhaustion blocks running")
	stats.tick(5.0)
	t.check(stats.stamina > 0.0 and stats.stamina <= Defs.MAX_STAMINA, "regeneration clamped")
	stats.stamina = 100.0
	stats.thirst = 5.0
	t.check(not stats.try_sprint(0.1), "severe thirst blocks sprint")
	stats.thirst = 10.0
	stats.stamina = 10.0
	stats.stamina_recovery_delay = 0.0
	stats.tick(1.0)
	t.near(stats.stamina, 10.0 + Defs.STAMINA_REGEN_PER_SECOND * 0.5, 0.001,
		"dehydration halves recovery")
	stats.hurt(999.0)
	t.check(not stats.try_sprint(0.1), "dead cannot sprint")
	stats.reset()
	t.near(stats.stamina, Defs.MAX_STAMINA, 0.001, "respawn resets stamina")

	t.current = "server movement"
	var world := WorldGen.new(42)
	var server := GameServer.new(world, 9)
	var survivor = server.add_player(877, "Runner")
	var origin := Vector3(0, world.height_at(0.0, 0.0), 0)
	survivor.position = origin
	survivor.input_budget = 0.1
	server.submit_input(877, 1, 1.0, 0.0, true, 0.0, 0.1)
	t.check(survivor.position.x > Defs.WALK_SPEED * 0.1 + 0.001,
		"valid sprint faster than walk")
	t.near(survivor.survival.stamina, 98.2, 0.001, "only accepted time consumes energy")
	var prior: float = survivor.survival.stamina
	server.submit_input(877, 2, 1.0, 0.0, true, 0.0, 0.1)
	t.near(survivor.survival.stamina, prior, 0.001, "exhausted input budget costs nothing")
	survivor.input_budget = 0.1
	survivor.survival.stamina = 0.0
	var before: float = survivor.position.x
	server.submit_input(877, 3, 1.0, 0.0, true, 0.0, 0.1)
	t.check(survivor.position.x - before <= Defs.WALK_SPEED * 0.1 + 0.001,
		"exhausted sprint command is forced to walk")
	t.near(survivor.survival.stamina, 0.0, 0.001, "exhaustion never negative")
	survivor.input_budget = 0.1
	survivor.survival.stamina = 50.0
	before = survivor.position.x
	server.submit_input(877, 4, 0.0, 0.0, true, 0.0, 0.1)
	t.near(survivor.survival.stamina, 50.0, 0.001, "no sprint cost when stationary")
	t.near(survivor.position.x, before, 0.001, "still input doesn't move")
	survivor.input_budget = 0.1
	survivor.inventory.add("stone_1", 50)
	server.submit_input(877, 5, 1.0, 0.0, true, 0.0, 0.1)
	t.near(survivor.survival.stamina, 50.0, 0.001, "overload blocks sprint without stamina cost")

	t.current = "save and restore"
	survivor.survival.stamina = 37.0
	var saved: Dictionary = server.character_data(survivor)
	t.near(float(saved["stamina"]), 37.0, 0.001, "saved stamina")
	t.check(server.apply_character(survivor, saved), "saved character restores")
	t.near(survivor.survival.stamina, 37.0, 0.001, "stamina round trip")
	var old: Dictionary = saved.duplicate(true)
	old.erase("stamina")
	t.check(server.apply_character(survivor, old), "old v1 save is compatible")
	t.near(survivor.survival.stamina, 100.0, 0.001, "old save gets full stamina")
	var invalid: Dictionary = saved.duplicate(true)
	invalid["stamina"] = INF
	var old_health: float = survivor.survival.health
	t.check(not server.apply_character(survivor, invalid), "infinite stamina invalid")
	t.near(survivor.survival.health, old_health, 0.001, "invalid save leaves live state")
	invalid["stamina"] = -1.0
	t.check(not server.apply_character(survivor, invalid), "negative stamina invalid")
	invalid["stamina"] = 110.0
	t.check(not server.apply_character(survivor, invalid), "oversized stamina invalid")
	var snap: Dictionary = server.snapshot_for(877)
	t.near(float(snap["you"]["stamina"]), survivor.survival.stamina, 0.001,
		"snapshot sends stamina to client")
