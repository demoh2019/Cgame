extends RefCounted
## Resources should create real, bounded infected hearing only after a
## legitimate server harvest. No client-command sound multipliers exist.

const Defs = preload("res://scripts/shared/defs.gd")
const GatheringNoise = preload("res://scripts/shared/gathering_noise.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const GameServer = preload("res://scripts/server/game_server.gd")
const Zombie = preload("res://scripts/shared/zombie.gd")


func _tree(world) -> Dictionary:
	for cx in range(3, 8):
		for cz in range(3, 8):
			var chunk: Dictionary = world.chunk(Vector2i(cx, cz))
			for node in chunk["nodes"]:
				if str(node["kind"]) == "tree" and int(node["tier"]) == 1 and (
						not world.is_safe(float(node["x"]), float(node["z"]))):
					return node
	return {}


func run(t) -> void:
	t.current = "gathering sound is bounded by work type"
	t.near(GatheringNoise.radius("pebble", false, 1),
		GatheringNoise.PEBBLE_RADIUS, 0.0001, "loose pebbles rustle only at close range")
	t.near(GatheringNoise.radius("branch", false, 1),
		GatheringNoise.BRANCH_RADIUS, 0.0001, "picking up branches makes light noise")
	t.near(GatheringNoise.radius("branch", true, 1),
		GatheringNoise.BRANCH_RADIUS * GatheringNoise.CROUCHED_FORAGING_FACTOR, 0.0001,
		"crouching makes branch pickup quieter")
	t.check(GatheringNoise.BRANCH_RADIUS < GatheringNoise.BUSH_RADIUS,
		"loose pickups are quieter than active gathering")
	t.near(GatheringNoise.radius("tree", false, 4),
		GatheringNoise.TREE_RADIUS, 0.0001, "chopping is audible")
	t.near(GatheringNoise.radius("rock", false, 4),
		GatheringNoise.ROCK_RADIUS, 0.0001, "stone breaking is audible")
	t.near(GatheringNoise.radius("ore", true, 3),
		GatheringNoise.ORE_RADIUS, 0.0001, "crouching cannot silence mining")
	t.near(GatheringNoise.radius("tree", true, 4),
		GatheringNoise.TREE_RADIUS, 0.0001, "crouching cannot silence axes")
	t.near(GatheringNoise.radius("bush", false, 3),
		GatheringNoise.BUSH_RADIUS, 0.0001, "bush harvest is relatively quiet")
	t.near(GatheringNoise.radius("bush", true, 3),
		GatheringNoise.BUSH_RADIUS * GatheringNoise.CROUCHED_FORAGING_FACTOR,
		0.0001, "crouching genuinely reduces fiber-gather noise")
	t.near(GatheringNoise.radius("berry", true, 3),
		GatheringNoise.BERRY_RADIUS * GatheringNoise.CROUCHED_FORAGING_FACTOR,
		0.0001, "crouched berry collection stays quiet")
	t.eq(GatheringNoise.radius("tree", false, 0), 0.0,
		"no inventory yield means no noise")
	t.eq(GatheringNoise.radius("tree", false, -1), 0.0,
		"malformed negative yield cannot emit a sound")
	t.eq(GatheringNoise.radius("invalid", false, 5), 0.0,
		"unknown world nodes cannot mint arbitrary sound")
	t.check(GatheringNoise.TREE_RADIUS > Defs.SPRINT_NOISE_RADIUS,
		"the resource economy has more hearing danger than ordinary sprinting")

	t.current = "completed genuine gathering attracts actual infected"
	var world := WorldGen.new(42)
	var source: Dictionary = _tree(world)
	t.check(not source.is_empty(), "an accessible tree exists in wilderness")
	if source.is_empty():
		return
	var server := GameServer.new(world, 42)
	var woodsman = server.add_player(601, "Lumberjack")
	var x: float = float(source["x"])
	var z: float = float(source["z"])
	woodsman.position = Vector3(x, world.height_at(x, z), z)
	t.eq(woodsman.noise_radius, 0.0, "idle survivor is silent")
	var action: Dictionary = server.cmd_gather(601, int(source["id"]))
	t.check(action.get("ok", false), "valid nearby tree gathering starts")
	if not action.get("ok", false):
		return
	t.eq(woodsman.noise_radius, 0.0,
		"starting or replaying a gather is not itself a sound event")
	server._finish_gather(woodsman, source)
	t.near(woodsman.noise_radius, GatheringNoise.TREE_RADIUS, 0.0001,
		"completed server gather emits its specific resource sound")
	t.near(woodsman.noise_timer, GatheringNoise.SOUND_SECONDS, 0.0001,
		"hearing risk has a bounded server-owned lifetime")
	var added: int = woodsman.inventory.count("wood_1")
	t.check(added > 0, "the gathering action actually supplies items")
	var harvesting: Dictionary = {}
	for event in server.events:
		if str(event.get("type", "")) == "gathered" and int(event.get("node", -1)) == int(source["id"]):
			harvesting = event
	t.near(float(harvesting.get("harvest_noise", 0.0)),
		GatheringNoise.TREE_RADIUS, 0.0001,
		"server event uses calculated radius not a client claim")

	# 23m exceeds even night-enhanced walker vision (16m * 1.35) but
	# remains inside its ordinary leash and this real sound's 25m radius.
	var enemy_pos := Vector3(x + 23.0,
		world.height_at(x + 23.0, z), z)
	var listener := Zombie.new(server.new_id(), "walker", enemy_pos)
	server.zombies[listener.id] = listener
	server.tick_count = 0 # prevent unrelated population management
	server._tick_zombies(0.05)
	t.eq(listener.target_id, woodsman.id,
		"actual world AI hears the lumberjack from outside sight range")
	server.zombies.clear()

	t.current = "spent nodes, expiry and quiet walking do not retrigger noise"
	server._tick_players(GatheringNoise.SOUND_SECONDS + 0.01)
	t.near(woodsman.noise_timer, 0.0, 0.0001,
		"natural server time removes gathering noise")
	t.near(woodsman.noise_radius, 0.0, 0.0001,
		"no phantom sound radius lingers after timer expiry")
	t.eq(server.cmd_gather(601, int(source["id"])).get("reason", ""),
		"depleted", "already harvested node cannot be replayed")
	t.eq(woodsman.inventory.count("wood_1"), added,
		"replayed attempts cannot create resources")
	t.eq(woodsman.noise_radius, 0.0,
		"replayed harvest cannot extend sound danger")
	var silent := Zombie.new(server.new_id(), "walker", enemy_pos)
	server.zombies[silent.id] = silent
	server._tick_zombies(0.05)
	t.eq(silent.target_id, -1,
		"quiet survivor outside normal sight is not detected after sound expiry")
