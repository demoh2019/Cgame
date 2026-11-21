extends RefCounted
## Infected temperaments: hunters keep chasing until they lose sight of you,
## territorial guardians defend their ground and never leave it, howlers wake the pack.
## Spawns are denser and more varied, deterministically.
const Defs = preload("res://scripts/shared/defs.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const Zombie = preload("res://scripts/shared/zombie.gd")


func _players(position: Vector3) -> Dictionary:
	return {1: {"position": position, "alive": true, "safe": false, "noise": 0.0}}


func run(t) -> void:
	var world := WorldGen.new(42)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var ground := WorldGen.HUB_HEIGHT

	t.current = "every type has a temperament and looks valid"
	for type in ["stalker", "sentinel", "howler", "crawler"]:
		t.check(Defs.ZOMBIES.has(type), "%s exists" % type)
		t.check(Defs.ZOMBIE_INFECTION_PER_HIT.has(type), "%s infects" % type)
	t.eq(Zombie.new(1, "stalker", Vector3.ZERO).behavior, "hunter", "stalkers hunt")
	t.eq(Zombie.new(1, "sentinel", Vector3.ZERO).behavior, "territorial", "sentinels guard")
	t.eq(Zombie.new(1, "walker", Vector3.ZERO).behavior, "roamer", "walkers roam")
	var champion := Zombie.new(1, "walker", Vector3.ZERO)
	champion.become_elite()
	t.eq(champion.behavior, "hunter", "champions never let go")

	t.current = "territorial guardians stay on their ground"
	var guard := Zombie.new(2, "sentinel", Vector3(0, ground, 0))
	var territory: float = float(Defs.ZOMBIES["sentinel"]["territory"])
	guard.think(world, _players(Vector3(6, ground, 0)), 0.3, rng)
	t.eq(guard.state, Zombie.State.CHASE, "an intruder inside the territory is attacked")
	guard.think(world, _players(Vector3(territory + 10.0, ground, 0)), 0.3, rng)
	t.check(guard.state != Zombie.State.CHASE and guard.target_id == -1, "a survivor who leaves is not followed")
	var guard2 := Zombie.new(3, "sentinel", Vector3(0, ground, 0))
	guard2.think(world, _players(Vector3(territory + 8.0, ground, 0)), 0.3, rng)
	t.eq(guard2.target_id, -1, "survivors passing outside are ignored")
	t.check(not guard2.receive_pack_alert(1, _players(Vector3(territory + 8.0, ground, 0))), "pack alerts cannot drag a guard off its ground")

	t.current = "hunters chase far and only give up after losing sight"
	var hunter := Zombie.new(4, "stalker", Vector3(0, ground, 0))
	hunter.think(world, _players(Vector3(10, ground, 0)), 0.3, rng)
	t.eq(hunter.state, Zombie.State.CHASE, "the stalker spots you")
	var far := float(Defs.ZOMBIES["walker"]["lose"]) + 20.0
	hunter.think(world, _players(Vector3(far, ground, 0)), 0.1, rng)
	t.eq(hunter.state, Zombie.State.CHASE, "it keeps chasing beyond where a walker gives up")
	hunter.unseen_seconds = Zombie.HUNTER_MEMORY_SECONDS + 1.0
	hunter._sight_check = 10.0
	hunter.think(world, _players(Vector3(far, ground, 0)), 0.1, rng)
	t.eq(hunter.state, Zombie.State.INVESTIGATE, "out of sight long enough, it searches your last position")
	t.near(hunter.investigate_time, Zombie.HUNTER_SEARCH_SECONDS, 0.2, "and searches longer than ordinary infected")

	t.current = "howlers scream once per survivor"
	var howler := Zombie.new(5, "howler", Vector3(0, ground, 0))
	howler.think(world, _players(Vector3(5, ground, 0)), 0.3, rng)
	t.check(howler.consume_howl(), "spotting someone triggers a howl")
	t.check(not howler.consume_howl(), "the howl is consumed once")
	howler.think(world, _players(Vector3(5.5, ground, 0)), 0.3, rng)
	t.check(not howler.consume_howl(), "no repeated howl for the same survivor")

	t.current = "native howler cooldown suppresses overlapping pack alarms"
	# Real target checks still create the original one-shot howl; the native
	# ledger only rate limits a subsequent server-authorized event.
	howler._howl_pending = true
	if ClassDB.class_exists("AIActionCooldowns"):
		t.check(howler._native_howl_cooldowns != null,
			"first authoritative howl lazily creates the native event ledger")
		t.check(not howler.consume_howl(), "second target cannot spam the pack instantly")
		t.check(float(howler.get_ai_debug_snapshot().get("pack_howl_cooldown_seconds", 0.0)) > 0.0,
			"server diagnostic exposes the remaining native timer")
		howler.think(world, {}, 6.2, rng)
		howler._howl_pending = true
		t.check(howler.consume_howl(), "game simulation time unlocks the howl again")
	else:
		t.check(howler.consume_howl(), "stock Godot keeps its previous howl behavior")
		t.eq(howler.get_ai_debug_snapshot().get("pack_howl_cooldown_seconds"), 0.0,
			"stock Godot retains a safe no-op cooldown diagnostic")

	t.current = "the wilds teem with varied infected"
	var types: Dictionary = {}
	var total := 0
	for x in range(4, 16):
		for z in range(-6, 6):
			for spawn in world.chunk(Vector2i(x, z))["spawns"]:
				types[str(spawn["type"])] = true
				total += 1
	t.check(total > 300, "dense spawns across the wilds (%d)" % total)
	for type in ["walker", "crawler", "stalker", "sentinel", "howler"]:
		t.check(types.has(type), "%s appears in the world" % type)
	var ids: Dictionary = {}
	var duplicate := false
	for spawn in world.chunk(Vector2i(8, 2))["spawns"]:
		if ids.has(spawn["id"]):
			duplicate = true
		ids[spawn["id"]] = true
	t.check(not duplicate, "spawn ids stay unique within a chunk")
	t.eq(WorldGen.new(42).chunk(Vector2i(8, 2))["spawns"], world.chunk(Vector2i(8, 2))["spawns"], "spawns are deterministic")
