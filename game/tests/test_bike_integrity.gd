extends RefCounted
## Bike frame condition is server-authored; movement and repair are reproducible.

const BikeIntegrity = preload("res://scripts/shared/bike_integrity.gd")
const GameServer = preload("res://scripts/server/game_server.gd")
const Defs = preload("res://scripts/shared/defs.gd")
const Mounts = preload("res://scripts/shared/mounts.gd")
const Movement = preload("res://scripts/shared/movement.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const BikeCargo = preload("res://scripts/shared/bike_cargo.gd")


func _open_trail(world) -> Vector3:
	for x in range(180, 361, 24):
		for z in range(180, 361, 24):
			var point := Vector3(float(x), world.height_at(float(x), float(z)), float(z))
			if not world.is_safe(point.x, point.z) and Movement.step(world, point,
					{"x": 1.0, "mounted": true}, 0.05).distance_to(point) > 0.1:
				return point
	return Vector3.INF


func run(t) -> void:
	t.current = "separate bicycle frame repair economy"
	t.eq(Defs.item(BikeIntegrity.KIT_ID).get("kind"), "bike_frame_repair",
		"repair kit is a real tradeable item")
	t.eq(Defs.recipes()[BikeIntegrity.KIT_ID]["station"], "workbench",
		"repair kit uses the crafting economy")
	t.near(BikeIntegrity.after_repair(70.0), 100.0, 0.0001,
		"repair cannot overfill frame integrity")
	t.near(BikeIntegrity.after_repair(0.0), 45.0, 0.0001,
		"repair can revive a fully broken bicycle")

	t.current = "road, mud, impact and malicious input"
	t.check(BikeIntegrity.after_ride(75.0, "swamp", 10.0) <
		BikeIntegrity.after_ride(75.0, "plains", 10.0),
		"swamp mud damages bike frame faster than firm ground")
	t.eq(BikeIntegrity.after_ride(75.0, "swamp", NAN), 75.0,
		"invalid movement cannot alter frame condition")
	t.eq(BikeIntegrity.after_ride(75.0, "swamp", -10.0), 75.0,
		"negative movement cannot heal a frame")
	t.near(BikeIntegrity.after_hit(8.0), 0.0, 0.0001,
		"real hit can break bicycle but never produce negative integrity")
	t.eq(BikeIntegrity.speed_factor(100.0), 1.0,
		"undamaged bike travels at designed speed")
	t.check(BikeIntegrity.speed_factor(15.0) < BikeIntegrity.speed_factor(50.0)
		and BikeIntegrity.speed_factor(50.0) < BikeIntegrity.speed_factor(100.0),
		"low integrity reduces riding speed in tiers")
	t.eq(BikeIntegrity.can_ride(0.0), false,
		"fully broken frames are not rideable")

	t.current = "real server owns mount and repair decisions"
	var world := WorldGen.new(42)
	var sim := GameServer.new(world, 42)
	var rider = sim.add_player(318, "FrameMechanic")
	rider.position = _open_trail(world)
	t.check(rider.position.is_finite(), "open dirt trail exists for test cycling")
	rider.bike_integrity = 0.0
	t.eq(sim.cmd_toggle_mount(318).get("reason"), "missing_bike",
		"cannot ride without a bike")
	rider.inventory.add(Mounts.ITEM_ID, 1)
	t.eq(sim.cmd_toggle_mount(318).get("reason"), "broken_bike",
		"server prevents mounting a broken frame")
	rider.inventory.add(BikeIntegrity.KIT_ID, 3)
	t.eq(sim.cmd_use(318, BikeIntegrity.KIT_ID).get("ok"), true,
		"valid item-paid repair restores broken frame")
	t.near(rider.bike_integrity, BikeIntegrity.REPAIR_POINTS, 0.001,
		"only one patch worth of integrity is restored")
	t.eq(rider.inventory.count(BikeIntegrity.KIT_ID), 2,
		"exactly one repair kit consumed")
	t.eq(sim.cmd_toggle_mount(318).get("mounted"), true,
		"fixed bike can mount without extra bypass")
	t.eq(sim.cmd_use(318, BikeIntegrity.KIT_ID).get("reason"), "mounted",
		"cannot repair while riding")

	t.current = "integrity movement is replicated and predicted"
	var start: Vector3 = rider.position
	var old_integrity: float = rider.bike_integrity
	var movement_input := {
		"x": 1.0, "mounted": true,
		"bike_integrity": old_integrity,
		"cargo_factor": BikeCargo.movement_factor(rider.inventory,
			rider.skills.bonus("carry_capacity"), true),
		"speed_bonus": rider.skills.bonus("move_speed"),
		"tire_grip_seconds": rider.tire_grip_seconds
	}
	var expected: Vector3 = Movement.step(world, start, movement_input, 0.1)
	rider.input_budget = 0.1
	sim.submit_input(318, 1, 1.0, 0.0, false, 0.0, 0.1)
	var moved: float = Vector2(rider.position.x - start.x,
		rider.position.z - start.z).length()
	t.near(rider.position.distance_to(expected), 0.0, 0.0001,
		"server uses shared physics and its own integrity value")
	t.check(moved > 0.0 and rider.bike_integrity < old_integrity,
		"actual riding distance damages bike frame")
	t.near(rider.bike_integrity, BikeIntegrity.after_ride(old_integrity,
		world.biome_at(start.x, start.z), moved), 0.0001,
		"server calculates wear from actual displacement and biome")
	t.near(float(sim.snapshot_for(318)["you"]["bike_integrity"]),
		rider.bike_integrity, 0.0001,
		"authoritative frame condition is replicated to owner")
	var after_move: float = rider.bike_integrity
	rider.input_budget = 0.1
	sim.submit_input(318, 2, 0.0, 0.0, false, 0.0, 0.1)
	t.near(rider.bike_integrity, after_move, 0.0001,
		"stationary input cannot wear frame")

	t.current = "hit dismount, repairs and anti-repair-spam"
	sim._dismount(rider, true)
	t.near(rider.bike_integrity, BikeIntegrity.after_hit(after_move), 0.0001,
		"server hit causes immediate frame damage")
	t.eq(rider.mounted, false, "hit forces dismount")
	t.eq(sim.cmd_use(318, BikeIntegrity.KIT_ID).get("ok"), true,
		"repair can restore a damaged dismounted bike")
	t.eq(rider.inventory.count(BikeIntegrity.KIT_ID), 1,
		"repair spends another physical kit")
	t.eq(sim.cmd_use(318, BikeIntegrity.KIT_ID).get("ok"), true,
		"second damaged frame patch completes repair")
	t.near(rider.bike_integrity, BikeIntegrity.MAX_INTEGRITY, 0.0001,
		"multiple paid repairs cannot exceed maximum")
	rider.inventory.add(BikeIntegrity.KIT_ID, 1)
	t.eq(sim.cmd_use(318, BikeIntegrity.KIT_ID).get("reason"), "frame_intact",
		"fully repaired bike cannot consume extra kits")
	t.eq(rider.inventory.count(BikeIntegrity.KIT_ID), 1,
		"unneeded kit remains in inventory")

	t.current = "persistent save validation"
	var saved: Dictionary = sim.character_data(rider)
	t.near(float(saved["bike_integrity"]), rider.bike_integrity, 0.0001,
		"logout saves authentic frame condition")
	var restored_sim := GameServer.new(world)
	var restored = restored_sim.add_player(318, "FrameMechanic", "", saved)
	t.near(restored.bike_integrity, rider.bike_integrity, 0.0001,
		"login preserves frame damage")
	t.eq(restored.mounted, false, "login cannot restore mount state")
	for invalid in [NAN, INF, -2.0, 101.0, "100"]:
		var forged: Dictionary = saved.duplicate(true)
		forged["bike_integrity"] = invalid
		t.eq(restored_sim.valid_character_data(forged), false,
			"invalid saved durability is rejected")
	var legacy: Dictionary = saved.duplicate(true)
	legacy.erase("bike_integrity")
	t.eq(restored_sim.valid_character_data(legacy), true,
		"old character saves default to intact bicycles")
	rider.inventory.remove(Mounts.ITEM_ID, 1)
	sim._tick_players(0.05)
	t.near(rider.bike_integrity, BikeIntegrity.MAX_INTEGRITY, 0.0001,
		"absent bike clears old frame damage before acquiring a new one")
