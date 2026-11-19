extends RefCounted
## Game fishing test: headless canonical server, no network or editor scene.

const Defs = preload("res://scripts/shared/defs.gd")
const Inventory = preload("res://scripts/shared/inventory.gd")
const Fishing = preload("res://scripts/shared/fishing.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const GameServer = preload("res://scripts/server/game_server.gd")


func _shore(world) -> Vector3:
	# The generated world changes shape by seed. Search for a reachable
	# shoreline instead of relying on a hardcoded coastal coordinate.
	for angle in 72:
		var direction := Vector2.from_angle(TAU * float(angle) / 72.0)
		var distance := 100.0
		while distance < 2500.0:
			var water: Vector2 = direction * distance
			var back: Vector2 = water - direction * 4.0
			if world.height_at(water.x, water.y) < -0.3 and world.height_at(back.x, back.y) > 0.5:
				var at: Vector2 = water - direction * 2.5
				if not world.is_water(at.x, at.y):
					var candidate := Vector3(at.x, world.height_at(at.x, at.y), at.y)
					if Fishing.water_near(world, candidate) != Vector2.INF:
						return candidate
			distance += 6.0
	return Vector3.INF


func run(t) -> void:
	t.current = "fishing and food definitions"
	t.check(Defs.is_item("fishing_rod") and Defs.is_item("raw_fish")
		and Defs.is_item("cooked_fish"), "rod and caught/cooked items registered")
	t.eq(Defs.item("fishing_rod").get("tool", ""), "fishing", "rod has correct tool type")
	t.eq(Defs.recipes()["cooked_fish"]["inputs"]["raw_fish"], 1, "cooking requires caught fish")
	t.eq(Defs.item("raw_fish").get("kind", ""), "resource", "raw fish not directly edible")
	t.eq(Defs.item("cooked_fish").get("kind", ""), "food", "cooked fish restores hunger")

	t.current = "server validates cast site and gear"
	var world := WorldGen.new(42)
	var at := _shore(world)
	t.check(at != Vector3.INF, "generated world contains reachable shoreline")
	if at == Vector3.INF:
		return
	var server := GameServer.new(world, 33)
	var player = server.add_player(801, "Fisher")
	player.position = at
	t.eq(server.cmd_fish(801)["reason"], "need_rod", "unarmed survivor cannot fish")
	var hub := GameServer.WORKBENCH_POSITION
	player.position = Vector3(hub.x, world.height_at(hub.x, hub.y), hub.y)
	player.inventory.add("plank_1", 2)
	player.inventory.add("fiber_1", 3)
	t.check(server.cmd_craft(801, "fishing_rod")["ok"],
		"crafting a rod at the hub makes functional fishing gear")
	t.eq(player.inventory.count("fishing_rod"), 1, "crafted rod now carried")
	t.eq(server.cmd_fish(801)["reason"], "need_water",
		"casting from dry hub cannot create free fish")
	player.position = at
	var full := Inventory.new(1)
	full.add("fishing_rod", 1)
	t.eq(Fishing.validate_start(world, at, full)["reason"], "no_space",
		"full single-slot backpack cannot start fishing")
	t.check(not Fishing.validate_start(world, at, player.inventory).is_empty(),
		"fishing rule accepts real shoreline")

	t.current = "timed fishing and catch rewards"
	var initial_xp: int = int(player.progression.gathering_xp["fishing"])
	t.check(server.cmd_fish(801)["ok"], "server begins fishing action")
	t.eq(server.cmd_fish(801)["reason"], "busy", "repeated casts cannot overlap")
	t.eq(player.inventory.count("raw_fish"), 0, "no fish granted at cast start")
	for step in 60:
		server.time += 0.1
		server._tick_players(0.1)
	t.check(player.action.is_empty(), "cast completed after the server-owned timer")
	t.check(player.inventory.count("raw_fish") >= 1, "server actually awarded fish")
	t.check(player.progression.gathering_xp["fishing"] > initial_xp,
		"only earned fish grants profession XP")
	t.eq(server.cmd_fish(801)["reason"], "cooldown",
		"immediate recasts are blocked server-side")

	t.current = "moving interrupts fishing"
	server.time = player.fish_next_at + 0.1
	t.check(server.cmd_fish(801)["ok"], "new cast after cooldown")
	var before_count: int = player.inventory.count("raw_fish")
	player.position = Vector3(at.x + 2.0, world.height_at(at.x + 2.0, at.z), at.z)
	server._tick_players(0.1)
	t.check(player.action.is_empty(), "moving away cancels a pending catch")
	t.eq(player.inventory.count("raw_fish"), before_count,
		"interrupted cast yields neither fish nor dupes")

	t.current = "cook the catch and persist profession"
	player.position = Vector3(hub.x, world.height_at(hub.x, hub.y), hub.y)
	player.inventory.add("wood_1", 1)
	t.check(server.cmd_craft(801, "cooked_fish")["ok"],
		"fish can be cooked at a workbench with fuel")
	t.eq(player.inventory.count("cooked_fish"), 1, "cooked fish created")
	player.survival.hunger = 20.0
	t.check(server.cmd_use(801, "cooked_fish")["ok"], "cooked fish is edible")
	t.check(player.survival.hunger > 20.0, "meal restores survival hunger")
	var saved: Dictionary = server.character_data(player)
	t.check(server.valid_character_data(saved), "Nakama snapshot accepts fishing XP")
	var persisted_xp: int = int(player.progression.gathering_xp["fishing"])
	player.progression.gathering_xp["fishing"] = 0
	t.check(server.apply_character(player, saved), "new save restores fishing mastery")
	t.eq(player.progression.gathering_xp["fishing"], persisted_xp, "XP round-trips")

	t.current = "old Nakama saves and malicious XP"
	var legacy: Dictionary = saved.duplicate(true)
	legacy["progression"]["gathering"].erase("fishing")
	t.check(server.apply_character(player, legacy), "old four-skill save still loads")
	t.eq(player.progression.gathering_xp["fishing"], 0, "legacy fishing XP starts at zero")
	var forged: Dictionary = saved.duplicate(true)
	forged["progression"]["gathering"]["fishing"] = INF
	t.check(not server.apply_character(player, forged), "infinite fishing XP rejected")
	t.eq(player.progression.gathering_xp["fishing"], 0,
		"failed load does not mutate persisted profession state")
