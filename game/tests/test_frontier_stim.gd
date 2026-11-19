extends RefCounted
## A rare PvE-sourced consumable must never duplicate energy, gear or cooldown.
const Defs = preload("res://scripts/shared/defs.gd")
const Crafting = preload("res://scripts/shared/crafting.gd")
const FrontierStim = preload("res://scripts/shared/frontier_stim.gd")
const GameServer = preload("res://scripts/server/game_server.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")


func _at(world, x: float, z: float) -> Vector3:
	return Vector3(x, world.height_at(x, z), z)


func run(t) -> void:
	t.current = "frontier stim definitions and character requirements"
	t.check(Defs.is_item(FrontierStim.ITEM_ID), "stimulant is registered as a real item")
	t.eq(Defs.item(FrontierStim.ITEM_ID)["kind"], "stimulant",
		"stimulant has a distinct item type, not a free medical buff")
	t.check(Defs.recipes().has(FrontierStim.ITEM_ID), "workbench recipe is available")
	var rule: Dictionary = Defs.recipes()[FrontierStim.ITEM_ID]
	t.eq(rule["station"], "workbench", "rare injection must be crafted at the workbench")
	t.eq(rule["inputs"]["infected_core"], 1, "recipe consumes a real infected trophy")
	t.eq(rule["inputs"]["field_antiseptic"], 1, "recipe consumes a real medical kit")
	t.eq(rule["inputs"]["water_bottle"], 1, "recipe consumes a clean water bottle")
	t.eq(FrontierStim.COOLDOWN, 90.0, "server uses a fixed 90-second cooldown")
	t.eq(FrontierStim.ready(null, 20.0, 0.0), "dead",
		"nonexistent or dead survivor cannot use a stimulant")


	var world := WorldGen.new(109)
	var server := GameServer.new(world, 109)
	var p = server.add_player(417, "Expedition survivor")
	t.eq(server.cmd_use(p.id, FrontierStim.ITEM_ID)["reason"], "not_carried",
		"empty inventory cannot trigger a free stamina or energy refill")
	p.inventory.add("infected_core", 1)
	p.inventory.add("field_antiseptic", 1)
	p.position = _at(world, 180.0, 0.0)
	t.eq(server.cmd_craft(p.id, FrontierStim.ITEM_ID)["reason"], "need_skill",
		"a novice cannot create elite T3 medicine without crafting mastery")
	p.progression.award_craft(1, 8)
	t.check(p.progression.can_craft_tier(3),
		"real crafting progression unlocks T3 equipment and medicine")
	t.eq(server.cmd_craft(p.id, FrontierStim.ITEM_ID)["reason"], "no_station",
		"crafting remotely is refused by the server")
	t.eq(p.inventory.count("infected_core"), 1, "rejected craft preserves rare trophy")
	p.position = _at(world, GameServer.WORKBENCH_POSITION.x,
		GameServer.WORKBENCH_POSITION.y)
	var crafted: Dictionary = server.cmd_craft(p.id, FrontierStim.ITEM_ID)
	t.check(bool(crafted.get("ok", false)), "server creates exactly one legitimate stimulant")
	t.eq(p.inventory.count(FrontierStim.ITEM_ID), 1, "crafted dose enters backpack")
	t.eq(p.inventory.count("infected_core"), 0, "trophy is actually consumed")
	t.eq(p.inventory.count("field_antiseptic"), 0, "medical material is consumed")

	t.current = "stimulant must only work when tired and hydrated"
	p.survival.thirst = 70.0
	p.survival.stamina = 100.0
	p.combat_energy = Defs.COMBAT_ENERGY_MAX
	t.eq(server.cmd_use(p.id, FrontierStim.ITEM_ID)["reason"], "no_effect",
		"fully rested players cannot waste or exploit an injection")
	t.eq(p.inventory.count(FrontierStim.ITEM_ID), 1,
		"no-effect injection never spends an item")
	p.survival.stamina = 30.0
	p.combat_energy = 25.0
	p.survival.thirst = 10.0
	t.eq(server.cmd_use(p.id, FrontierStim.ITEM_ID)["reason"], "too_thirsty",
		"dehydrated survivor cannot activate stimulant")
	t.eq(p.inventory.count(FrontierStim.ITEM_ID), 1,
		"failed dehydration check preserves the dose")
	p.survival.thirst = 70.0
	var result: Dictionary = server.cmd_use(p.id, FrontierStim.ITEM_ID)
	t.check(result.get("ok", false), "server accepts a legal paid injection")
	t.near(p.survival.stamina, 80.0, 0.0001,
		"50 stamina restored without going above cap")
	t.near(p.combat_energy, 60.0, 0.0001,
		"35 combat energy restored without overfilling")
	t.near(p.survival.thirst, 58.0, 0.0001,
		"immediate recovery costs twelve thirst")
	t.eq(p.inventory.count(FrontierStim.ITEM_ID), 0,
		"one inventory dose is charged exactly once")
	t.eq(p.stim_cooldown, FrontierStim.COOLDOWN, "server begins real cooldown")
	t.check(p.dirty_inventory and p.dirty_character,
		"successful use marks both inventory and account save dirty")

	t.current = "replay and cooldown guard"
	p.inventory.add(FrontierStim.ITEM_ID, 2)
	var before_state: Dictionary = p.inventory.to_dict()
	t.eq(server.cmd_use(p.id, FrontierStim.ITEM_ID)["reason"], "cooldown",
		"replayed/rapid RPC cannot reuse the injection")
	t.eq(p.inventory.to_dict(), before_state, "rejected replay preserves all stacks")
	server._tick_players(5.0)
	t.near(p.stim_cooldown, FrontierStim.COOLDOWN - 5.0, 0.0001,
		"only authoritative server time reduces the cooldown")
	t.eq(p.inventory.count(FrontierStim.ITEM_ID), 2,
		"elapsed time does not consume additional inventory")
	var own: Dictionary = server.snapshot_for(p.id)["you"]
	t.near(float(own["stim_cooldown"]), p.stim_cooldown, 0.0001,
		"owner HUD sees server-owned cooldown")
	server._tick_players(-5.0)
	t.near(p.stim_cooldown, FrontierStim.COOLDOWN - 5.0, 0.0001,
		"negative deltas cannot reduce recharge time")

	t.current = "restore, migration and invalid saved cooldown"
	var saved: Dictionary = server.character_data(p)
	t.near(float(saved["stim_cooldown"]), p.stim_cooldown, 0.0001,
		"account character record persists the remaining cooldown")
	var stored: float = p.stim_cooldown
	p.stim_cooldown = 0.0
	t.check(server.apply_character(p, saved), "saved character cooldown restores")
	t.near(p.stim_cooldown, stored, 0.0001,
		"restoring an account cannot clear a running cooldown")
	var legacy: Dictionary = saved.duplicate(true)
	legacy.erase("stim_cooldown")
	t.check(server.apply_character(p, legacy),
		"pre-stimulant version-one saves still load")
	t.eq(p.stim_cooldown, 0.0, "old character defaults to zero cooldown")
	t.check(server.apply_character(p, saved), "restore saved cooldown again")
	for invalid in [-1.0, INF, NAN, 91.0, "90", true]:
		var corrupted: Dictionary = saved.duplicate(true)
		corrupted["stim_cooldown"] = invalid
		t.check(not server.apply_character(p, corrupted),
			"corrupt cooldown is rejected before modifying the character")
		t.near(p.stim_cooldown, stored, 0.0001,
			"failed validation cannot reset a live cooldown")
	t.check(server.valid_character_data(saved),
		"full character validation accepts a saved cooldown")
	var broken: Dictionary = saved.duplicate(true)
	broken["stim_cooldown"] = INF
	t.check(not server.valid_character_data(broken),
		"remote save validation rejects an infinite cooldown")

	t.current = "respawn does not bypass cooldown"
	p.survival.hurt(1000.0)
	server._on_player_death(p, -1)
	server._spawn_player(p)
	t.near(p.stim_cooldown, stored, 0.0001,
		"death and respawn do not refresh the limited combat consumable")
	p.inventory.add(FrontierStim.ITEM_ID, 1)
	t.eq(server.cmd_use(p.id, FrontierStim.ITEM_ID)["reason"], "cooldown",
		"freshly respawned survivor still cannot use an old active cooldown")
	t.eq(p.inventory.count(FrontierStim.ITEM_ID), 1,
		"blocked respawn use leaves the fresh dose untouched")
