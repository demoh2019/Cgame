extends RefCounted
## Stealth equipment affects only acquisition by sight, with server-owned gear checks.

const Defs = preload("res://scripts/shared/defs.gd")
const Camouflage = preload("res://scripts/shared/camouflage.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const GameServer = preload("res://scripts/server/game_server.gd")
const Zombie = preload("res://scripts/shared/zombie.gd")
const BloodScent = preload("res://scripts/shared/blood_scent.gd")


func _at(world, x: float, z: float) -> Vector3:
	return Vector3(x, world.height_at(x, z), z)


func _player_info(position: Vector3, factor: float, noise: float = 0.0,
		scent: float = 0.0) -> Dictionary:
	return {51: {"position": position, "alive": true, "safe": false, "noise": noise,
		"notice_multiplier": 1.0, "visual_signature": factor, "scent": scent}}


func run(t) -> void:
	t.current = "craftable classless ghillie clothing"
	for tier in range(2, Defs.MAX_TIER + 1):
		var id: String = "ghillie_cloak_%d" % tier
		var data: Dictionary = Defs.item(id)
		var recipe: Dictionary = Defs.recipes().get(id, {})
		t.eq(str(data.get("kind", "")), "armor", "ghillie cloak is real armor")
		t.eq(int(data.get("tier", 0)), tier, "recipe participates in tier progression")
		t.eq(str(recipe.get("station", "")), "workbench", "stealth cloak needs workbench")
		t.eq(str(recipe.get("output", "")), id, "workbench produces wearable gear")
		t.check(float(data.get("armor", 0.0)) < float(Defs.item("jacket_%d" % tier)["armor"]),
			"camouflage trades away normal protection")
	t.near(Camouflage.visual_signature("ghillie_cloak_2", true, 0.0), 0.62,
		0.001, "base cloak reduces visual signature")
	t.near(Camouflage.visual_signature("ghillie_cloak_4", true, 0.0), 0.48,
		0.001, "master cloak improves stealth")
	t.eq(Camouflage.visual_signature("ghillie_cloak_2", false, 0.0), 1.0,
		"phantom equipped gear grants no camouflage")
	t.eq(Camouflage.visual_signature("ghillie_cloak_2", true, 0.5), 1.0,
		"sprinting or gunshot noise cancels camouflage")
	t.eq(Camouflage.visual_signature("ghillie_cloak_2", true, INF), 1.0,
		"invalid noise value grants no benefit")
	t.eq(Camouflage.visual_signature("ghillie_cloak_2", true, 0.0, false), 1.0,
		"dead survivors receive no stealth")
	t.eq(Camouflage.visual_signature("jacket_3", true, 0.0), 1.0,
		"normal armor cannot grant stealth")
	t.eq(Camouflage.visual_signature("pistol", true, 0.0), 1.0,
		"a carried weapon cannot impersonate armor")

	t.current = "an idle walker sees ordinary clothing but misses distant camouflage"
	var world := WorldGen.new(442)
	var rng := RandomNumberGenerator.new()
	rng.seed = 442
	var ground: float = WorldGen.HUB_HEIGHT
	var position := Vector3(13.0, ground, 0.0)
	var hidden := Zombie.new(9101, "walker", Vector3(0.0, ground, 0.0))
	for frame in 5:
		hidden.think(world, _player_info(position, 0.62), 0.1, rng)
	t.eq(hidden.target_id, -1, "normal walker vision is shortened by cloak")
	var plain := Zombie.new(9102, "walker", Vector3(0.0, ground, 0.0))
	for frame in 5:
		plain.think(world, _player_info(position, 1.0), 0.1, rng)
	t.eq(plain.target_id, 51, "same quiet survivor without cloak is spotted")
	var loud := Zombie.new(9103, "walker", Vector3(0.0, ground, 0.0))
	for frame in 5:
		loud.think(world, _player_info(position, 0.62, Defs.SPRINT_NOISE_RADIUS), 0.1, rng)
	t.eq(loud.target_id, 51, "audible footsteps still attract an infected")
	var wounded := Zombie.new(9104, "walker", Vector3(0.0, ground, 0.0))
	for frame in 5:
		wounded.think(world, _player_info(position, 0.62, 0.0,
			BloodScent.detection_radius(65.0)), 0.1, rng)
	t.eq(wounded.target_id, 51, "blood scent still detects camouflaged survivor")

	t.current = "server validates owned armor, suppresses only sight, and snapshots status"
	var live_world := WorldGen.new(443)
	var server := GameServer.new(live_world, 443)
	var player = server.add_player(918, "Scout")
	player.position = _at(live_world, 300.0, 0.0)
	player.inventory.add("ghillie_cloak_2", 1)
	t.check(player.inventory.equip("ghillie_cloak_2"), "owned cloak is equipped")
	var walker := Zombie.new(server.new_id(), "walker", _at(live_world, 314.0, 0.0))
	server.zombies[walker.id] = walker
	server._tick_zombies(0.1)
	t.eq(walker.target_id, -1, "server stealth prevents distant visual acquisition")
	t.near(float(server.snapshot_for(918)["you"]["visual_signature"]), 0.62,
		0.001, "online HUD receives authoritative stealth effectiveness")
	player.noise_radius = Defs.SPRINT_NOISE_RADIUS
	player.noise_timer = Defs.SPRINT_NOISE_SECONDS
	# An infected reevaluates targets on a quarter-second thinking clock.
	# Trigger the next decision explicitly instead of depending on frame order.
	walker.think_timer = 0.0
	server._tick_zombies(0.1)
	t.eq(walker.target_id, 918, "real server-owned sprint noise breaks concealment")
	t.eq(server.snapshot_for(918)["you"]["visual_signature"], 1.0,
		"network HUD reports the loss of stealth when noise is active")
	player.noise_timer = 0.0
	player.inventory.remove("ghillie_cloak_2", 1)
	t.eq(server.snapshot_for(918)["you"]["visual_signature"], 1.0,
		"removing a cloak immediately revokes its effect")
	player.inventory.add("ghillie_cloak_2", 1)
	t.current = "stealth armor uses ordinary account persistence"
	var saved: Dictionary = server.character_data(player)
	t.check(server.apply_character(player, saved), "existing save accepts cloaks")
	t.eq(player.inventory.armor, "ghillie_cloak_2", "equipped cloak survives restore")
