extends RefCounted
## Boiled shoreline water uses a real burning campfire and a paid, atomic
## backpack debit. The command shares the persisted lake-water cooldown.
const Inventory = preload("res://scripts/shared/inventory.gd")
const FieldCanteen = preload("res://scripts/shared/field_canteen.gd")
const FieldWater = preload("res://scripts/shared/field_water.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const GameServer = preload("res://scripts/server/game_server.gd")
const CanteenTest = preload("res://tests/test_field_canteen.gd")
const Net = preload("res://scripts/shared/net.gd")


func run(t) -> void:
	t.current = "only nearby unexpired server-owned fires allow boiling"
	var position := Vector3(10.0, 5.0, 10.0)
	var fire := {"id": 77, "x": 12.0, "y": 5.0, "z": 10.0, "expires": 80.0}
	t.check(not FieldCanteen.can_boil({}, position, 0.0),
		"no fire must not authorize a water conversion")
	t.check(FieldCanteen.can_boil({77: fire}, position, 10.0),
		"nearby active campfire authorizes boiling")
	t.check(not FieldCanteen.can_boil({77: fire}, position, 80.0),
		"expired campfire cannot boil water")
	t.check(not FieldCanteen.can_boil({77: fire}, Vector3(50, 5, 10), 10.0),
		"another player's distant campfire is not portable heat")
	t.check(not FieldCanteen.can_boil({77: fire}, Vector3(10, 15, 10), 10.0),
		"large floor-height separation cannot reach the flame")
	t.check(not FieldCanteen.can_boil({77: fire}, Vector3.INF, 10.0),
		"nonfinite player positions are rejected")
	t.check(not FieldCanteen.can_boil({77: fire}, position, NAN),
		"nonfinite server time cannot authorize a boil")
	var broken := fire.duplicate()
	broken["x"] = NAN
	t.check(not FieldCanteen.can_boil({77: broken}, position, 10.0),
		"corrupt camp coordinates fail closed")

	t.current = "paid atomic conversion, including full backpacks"
	var pack := Inventory.new()
	t.eq(FieldCanteen.boil(pack), "need_canteen",
		"water cannot materialize without a crafted canteen")
	pack.add(FieldCanteen.CANTEEN_ITEM, 1)
	t.eq(FieldCanteen.boil(pack), "need_wood", "fire needs its own real fuel")
	pack.add("wood_1", 1)
	var before: Dictionary = pack.to_dict()
	t.eq(FieldCanteen.boil(pack), "need_wood",
		"one unit of wood cannot be replayed as two")
	t.eq(pack.to_dict(), before, "failed boil leaves inventory untouched")
	pack.add("wood_1", 3)
	t.eq(FieldCanteen.boil(pack), "", "two wood units produce one clean bottle")
	t.eq(pack.count("wood_1"), 2, "successful boil debits exactly two wood")
	t.eq(pack.count("charcoal_filter"), 0, "boiling never requires or mints a filter")
	t.eq(pack.count("water_bottle"), 1, "only one bottled water credited")
	t.eq(pack.count(FieldCanteen.CANTEEN_ITEM), 1, "canteen remains reusable")
	var full := Inventory.new(3)
	full.add(FieldCanteen.CANTEEN_ITEM, 1)
	full.add("wood_1", 4)
	full.add("water_bottle", 10)
	before = full.to_dict()
	t.eq(FieldCanteen.boil(full), "no_space", "full bag cannot waste wood")
	t.eq(full.to_dict(), before, "refused boil is entirely atomic")
	var freed := Inventory.new(2)
	freed.add(FieldCanteen.CANTEEN_ITEM, 1)
	freed.add("wood_1", 2)
	t.eq(FieldCanteen.boil(freed), "",
		"spending the last wood stack frees a slot for clean water")
	t.eq(freed.count("water_bottle"), 1, "freed slot receives the bottle")

	t.current = "server lake, fire, cooldown and character persistence"
	var world := WorldGen.new(42)
	var sim := GameServer.new(world, 42)
	var player = sim.add_player(923, "Field Boiler")
	t.eq(sim.cmd_refill_canteen(999, true).get("reason", ""), "dead",
		"anonymous peer cannot request boiling")
	t.eq(sim.cmd_refill_canteen(923, true).get("reason", ""), "no_water",
		"fire or paid inventory cannot create water at the safe hub")
	var shore: Vector3 = CanteenTest.new()._shore(world)
	t.check(shore.is_finite(), "seeded world has an accessible shoreline")
	if not shore.is_finite():
		return
	player.position = shore
	player.inventory.add(FieldCanteen.CANTEEN_ITEM, 1)
	player.inventory.add("wood_1", 4)
	before = player.inventory.to_dict()
	t.eq(sim.cmd_refill_canteen(923, true).get("reason", ""), "no_fire",
		"lake alone is not enough for boiling without a real campfire")
	t.eq(player.inventory.to_dict(), before, "missing fire costs no resources")
	sim.campfires[77] = {"id": 77, "x": shore.x + 1.0, "y": shore.y,
		"z": shore.z, "expires": sim.time + 40.0, "owner": 923}
	var before_wood: int = player.inventory.count("wood_1")
	var before_water: int = player.inventory.count("water_bottle")
	var boiled: Dictionary = sim.cmd_refill_canteen(923, true)
	t.check(boiled.get("ok", false), "lakeside burning campfire produces clean water")
	t.check(boiled.get("boiled", false), "success identifies boiled preparation")
	t.eq(player.inventory.count("wood_1"), before_wood - 2,
		"server debits two real wood, not an untrusted client amount")
	t.eq(player.inventory.count("water_bottle"), before_water + 1,
		"server credits one water bottle")
	t.eq(player.inventory.count("charcoal_filter"), 0,
		"boil mode does not consume filters")
	t.eq(sim.cmd_refill_canteen(923, true).get("reason", ""), "cooldown",
		"replaying same boiling request cannot mint more water")
	t.eq(sim.cmd_refill_canteen(923, false).get("reason", ""), "cooldown",
		"switching to charcoal filtration cannot bypass shared cooldown")
	t.eq(sim.cmd_drink_water(923).get("reason", ""), "cooldown",
		"drinking lake water cannot bypass the same clock")
	t.eq(sim.character_data(player)["lake_drink_cooldown"], FieldWater.COOLDOWN_SECONDS,
		"existing character save carries the anti-relogin cooldown")
	sim._tick_players(FieldWater.COOLDOWN_SECONDS)
	t.eq(player.lake_drink_cooldown, 0.0, "cooldown eventually expires")
	t.eq(sim.cmd_refill_canteen(923, true).get("reason", ""), "need_wood",
		"one remaining wood stack cannot be used without enough fuel")
	player.inventory.remove("wood_1", player.inventory.count("wood_1"))
	t.eq(sim.cmd_refill_canteen(923, true).get("reason", ""), "need_wood",
		"empty wood inventory cannot mint clean water")
	player.inventory.add("wood_1", 2)
	sim.time += 41.0
	before = player.inventory.to_dict()
	t.eq(sim.cmd_refill_canteen(923, true).get("reason", ""), "no_fire",
		"expired campfire never consumes wood")
	t.eq(player.inventory.to_dict(), before, "expired fire fails atomically")
	var net := Net.new()
	net.role = "server"
	net.sim = sim
	t.check(net.has_method("c_refill_canteen"), "authenticated multiplayer boil RPC is wired")
	net.free()
