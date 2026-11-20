extends RefCounted
## Server-owned cargo mount upgrade: no invented backpack slots or free on-foot capacity.

const BikeCargo = preload("res://scripts/shared/bike_cargo.gd")
const Defs = preload("res://scripts/shared/defs.gd")
const Inventory = preload("res://scripts/shared/inventory.gd")
const Mounts = preload("res://scripts/shared/mounts.gd")
const GameServer = preload("res://scripts/server/game_server.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const Movement = preload("res://scripts/shared/movement.gd")


func run(t) -> void:
	t.current = "craftable cargo equipment"
	t.eq(Defs.item(BikeCargo.ITEM_ID).get("kind"), "bike_cargo", "panniers have a real item definition")
	t.eq(Defs.recipes()[BikeCargo.ITEM_ID]["station"], "workbench", "must craft at a station")
	var inv := Inventory.new()
	t.eq(BikeCargo.installed(inv), false, "empty inventory has no free bike cargo")
	inv.add(BikeCargo.ITEM_ID, 2)
	t.eq(BikeCargo.installed(inv), false, "bags alone cannot create a bicycle")
	inv.add(Mounts.ITEM_ID, 1)
	t.eq(BikeCargo.installed(inv), true, "bike and bags required")
	var base_mass: float = inv.total_weight()
	t.near(BikeCargo.effective_weight(inv, true), maxf(0.0, base_mass - BikeCargo.SUPPORTED_KG),
		0.0001, "carried item weight remains part of the real inventory")
	t.near(BikeCargo.effective_weight(inv, false), base_mass, 0.0001,
		"dismount restores the actual pack weight")
	inv.remove(Mounts.ITEM_ID, 1)
	t.near(BikeCargo.effective_weight(inv, true), inv.total_weight(), 0.0001,
		"losing the bicycle removes its cargo support")

	t.current = "server mount, loaded travel and dismount"
	var world := WorldGen.new(42)
	var server := GameServer.new(world)
	var rider = server.add_player(83, "CargoRider")
	# 22 stones weigh 44 kg. With the 12 kg bike, 3 kg panniers and starter
	# supplies the real load is heavy, but bike support keeps effective load <= 35 kg.
	rider.inventory.add("stone_1", 22)
	rider.inventory.add(Mounts.ITEM_ID, 1)
	t.check(BikeCargo.movement_factor(rider.inventory, 0.0, false) < 0.9999,
		"unassisted loaded traveler cannot ride")
	t.eq(server.cmd_toggle_mount(83).get("reason"), "overweight",
		"bike without saddle bags cannot bypass encumbrance")
	rider.inventory.add(BikeCargo.ITEM_ID, 1)
	t.check(BikeCargo.movement_factor(rider.inventory, 0.0, true) >= 0.9999,
		"fitted cargo removes load penalty up to its finite limit")
	t.check(bool(server.cmd_toggle_mount(83).get("mounted", false)),
		"loaded bicycle can now mount when bags support the weight")
	var before: int = rider.position
	var expected := Movement.step(world, before, {
		"x": 1.0, "mounted": true, "cargo_factor":
		BikeCargo.movement_factor(rider.inventory, rider.skills.bonus("carry_capacity"), true),
		"speed_bonus": rider.skills.bonus("move_speed"),
	}, 0.1)
	rider.input_budget = 0.1
	server.submit_input(83, 1, 1.0, 0.0, false, 0.0, 0.1)
	t.near(rider.position.distance_to(expected), 0.0, 0.0001,
		"server travel speed matches shared mounted calculation")
	t.near(float(server.snapshot_for(83)["you"]["cargo_factor"]),
		BikeCargo.movement_factor(rider.inventory, rider.skills.bonus("carry_capacity"), true),
		0.0001, "network snapshot reports server cargo support")
	t.near(float(server.snapshot_for(83)["you"]["bike_cargo_kg"]),
		BikeCargo.SUPPORTED_KG, 0.0001, "network snapshot advertises only real cargo support")
	server.cmd_toggle_mount(83)
	t.check(not rider.mounted, "dismount remains possible under load")
	t.check(float(server.snapshot_for(83)["you"]["cargo_factor"]) < 0.9999,
		"on-foot load factor returns immediately after dismount")

	t.current = "cargo upgrade cannot be exploited"
	rider.mount_cooldown = 0.0
	t.check(bool(server.cmd_toggle_mount(83).get("mounted", false)),
		"mounting again is possible after cooldown")
	rider.inventory.remove(BikeCargo.ITEM_ID, 1)
	server._tick_players(0.05)
	t.eq(rider.mounted, false, "losing bags dismounts an overloaded rider")
	t.eq(server.cmd_toggle_mount(83).get("reason"), "cooldown",
		"normal dismount cooldown still applies")
	rider.mount_cooldown = 0.0
	rider.inventory.add(BikeCargo.ITEM_ID, 1)
	rider.inventory.add("stone_1", 18)
	t.check(BikeCargo.movement_factor(rider.inventory, 0.0, true) < 0.9999,
		"finite support cannot carry arbitrarily heavy loads")
	t.eq(server.cmd_toggle_mount(83).get("reason"), "overweight",
		"server refuses an over-capacity bicycle")

	t.current = "cargo inventory persistence"
	var saved: Dictionary = server.character_data(rider)
	var restore := GameServer.new(world)
	var rejoined = restore.add_player(83, "CargoRider", "", saved)
	t.eq(rejoined.inventory.count(BikeCargo.ITEM_ID), 1, "cargo bags persist as items")
	t.eq(rejoined.mounted, false, "riding state never persists")
	t.near(rejoined.inventory.total_weight(), rider.inventory.total_weight(), 0.001,
		"cargo has not duplicated or removed actual items")
