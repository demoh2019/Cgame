extends RefCounted
## Workbench consumable, real shared traction, server packets and relog security.

const Defs = preload("res://scripts/shared/defs.gd")
const BikeGrip = preload("res://scripts/shared/bike_grip.gd")
const BikeTerrain = preload("res://scripts/shared/bike_terrain.gd")
const Mounts = preload("res://scripts/shared/mounts.gd")
const Movement = preload("res://scripts/shared/movement.gd")
const Inventory = preload("res://scripts/shared/inventory.gd")
const Crafting = preload("res://scripts/shared/crafting.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const GameServer = preload("res://scripts/server/game_server.gd")


class FlatWorld:
	var biome := "plains"
	var hill := 0.0

	func height_at(x: float, _z: float) -> float:
		return 3.0 + hill * x

	func biome_at(_x: float, _z: float) -> String:
		return biome

	func blockers_near(_x: float, _z: float, _radius: float) -> Array:
		return []


func _find_rough_trail(world) -> Vector3:
	for gx in range(-15, 16):
		for gz in range(-15, 16):
			var x := float(gx) * 80.0
			var z := float(gz) * 80.0
			if world.biome_at(x, z) != "swamp" or world.is_water(x, z):
				continue
			var spot := Vector3(x, world.height_at(x, z), z)
			if world.is_safe(x, z):
				continue
			if Movement.step(world, spot, {"x": 1.0, "mounted": true}, 0.1).distance_to(spot) > 0.01:
				return spot
	return Vector3.INF


func run(t) -> void:
	t.current = "real crafted grips and explicit bike ownership"
	t.eq(Defs.item(BikeGrip.ITEM_ID).get("kind"), "tire_grips",
		"tire grips registered in inventory")
	t.eq(Defs.recipes()[BikeGrip.ITEM_ID]["station"], "workbench",
		"rubberized tread kit needs workbench")
	var bag := Inventory.new()
	bag.add("cloth_2", 2)
	bag.add("fiber_2", 2)
	bag.add("scrap", 2)
	t.eq(Crafting.craft(bag, BikeGrip.ITEM_ID, false), Crafting.Result.NO_STATION,
		"cannot forge tire grips in wilderness")
	t.eq(Crafting.craft(bag, BikeGrip.ITEM_ID, true), Crafting.Result.OK,
		"real workbench produces kit from materials")
	t.eq(bag.count(BikeGrip.ITEM_ID), 1, "one crafted kit physically exists")
	t.eq(BikeGrip.apply_reason(bag, 0.0), "missing_bike",
		"non-riders cannot apply tire grips")
	bag.add(Mounts.ITEM_ID, 1)
	t.eq(BikeGrip.apply_reason(bag, 0.0), "", "bike owner may fit kit")
	t.eq(BikeGrip.apply_reason(bag, 100.0), "already_gripped",
		"cannot stack or refresh prematurely")
	for invalid in [-1.0, NAN, INF, BikeGrip.DURATION_SECONDS + 1.0]:
		t.eq(BikeGrip.apply_reason(bag, invalid), "invalid_state",
			"corrupted timer never authorizes use")

	t.current = "client/server share actual biome and slope traction"
	var map := FlatWorld.new()
	var start := Vector3(0.0, 3.0, 0.0)
	for biome in ["swamp", "beach", "forest", "mountain"]:
		map.biome = biome
		var ordinary: float = BikeTerrain.speed_factor(map, start, Vector2.RIGHT)
		var upgraded: float = BikeTerrain.speed_factor(map, start, Vector2.RIGHT,
			BikeGrip.DURATION_SECONDS)
		t.check(upgraded > ordinary and upgraded <= 1.0,
			"wet, sandy or rough terrain improves only when fitted")
		var standard: Vector3 = Movement.step(map, start, {"x": 1.0,
			"mounted": true}, 0.1)
		var improved: Vector3 = Movement.step(map, start, {"x": 1.0,
			"mounted": true, "tire_grip_seconds": 60.0}, 0.1)
		t.check(improved.x > standard.x, "mounted movement consumes grip timer")
		var on_foot: Vector3 = Movement.step(map, start, {"x": 1.0,
			"tire_grip_seconds": 60.0}, 0.1)
		t.near(on_foot.x, Defs.WALK_SPEED * 0.1, 0.0001,
			"on-foot survivors never get offroad tire speed")
	map.biome = "plains"
	t.eq(BikeTerrain.speed_factor(map, start, Vector2.RIGHT, 60.0),
		BikeTerrain.speed_factor(map, start, Vector2.RIGHT),
		"firm roads do not accelerate further")
	map.biome = "swamp"
	map.hill = 0.2
	var ungripped: float = BikeTerrain.speed_factor(map, start, Vector2.RIGHT)
	var gripped: float = BikeTerrain.speed_factor(map, start, Vector2.RIGHT, 60.0)
	t.check(gripped > ungripped and gripped < 1.0,
		"uphill costs remain even with tire grips")
	t.eq(BikeTerrain.speed_factor(map, start, Vector2.RIGHT, NAN),
		ungripped, "malformed duration never adds traction")
	t.eq(BikeTerrain.speed_factor(map, start, Vector2.RIGHT,
		BikeGrip.DURATION_SECONDS + 1.0), ungripped,
		"overlong effect timer cannot gain unlimited speed")

	t.current = "server owns item, on-foot use and remaining duration"
	var world := WorldGen.new(311)
	var server := GameServer.new(world, 311)
	var rider = server.add_player(73, "Offroad Courier")
	rider.inventory.add(BikeGrip.ITEM_ID, 2)
	t.eq(server.cmd_use(73, BikeGrip.ITEM_ID)["reason"], "missing_bike",
		"server refuses kit without an owned bike")
	t.eq(rider.inventory.count(BikeGrip.ITEM_ID), 2, "rejected use spends no kit")
	rider.inventory.add(Mounts.ITEM_ID, 1)
	t.check(bool(server.cmd_use(73, BikeGrip.ITEM_ID).get("ok", false)),
		"authoritative fitting accepted")
	t.eq(rider.inventory.count(BikeGrip.ITEM_ID), 1, "exactly one kit debited")
	t.eq(server.cmd_use(73, BikeGrip.ITEM_ID)["reason"], "already_gripped",
		"cannot buy free extension with repeated RPC")
	t.eq(rider.inventory.count(BikeGrip.ITEM_ID), 1, "failed use preserves kit")
	t.near(float(server.snapshot_for(73)["you"]["tire_grip_seconds"]),
		BikeGrip.DURATION_SECONDS, 0.001, "owner sees server-bounded timer")
	var site: Vector3 = _find_rough_trail(world)
	t.check(site.is_finite(), "generated world has a traversable muddy wilderness trail")
	if not site.is_finite():
		return
	rider.position = site
	t.check(bool(server.cmd_toggle_mount(73).get("ok", false)),
		"real player mounts owned bike")
	t.eq(server.cmd_use(73, BikeGrip.ITEM_ID)["reason"], "mounted",
		"cannot fit tires while riding")
	var before: Vector3 = rider.position
	var expected: Vector3 = Movement.step(world, before, {"x": 1.0,
		"mounted": true, "cargo_factor": rider.inventory.movement_factor(
			rider.skills.bonus("carry_capacity")),
		"speed_bonus": rider.skills.bonus("move_speed"),
		"tire_grip_seconds": rider.tire_grip_seconds}, 0.05)
	rider.input_budget = 0.25
	server.submit_input(73, 1, 1.0, 0.0, false, 0.0, 0.05)
	t.near(rider.position.distance_to(expected), 0.0, 0.0001,
		"server uses same traction movement primitive as prediction")
	var saved: Dictionary = server.character_data(rider)
	t.check(saved.has("tire_grip_seconds"), "effect is a persisted character state")
	t.check(server.apply_character(rider, saved), "valid save loads")
	t.near(rider.tire_grip_seconds, BikeGrip.DURATION_SECONDS, 0.001,
		"relogin cannot renew a timer or remove it without expiry")
	for invalid in [-1.0, NAN, INF, BikeGrip.DURATION_SECONDS + 1.0, "100"]:
		var damaged: Dictionary = saved.duplicate(true)
		damaged["tire_grip_seconds"] = invalid
		t.check(not server.apply_character(rider, damaged), "invalid save rejected")
		t.near(rider.tire_grip_seconds, BikeGrip.DURATION_SECONDS, 0.001,
			"failed load leaves live character intact")
	var legacy: Dictionary = saved.duplicate(true)
	legacy.erase("tire_grip_seconds")
	t.check(server.apply_character(rider, legacy), "existing saves stay compatible")
	t.eq(rider.tire_grip_seconds, 0.0, "legacy characters have no free kit")
	rider.tire_grip_seconds = BikeGrip.DURATION_SECONDS
	server._tick_players(1.5)
	t.near(rider.tire_grip_seconds, BikeGrip.DURATION_SECONDS - 1.5, 0.001,
		"authoritative tick consumes off-road tire duration")
