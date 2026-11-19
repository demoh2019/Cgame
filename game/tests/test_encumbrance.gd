extends RefCounted
## Shared carry-load rules must agree across inventory, movement and server-authority.

const Defs = preload("res://scripts/shared/defs.gd")
const Inventory = preload("res://scripts/shared/inventory.gd")
const Movement = preload("res://scripts/shared/movement.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const GameServer = preload("res://scripts/server/game_server.gd")


func run(t) -> void:
	t.current = "weight definitions"
	for id in Defs.items():
		var info: Dictionary = Defs.item(id)
		t.check(info.has("weight") and float(info["weight"]) >= 0.0,
			"%s has nonnegative weight" % id)
	t.near(Defs.item_weight("stone_1"), 2.0, 0.00001, "stone has a heavy weight")
	t.near(Defs.item_weight("silver"), 0.0, 0.00001, "silver is weightless currency")
	t.eq(Defs.item_weight("unknown"), 0.0, "unknown items have zero weight")
	t.near(Defs.carry_speed_factor(0.0), 1.0, 0.00001, "empty load")
	t.near(Defs.carry_speed_factor(Defs.CARRY_COMFORT_KG), 1.0, 0.00001,
		"comfort boundary permits full-speed movement")
	t.check(Defs.carry_speed_factor(Defs.CARRY_COMFORT_KG + 1.0) < 1.0,
		"over comfort load applies a movement penalty")
	t.near(Defs.carry_speed_factor(Defs.CARRY_HEAVY_KG), 0.5, 0.00001,
		"heavy load reaches the minimum movement speed")
	t.near(Defs.carry_speed_factor(999999.0), 0.5, 0.00001,
		"extremely heavy loads cannot make speed negative")
	t.near(Defs.carry_speed_factor(INF), 0.5, 0.00001,
		"nonsensical weights do not grant full movement speed")

	t.current = "inventory stacks and equipment"
	var inv := Inventory.new()
	t.near(inv.total_weight(), 0.0, 0.00001, "empty inventory")
	inv.add("stone_1", 20)
	t.near(inv.total_weight(), 40.0, 0.00001, "20 stones weigh 40 kg")
	t.check(inv.movement_factor() < 1.0, "a heavy backpack slows movement")
	inv.add("club_1", 1)
	t.check(inv.equip("club_1"), "can equip carried club")
	t.near(inv.total_weight(), 43.0, 0.00001,
		"equipped gear is already in a backpack slot and is not counted twice")
	inv.remove("stone_1", 20)
	t.near(inv.total_weight(), 3.0, 0.00001, "removing stone restores mobility")
	t.near(inv.movement_factor(), 1.0, 0.00001, "light pack is full speed")
	var saved := inv.to_dict()
	var loaded := Inventory.new()
	loaded.load_dict(saved)
	t.near(loaded.total_weight(), inv.total_weight(), 0.00001,
		"legacy inventory saves have the same derived weight")

	t.current = "shared movement"
	var world := WorldGen.new(42)
	var start := Vector3(0.0, world.height_at(0.0, 0.0), 0.0)
	var normal := Movement.step(world, start, {"x": 1.0, "z": 0.0, "sprint": true}, 0.05)
	t.near(normal.x, Defs.SPRINT_SPEED * 0.05, 0.01, "light player sprints normally")
	var loaded_move := Movement.step(world, start,
		{"x": 1.0, "z": 0.0, "sprint": true, "cargo_factor": 0.5}, 0.05)
	t.near(loaded_move.x, Defs.WALK_SPEED * 0.5 * 0.05, 0.01,
		"heavy player cannot sprint and walks at half speed")
	var forged := Movement.step(world, start,
		{"x": 1.0, "z": 0.0, "sprint": true, "cargo_factor": 99.0}, 0.05)
	t.check(forged.x <= Defs.SPRINT_SPEED * 0.05 + 0.001,
		"input factor above one cannot exceed normal sprint speed")

	t.current = "authoritative server speed"
	var server := GameServer.new(world, 27)
	var p = server.add_player(998, "Heavy")
	p.position = start
	p.inventory.add("stone_1", 50)
	t.check(p.inventory.movement_factor() <= 0.5 + 0.0001,
		"server inventory computes its own heavy-load factor")
	p.input_budget = 0.1
	server.submit_input(998, 1, 1.0, 0.0, true, 0.0, 0.1)
	t.check(p.position.x - start.x <= Defs.WALK_SPEED * 0.5 * 0.1 + 0.01,
		"sprint command cannot bypass server load penalty")
	var snapshot: Dictionary = server.snapshot_for(998)
	t.near(float(snapshot["you"]["carry_kg"]), p.inventory.total_weight(), 0.00001,
		"server snapshot reports authoritative carried weight")
	t.near(float(snapshot["you"]["cargo_factor"]), p.inventory.movement_factor(), 0.00001,
		"server snapshot reports authoritative movement factor")
