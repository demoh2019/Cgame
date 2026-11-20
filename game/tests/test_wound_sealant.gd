extends RefCounted
## Deterministic server-backed crafting, a real infected melee hit, saves and expiry.

const Defs = preload("res://scripts/shared/defs.gd")
const WoundSealant = preload("res://scripts/shared/wound_sealant.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const GameServer = preload("res://scripts/server/game_server.gd")
const Zombie = preload("res://scripts/shared/zombie.gd")


func _hit(sim, victim) -> void:
	sim.zombies.clear()
	var infected := Zombie.new(sim.new_id(), "walker",
		victim.position + Vector3(1.1, 0.0, 0.0))
	infected.state = Zombie.State.ATTACK
	infected.target_id = victim.id
	sim.zombies[infected.id] = infected
	sim._tick_zombies(0.1)


func run(t) -> void:
	t.current = "paid field crafting, scope and anti-repeat protection"
	t.check(Defs.is_item(WoundSealant.ITEM_ID), "wound seal is a catalog item")
	t.eq(Defs.item(WoundSealant.ITEM_ID).get("kind", ""), "wound_seal",
		"dedicated defensive consumable")
	var recipe: Dictionary = Defs.recipes().get(WoundSealant.ITEM_ID, {})
	t.eq(recipe.get("inputs", {}),
		{"wild_herbs": 2, "field_antiseptic": 1, "cloth_1": 1},
		"uses gathered herbs and existing medical supplies")
	t.eq(recipe.get("station", "?"), "", "field crafting needs no workbench")
	t.near(WoundSealant.mitigate(8.0, 90.0), 4.4, 0.001,
		"45 percent of bite infection prevented")
	t.near(WoundSealant.mitigate(8.0, 0.0), 8.0, 0.001,
		"expiry removes protection")
	t.near(WoundSealant.mitigate(8.0, NAN), 8.0, 0.001,
		"invalid timer provides no buff")
	var world := WorldGen.new(418)
	var sim := GameServer.new(world, 418)
	var survivor = sim.add_player(748, "Field Medic")
	t.eq(sim.cmd_use(999, WoundSealant.ITEM_ID).get("reason", ""), "dead",
		"unknown peers cannot spend medical items")
	t.eq(sim.cmd_use(survivor.id, WoundSealant.ITEM_ID).get("reason", ""),
		"not_carried", "no free dose")
	survivor.inventory.add("wild_herbs", 2)
	survivor.inventory.add("cloth_1", 1)
	t.eq(sim.cmd_craft(survivor.id, WoundSealant.ITEM_ID).get("reason", ""),
		"missing_inputs", "missing antiseptic prevents crafting")
	survivor.inventory.add("field_antiseptic", 1)
	t.check(sim.cmd_craft(survivor.id, WoundSealant.ITEM_ID).get("ok", false),
		"field crafting consumes real items")
	t.eq(survivor.inventory.count("wild_herbs"), 0, "herbs debited")
	t.eq(survivor.inventory.count("field_antiseptic"), 0, "antiseptic debited")
	t.eq(survivor.inventory.count(WoundSealant.ITEM_ID), 1, "seal enters the bag")
	var activation: Dictionary = sim.cmd_use(survivor.id, WoundSealant.ITEM_ID)
	t.check(activation.get("ok", false) and activation.get("wound_seal", false),
		"ordinary authenticated item use activates the dressing")
	t.eq(survivor.inventory.count(WoundSealant.ITEM_ID), 0, "one dose consumed")
	t.near(survivor.wound_seal_seconds, WoundSealant.DURATION_SECONDS, 0.001,
		"duration is owned by the server")
	t.near(float(sim.snapshot_for(survivor.id)["you"]["wound_seal_seconds"]),
		WoundSealant.DURATION_SECONDS, 0.001, "personal HUD sees timer")
	survivor.inventory.add(WoundSealant.ITEM_ID, 1)
	t.eq(sim.cmd_use(survivor.id, WoundSealant.ITEM_ID).get("reason", ""),
		"already_sealed", "reapplication cannot stack or refresh")
	t.eq(survivor.inventory.count(WoundSealant.ITEM_ID), 1,
		"refused application preserves inventory")

	t.current = "real infected bite mitigated without damage or bleeding immunity"
	survivor.position = Vector3(200.0, world.height_at(200.0, 200.0), 200.0)
	survivor.survival.reset()
	_hit(sim, survivor)
	t.near(survivor.survival.infection, 8.0 * WoundSealant.INFECTION_FACTOR,
		0.001, "real walker attack uses the reduced infection")
	t.near(survivor.survival.bleeding, Defs.ZOMBIE_BLEEDING_PER_HIT["walker"],
		0.001, "bleeding still applies normally")
	t.near(survivor.survival.health, Defs.MAX_HEALTH - 9.0, 0.001,
		"direct injury damage is unchanged")
	survivor.survival.reset()
	survivor.wound_seal_seconds = 0.0
	_hit(sim, survivor)
	t.near(survivor.survival.infection, 8.0, 0.001,
		"expired seal no longer blocks infection")

	t.current = "validated save, legacy load, expiry and death cleanup"
	survivor.wound_seal_seconds = 32.0
	var saved: Dictionary = sim.character_data(survivor)
	survivor.wound_seal_seconds = 0.0
	t.check(sim.apply_character(survivor, saved), "effect survives relog")
	t.near(survivor.wound_seal_seconds, 32.0, 0.001,
		"relog cannot reset remaining duration")
	for invalid in [-1.0, WoundSealant.DURATION_SECONDS + 1.0, NAN, INF, "32", true]:
		var corrupt: Dictionary = saved.duplicate(true)
		corrupt["wound_seal_seconds"] = invalid
		t.check(not sim.apply_character(survivor, corrupt),
			"corrupt timer rejected atomically")
		t.near(survivor.wound_seal_seconds, 32.0, 0.001,
			"invalid save leaves existing duration intact")
	var legacy: Dictionary = saved.duplicate(true)
	legacy.erase("wound_seal_seconds")
	t.check(sim.apply_character(survivor, legacy), "older saves still load")
	t.eq(survivor.wound_seal_seconds, 0.0, "legacy save grants no free buff")
	t.check(sim.apply_character(survivor, saved), "original save restores")
	survivor.position = Vector3(0.0, world.height_at(0.0, 0.0), 0.0)
	sim._tick_players(33.0)
	t.near(survivor.wound_seal_seconds, 0.0, 0.001,
		"server decrements and expires the timed buff")
	survivor.wound_seal_seconds = 10.0
	survivor.survival.hurt(1000.0)
	sim._on_player_death(survivor, -1)
	t.eq(survivor.wound_seal_seconds, 0.0, "death clears protection")
