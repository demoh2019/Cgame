extends RefCounted
## End-to-end deterministic swamp spore exposure and protective gear regression.

const Defs = preload("res://scripts/shared/defs.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const WorldCycle = preload("res://scripts/shared/world_cycle.gd")
const GameServer = preload("res://scripts/server/game_server.gd")
const SporeHazard = preload("res://scripts/shared/spore_hazard.gd")
const Inventory = preload("res://scripts/shared/inventory.gd")
const Crafting = preload("res://scripts/shared/crafting.gd")


class TestBiome:
	var biome: String = "swamp"
	var zone: int = 2
	var safe: bool = false

	func is_safe(_x: float, _z: float) -> bool:
		return safe

	func zone_at(_x: float, _z: float) -> int:
		return zone

	func biome_at(_x: float, _z: float) -> String:
		return biome


func run(t) -> void:
	t.current = "pure swamp hazard, time and safety boundaries"
	var fake := TestBiome.new()
	var position := Vector3(800.0, 2.0, 200.0)
	var day: Dictionary = SporeHazard.status(fake, position, 100.0)
	t.check(bool(day["active"]), "unsafe swamp has airborne spores")
	t.near(float(day["rate"]), SporeHazard.DAY_INFECTION_PER_SECOND, 0.0001,
		"daytime spores have bounded infection rate")
	var night: Dictionary = SporeHazard.status(fake, position, 650.0)
	t.check(WorldCycle.is_night(650.0), "night test uses real world cycle")
	t.near(float(night["rate"]), SporeHazard.NIGHT_INFECTION_PER_SECOND, 0.0001,
		"night increases airborne danger")
	t.check(not bool(SporeHazard.status(fake, Vector3(INF, 0.0, 0.0), 100.0)["active"]),
		"invalid positions reject hazard")
	t.check(not bool(SporeHazard.status(fake, position, NAN)["active"]),
		"invalid clock rejects hazard")
	fake.safe = true
	t.check(not bool(SporeHazard.status(fake, position, 100.0)["active"]),
		"settlement shelter blocks spores")
	fake.safe = false
	fake.biome = "plains"
	t.check(not bool(SporeHazard.status(fake, position, 100.0)["active"]),
		"ordinary land remains safe")
	fake.biome = "swamp"
	fake.zone = 0
	t.check(not bool(SporeHazard.status(fake, position, 100.0)["active"]),
		"green zone remains free of spore infection")
	fake.zone = 2

	t.current = "craftable sealed suits have tiered protection"
	var bag := Inventory.new()
	for tier in range(2, 5):
		var armor: String = "sealed_suit_%d" % tier
		t.check(Defs.is_item(armor), "protective armor exists at tier %d" % tier)
		t.check(Defs.recipes().has(armor), "suit recipe exists at tier %d" % tier)
		var expected: float = 0.65 + 0.1 * float(tier - 2)
		t.near(SporeHazard.protection(armor), expected, 0.0001,
			"tier protection is accurately defined")
	t.near(SporeHazard.protection("jacket_2"), 0.0, 0.0001,
		"ordinary armor does not protect from spores")
	t.near(SporeHazard.protection("antibiotics"), 0.0, 0.0001,
		"carrying medicine is not protective equipment")
	t.near(float(SporeHazard.status(fake, position, 100.0, "sealed_suit_2")["rate"]),
		float(day["rate"]) * 0.35, 0.0001, "T2 suit mitigates airborne infection")
	t.near(float(SporeHazard.status(fake, position, 100.0, "sealed_suit_4")["rate"]),
		float(day["rate"]) * 0.15, 0.0001, "T4 suit mitigates more")
	t.eq(Crafting.craft(bag, "sealed_suit_2", true),
		Crafting.Result.MISSING_INPUTS, "cannot create a suit from nothing")
	bag.add("cloth_2", 5)
	bag.add("bar_2", 2)
	bag.add("fiber_2", 3)
	t.eq(Crafting.craft(bag, "sealed_suit_2", true),
		Crafting.Result.OK, "workbench crafts the real equipment")
	t.eq(bag.count("sealed_suit_2"), 1, "crafting grants one suit")
	t.eq(bag.count("cloth_2"), 0, "crafting pays real cloth costs")

	t.current = "game server exposure, stale equipment, events and persistence"
	var world := WorldGen.new(311)
	var swamp := Vector2.ZERO
	for gx in range(-15, 16):
		for gz in range(-15, 16):
			var at := Vector2(float(gx) * 80.0, float(gz) * 80.0)
			if at.length() >= 270.0 and world.biome_at(at.x, at.y) == "swamp":
				swamp = at
				break
		if swamp != Vector2.ZERO:
			break
	t.check(swamp != Vector2.ZERO, "world generates a dangerous swamp")
	if swamp == Vector2.ZERO:
		return
	var server := GameServer.new(world, 311)
	var player = server.add_player(42, "Spore Survivor")
	player.position = Vector3(swamp.x, world.height_at(swamp.x, swamp.y), swamp.y)
	server.time = 100.0
	var before: float = player.survival.infection
	server._tick_players(4.0)
	var after: float = player.survival.infection
	t.check(after > before, "server time, not a client flag, applies exposure")
	var snapshot: Dictionary = server.snapshot_for(42)["you"]
	t.check(bool(snapshot["spore"]["active"]), "server publishes active hazard")
	t.near(float(snapshot["spore"]["rate"]), SporeHazard.DAY_INFECTION_PER_SECOND,
		0.0001, "unprotected snapshot reports true rate")
	var entered := false
	for event in server.events:
		if event.get("type") == "spore_enter" and event.get("peer") == 42:
			entered = true
	t.check(entered, "entering the swamp sends one warning")
	player.inventory.add("sealed_suit_2", 1)
	player.inventory.equip("sealed_suit_2")
	var geared: Dictionary = server.snapshot_for(42)["you"]["spore"]
	t.near(float(geared["protection"]), 0.65, 0.0001,
		"snapshot uses equipped protective suit")
	server._tick_players(4.0)
	t.near(float(server.snapshot_for(42)["you"]["spore"]["rate"]),
		SporeHazard.DAY_INFECTION_PER_SECOND * 0.35, 0.0001,
		"server applies lower rate when suit is equipped")
	player.inventory.remove("sealed_suit_2", 1)
	player.inventory.armor = "sealed_suit_2"
	t.near(float(server.snapshot_for(42)["you"]["spore"]["protection"]), 0.0,
		0.0001, "stale gear ID without actual item gives no protection")
	var saved: Dictionary = server.character_data(player)
	t.check(saved.has("infection") and float(saved["infection"]) > 0.0,
		"existing character save persists spore-acquired infection")
	var stored: float = float(saved["infection"])
	player.survival.treat_infection(100.0)
	t.check(server.apply_character(player, saved), "existing save loader restores survivor")
	t.near(player.survival.infection, stored, 0.0001,
		"spore infection survives re-login")
	player.position = Vector3(0.0, world.height_at(0.0, 0.0), 0.0)
	server._tick_players(0.1)
	t.check(not bool(server.snapshot_for(42)["you"]["spore"]["active"]),
		"hub removes airborne hazard")
	var cleared := false
	for event in server.events:
		if event.get("type") == "spore_exit" and event.get("peer") == 42:
			cleared = true
	t.check(cleared, "leaving spores sends one clear-air event")
