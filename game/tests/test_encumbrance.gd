extends RefCounted

const Defs = preload("res://scripts/shared/defs.gd")
const Inventory = preload("res://scripts/shared/inventory.gd")
const Encumbrance = preload("res://scripts/shared/encumbrance.gd")
const Movement = preload("res://scripts/shared/movement.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const GameServer = preload("res://scripts/server/game_server.gd")


func run(t) -> void:
	t.current = "weight catalog"
	t.eq(Encumbrance.item_grams("silver"), 0, "silver adds no mass")
	t.eq(Encumbrance.item_grams("water_bottle"), 1000, "a bottle weighs one kilogram")
	t.eq(Encumbrance.item_grams("wood_1"), 1700, "wood has an explicit weight")
	t.eq(Encumbrance.item_grams("wood_2"), 3400, "higher-tier wood is heavier")
	t.eq(Encumbrance.item_grams("stone_1"), 2400, "stones are heavier than wood")
	t.eq(Encumbrance.item_grams("fiber_1"), 350, "fiber weighs less than ore")
	for id in Defs.items():
		t.check(Encumbrance.item_grams(id) >= 0, "valid nonnegative mass for " + id)

	t.current = "inventory load"
	var inv := Inventory.new()
	t.eq(inv.weight_grams(), 0, "empty inventory has no mass")
	inv.add("water_bottle", 2)
	inv.add("stone_1", 5)
	t.eq(inv.weight_grams(), 14000, "stacks count quantity, not slots")
	t.check(inv.can_sprint(), "14 kg allows sprint")
	t.check(inv.speed_factor() < 1.0 and inv.speed_factor() > Encumbrance.MIN_SPEED_FACTOR,
		"weight above free load slows walking")
	inv.add("stone_1", 3)
	t.eq(inv.weight_grams(), 21200, "additional material increases carried load")
	t.check(not inv.can_sprint(), "heavy inventory blocks sprint")
	var before_remove := inv.weight_grams()
	t.check(inv.remove("stone_1", 3), "remove three stones")
	t.eq(inv.weight_grams(), before_remove - 3 * 2400, "dropping weight updates movement")
	inv.add("club_1", 1)
	var before_equip := inv.weight_grams()
	t.check(inv.equip("club_1"), "weapon is equipped")
	t.eq(inv.weight_grams(), before_equip, "equipped weapon is not counted twice")
	var carry_copy := Inventory.new()
	carry_copy.load_dict(inv.to_dict())
	t.eq(carry_copy.weight_grams(), inv.weight_grams(), "load survives inventory persistence")
	inv.take_everything()
	t.eq(inv.weight_grams(), 0, "full loot death or drop clears carried load")

	t.current = "shared movement"
	var world := WorldGen.new(42)
	var start := Vector3(0.0, world.height_at(0.0, 0.0), 0.0)
	var light := start
	var medium := start
	var heavy := start
	for i in 30:
		light = Movement.step(world, light, {"x": 1.0, "z": 0.0, "sprint": true}, 1.0 / 30.0, 0)
		medium = Movement.step(world, medium, {"x": 1.0, "z": 0.0, "sprint": true}, 1.0 / 30.0, 14000)
		heavy = Movement.step(world, heavy, {"x": 1.0, "z": 0.0, "sprint": true}, 1.0 / 30.0, 50000)
	t.near(light.x, Defs.SPRINT_SPEED, 0.05, "light player sprints normally")
	t.check(medium.x < light.x and medium.x > heavy.x, "partially loaded player slows")
	t.near(heavy.x, Defs.WALK_SPEED * Encumbrance.MIN_SPEED_FACTOR, 0.05,
		"heavy sprint input becomes capped slow walking")
	t.eq(Encumbrance.speed_factor(999999), Encumbrance.MIN_SPEED_FACTOR,
		"speed factor saturates under extreme loads")
	t.eq(Encumbrance.speed_factor(-1), 1.0, "negative load gives no speed bonus")

	t.current = "server authoritative load"
	var server := GameServer.new(world, 123)
	var player = server.add_player(42, "Hauler")
	player.position = start
	player.inventory.take_everything()
	player.inventory.add("stone_1", 30) # 72 kg
	server.tick(0.2)
	var snapshot: Dictionary = server.snapshot_for(42)
	t.eq(snapshot["you"]["carry_grams"], 72000, "server reports true carried weight")
	t.eq(snapshot["you"]["can_sprint"], false, "server disallows heavy sprint")
	var initial: Vector3 = player.position
	# Client cannot claim to be weightless: submit_input receives no weight
	# argument and server recomputes mass from authoritative inventory.
	server.submit_input(42, 1, 1.0, 0.0, true, 0.0, 0.1)
	t.check(player.position.x - initial.x <= Defs.WALK_SPEED * Encumbrance.MIN_SPEED_FACTOR * 0.1 + 0.001,
		"claimed sprint cannot bypass authoritative heavy load")
	player.inventory.take_everything()
	server.tick(0.2)
	player.position = start
	server.submit_input(42, 2, 1.0, 0.0, true, 0.0, 0.1)
	t.check(player.position.x - start.x > 0.4, "unloaded player regains sprint immediately")
	var after: Dictionary = server.snapshot_for(42)
	t.eq(after["you"]["carry_grams"], 0, "server load resets after inventory drop")
	t.eq(after["you"]["can_sprint"], true, "sprint unlocks after unloading")
