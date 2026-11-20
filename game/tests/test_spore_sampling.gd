extends RefCounted
## Hazardous world gathering, kit payment, real crafting, client-safe snapshots
## and persisted cooldowns are all validated together.

const Defs = preload("res://scripts/shared/defs.gd")
const SporeSampling = preload("res://scripts/shared/spore_sampling.gd")
const SporeHazard = preload("res://scripts/shared/spore_hazard.gd")
const Inventory = preload("res://scripts/shared/inventory.gd")
const Crafting = preload("res://scripts/shared/crafting.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const GameServer = preload("res://scripts/server/game_server.gd")


class TestBiome:
	var biome: String = "swamp"
	var zone: int = 2
	var safe: bool = false
	var water: bool = false
	func is_safe(_x: float, _z: float) -> bool:
		return safe
	func is_water(_x: float, _z: float) -> bool:
		return water
	func zone_at(_x: float, _z: float) -> int:
		return zone
	func biome_at(_x: float, _z: float) -> String:
		return biome


func run(t) -> void:
	t.current = "paid resource loop and crafted medicine"
	t.check(Defs.is_item("spore_sampler") and Defs.is_item("spore_culture"),
		"sampler and real cultures appear in the item database")
	t.eq(Defs.recipes()["spore_sampler"]["station"], "workbench",
		"sampler crafting costs a real station")
	t.eq(Defs.recipes()["spore_antidote"]["station"], "workbench",
		"antidote requires a bench")
	var bag := Inventory.new()
	t.eq(SporeSampling.transact(bag)["reason"], "no_sample_kit",
		"no kit means no samples")
	bag.add("spore_sampler", 1)
	t.check(bool(SporeSampling.transact(bag).get("ok", false)),
		"one paid kit yields two cultures")
	t.eq(bag.count("spore_sampler"), 0, "sampler consumed exactly once")
	t.eq(bag.count("spore_culture"), 2, "two cultures credited")
	t.eq(SporeSampling.transact(bag)["reason"], "no_sample_kit",
		"replay cannot duplicate samples")
	bag.add("bandage", 1)
	bag.add("water_bottle", 1)
	t.eq(Crafting.craft(bag, "spore_antidote", false), Crafting.Result.NO_STATION,
		"antidote cannot be prepared anywhere")
	t.eq(Crafting.craft(bag, "spore_antidote", true), Crafting.Result.OK,
		"actual cultures yield one medical antidote")
	t.eq(bag.count("spore_culture"), 0, "antidote recipe consumes cultures")
	t.eq(float(Defs.item("spore_antidote")["cure"]), 75.0,
		"new medicine treats 75 infection")

	t.current = "biome authority and protection"
	var fake := TestBiome.new()
	var point := Vector3(800.0, 3.0, 250.0)
	t.eq(SporeSampling.site_reason(fake, point), "", "dangerous swamp eligible")
	t.eq(SporeSampling.site_reason(fake, Vector3.INF), "invalid_position",
		"nonfinite coordinates cannot create loot")
	fake.safe = true
	t.eq(SporeSampling.site_reason(fake, point), "safe_zone",
		"protected settlement has no dangerous samples")
	fake.safe = false
	fake.zone = 0
	t.eq(SporeSampling.site_reason(fake, point), "safe_zone",
		"green zones do not mint rare cultures")
	fake.zone = 2
	fake.water = true
	t.eq(SporeSampling.site_reason(fake, point), "in_water", "cannot harvest underwater")
	fake.water = false
	fake.biome = "plains"
	t.eq(SporeSampling.site_reason(fake, point), "no_spores", "wrong biome denied")
	t.near(SporeSampling.infection_cost(0.75), 1.25, 0.0001,
		"protective kit reduces collection infection")
	t.near(SporeSampling.infection_cost(NAN), 5.0, 0.0001,
		"malformed protection cannot eliminate infection")

	t.current = "transaction is all-or-nothing at capacity"
	var packed := Inventory.new(2)
	packed.add("spore_sampler", 2)
	packed.add("stone_1", 100)
	var snapshot: Dictionary = packed.to_dict()
	t.eq(SporeSampling.transact(packed)["reason"], "no_space",
		"no slot for cultures means no item consumption")
	t.eq(packed.to_dict(), snapshot, "every slot stays unchanged")
	var freed := Inventory.new(1)
	freed.add("spore_sampler", 1)
	t.check(bool(SporeSampling.transact(freed).get("ok", false)),
		"spent kit frees a slot for culture")

	t.current = "server, saved cooldown and suit-bound exposure"
	var world := WorldGen.new(311)
	var site := Vector2.ZERO
	for gx in range(-15, 16):
		for gz in range(-15, 16):
			var pos := Vector2(float(gx) * 80.0, float(gz) * 80.0)
			if pos.length() >= 270.0 and world.biome_at(pos.x, pos.y) == "swamp" and (
					not world.is_water(pos.x, pos.y)):
				site = pos
				break
		if site != Vector2.ZERO:
			break
	t.check(site != Vector2.ZERO, "procedural world has a dry dangerous swamp")
	if site == Vector2.ZERO:
		return
	var sim := GameServer.new(world, 311)
	var player = sim.add_player(88, "Swamp Researcher")
	player.inventory.add("spore_sampler", 2)
	t.eq(sim.cmd_sample_spores(999)["reason"], "dead",
		"unjoined players cannot sample")
	t.eq(sim.cmd_sample_spores(88)["reason"], "safe_zone",
		"hub cannot spawn cultures")
	player.position = Vector3(site.x, world.height_at(site.x, site.y), site.y)
	var initial: float = player.survival.infection
	t.check(bool(sim.cmd_sample_spores(88).get("ok", false)),
		"server authorizes genuine swamp harvest")
	t.eq(player.inventory.count("spore_sampler"), 1, "server consumes one kit")
	t.eq(player.inventory.count("spore_culture"), 2, "server credits two cultures")
	t.near(player.survival.infection - initial, 5.0, 0.001,
		"unprotected harvest adds a known risk")
	t.eq(sim.cmd_sample_spores(88)["reason"], "cooldown",
		"replay before timer expires cannot mint more cultures")
	t.near(float(sim.snapshot_for(88)["you"]["spore_sample_cooldown"]),
		SporeSampling.COOLDOWN_SECONDS, 0.001, "server timer reaches owner snapshot")
	var save: Dictionary = sim.character_data(player)
	t.check(sim.apply_character(player, save), "character state reloads")
	t.eq(player.spore_sample_cooldown, SporeSampling.COOLDOWN_SECONDS,
		"relogin does not reset timer")
	for invalid in [-1.0, NAN, INF, SporeSampling.COOLDOWN_SECONDS + 1.0, "150"]:
		var corrupt: Dictionary = save.duplicate(true)
		corrupt["spore_sample_cooldown"] = invalid
		t.check(not sim.apply_character(player, corrupt), "bad timer is rejected")
		t.eq(player.spore_sample_cooldown, SporeSampling.COOLDOWN_SECONDS,
			"failed load changes no timer")
	var legacy: Dictionary = save.duplicate(true)
	legacy.erase("spore_sample_cooldown")
	t.check(sim.apply_character(player, legacy), "old version-one saves still load")
	t.eq(player.spore_sample_cooldown, 0.0, "older saves start with no timer")
	player.inventory.add("sealed_suit_2", 1)
	player.inventory.equip("sealed_suit_2")
	var prior: float = player.survival.infection
	t.check(bool(sim.cmd_sample_spores(88).get("ok", false)),
		"protected explorer can use second paid kit")
	t.near(player.survival.infection - prior,
		SporeSampling.infection_cost(SporeHazard.protection("sealed_suit_2")),
		0.001, "real owned suit decreases sampling infection")
	sim._tick_players(0.25)
	t.check(player.spore_sample_cooldown < SporeSampling.COOLDOWN_SECONDS,
		"cooldown advances on server time")
