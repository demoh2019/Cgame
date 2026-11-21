extends RefCounted
## Field smoked-fish rations must use real fuel, server-owned timers and saves.

const Defs = preload("res://scripts/shared/defs.gd")
const TrailRation = preload("res://scripts/shared/trail_ration.gd")
const Inventory = preload("res://scripts/shared/inventory.gd")
const Crafting = preload("res://scripts/shared/crafting.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const GameServer = preload("res://scripts/server/game_server.gd")


func run(t) -> void:
	t.current = "smoked rations are ordinary safe, tiered campfire food"
	for tier in range(1, Defs.MAX_TIER + 1):
		var item_id: String = "smoked_fish" if tier == 1 else "smoked_fish_%d" % tier
		var raw_id: String = "raw_fish" if tier == 1 else "raw_fish_%d" % tier
		var wood_id: String = "wood_%d" % tier
		var data: Dictionary = Defs.item(item_id)
		t.eq(str(data.get("kind", "")), "food", "smoked tier %d is safe food" % tier)
		t.eq(TrailRation.tier_for_food(item_id), tier, "real smoked tier recognized")
		t.eq(Defs.recipes()[item_id]["station"], "campfire",
			"smoking tier %d requires a burning field campfire or hub bench" % tier)
		t.eq(Defs.recipes()[item_id]["inputs"],
			{raw_id: 1, wood_id: 2, "fiber_1": 1},
			"smoking tier %d always consumes fish, wood and fiber" % tier)
		t.check(TrailRation.duration(tier) > 0.0, "tier has a limited duration")
		t.check(TrailRation.hunger_savings(tier) > 0.0 and
			TrailRation.hunger_savings(tier) <= 0.40,
			"saved hunger never exceeds forty percent")
	t.eq(TrailRation.tier_for_food("cooked_fish"), 0,
		"ordinary cooked fish keeps its prior hearty meal buff")
	t.eq(TrailRation.tier_for_food("camp_fish_stew"), 0,
		"fish stew is not a separate smoked-ration buff")
	t.eq(TrailRation.tier_for_food("smoked_fish_99"), 0, "unregistered tiers are rejected")
	t.check(TrailRation.valid_state(0.0, 0), "legacy and inactive state is valid")
	t.check(not TrailRation.valid_state(100.0, 0), "an active timer needs a real tier")
	t.check(not TrailRation.valid_state(0.0, 2), "expired timer cannot retain a tier")
	t.check(not TrailRation.valid_state(INF, 1), "infinite duration rejected")
	t.check(not TrailRation.valid_state(NAN, 1), "NaN duration rejected")
	t.check(not TrailRation.valid_state("90", 1), "text duration rejected")
	t.check(not TrailRation.valid_state(90.0, 1.0), "float tier rejected")
	t.check(not TrailRation.valid_state(TrailRation.MAX_DURATION + 1.0, 4),
		"oversized duration rejected")
	t.check(TrailRation.valid_state(TrailRation.duration(4), 4),
		"exactly maximum earned duration is accepted")

	t.current = "quick smoking picks only a carried, craftable recipe"
	var supplies := Inventory.new()
	supplies.add("raw_fish", 1)
	supplies.add("wood_1", 2)
	t.eq(TrailRation.best_recipe(supplies, 1), "", "no fiber means no smoked ration")
	supplies.add("fiber_1", 1)
	t.eq(TrailRation.best_recipe(supplies, 1), "smoked_fish",
		"T1 recipe uses exactly owned ingredients")
	supplies.add("raw_fish_3", 1)
	supplies.add("wood_3", 2)
	t.eq(TrailRation.best_recipe(supplies, 1), "smoked_fish",
		"crafting progression prevents selecting inaccessible higher tiers")
	t.eq(TrailRation.best_recipe(supplies, 3), "smoked_fish_3",
		"higher-tier crafting and materials enable better travel rations")
	t.eq(TrailRation.best_recipe(supplies, 0), "", "invalid skill cannot create a recipe")
	t.eq(Crafting.craft(supplies, "smoked_fish", false), Crafting.Result.NO_STATION,
		"raw fish and wood cannot be smoked without a station")
	t.eq(supplies.count("raw_fish"), 1, "denied craft does not spend fish")
	t.eq(Crafting.craft(supplies, "smoked_fish", false, 1, true), Crafting.Result.OK,
		"valid lit campfire converts resources into a smoked food item")
	t.eq(supplies.count("smoked_fish"), 1, "crafted ration is real inventory food")
	t.eq(supplies.count("wood_1"), 0, "two units of T1 wood are consumed")
	t.eq(supplies.count("fiber_1"), 0, "wrapping consumes one fiber")

	t.current = "server owns cooking, buffs, owner HUD and survival ticking"
	var world := WorldGen.new(209)
	var sim := GameServer.new(world, 209)
	sim.craft_quality_enabled = false # This suite checks the item itself, not quality rolls.
	var p = sim.add_player(235, "Trail Cook")
	p.position = Vector3(140.0, world.height_at(140.0, 140.0), 140.0)
	p.inventory.add("raw_fish", 2)
	p.inventory.add("wood_1", 4)
	p.inventory.add("fiber_1", 2)
	t.eq(sim.cmd_craft(p.id, "smoked_fish").get("reason", ""), "no_station",
		"wilderness crafting without fire is denied")
	sim.campfires[987] = {"id": 987, "x": p.position.x, "y": p.position.y,
		"z": p.position.z, "expires": sim.time + 90.0}
	t.check(bool(sim.cmd_craft(p.id, "smoked_fish").get("ok", false)),
		"a server-owned active fire allows smoking fish")
	t.eq(p.inventory.count("smoked_fish"), 1, "server adds only one smoked ration")
	t.eq(p.inventory.count("raw_fish"), 1, "server debits one caught fish")
	t.eq(p.inventory.count("wood_1"), 2, "server debits two wood fuel")
	t.eq(p.inventory.count("fiber_1"), 1, "server debits one fiber")
	t.eq(sim.cmd_use(999, "smoked_fish").get("reason", ""), "dead",
		"unknown player cannot consume a ration")
	p.survival.hunger = 42.0
	var eaten: Dictionary = sim.cmd_use(p.id, "smoked_fish")
	t.check(bool(eaten.get("ok", false)) and bool(eaten.get("trail_ration", false)),
		"existing use-item authority consumes a real smoked ration")
	t.eq(p.inventory.count("smoked_fish"), 0, "item is debited only once")
	t.near(p.survival.hunger, 68.0, 0.0001, "T1 ration adds actual hunger")
	t.eq(p.ration_tier, 1, "T1 buff is server-owned")
	t.eq(p.ration_seconds, TrailRation.duration(1), "full earned duration applied")
	t.eq(p.meal_seconds, 0.0, "smoked fish does not also grant the hot meal buff")
	t.eq(sim.snapshot_for(p.id)["you"]["ration_seconds"], p.ration_seconds,
		"private HUD snapshot contains correct remaining ration duration")

	t.current = "actual hunger saving handles partial expiry and skill multipliers"
	p.survival.hunger = 60.0
	p.ration_seconds = 2.0
	var base_mult: float = p.survival.hunger_mult
	sim._tick_players(4.0)
	var expected: float = 60.0 - Defs.HUNGER_PER_SECOND * base_mult * 4.0 * (
		1.0 - TrailRation.hunger_savings(1) * 0.5)
	t.near(p.survival.hunger, expected, 0.0002,
		"a four-second tick applies saving only for two active seconds")
	t.eq(p.ration_seconds, 0.0, "timer expires at the correct time")
	t.eq(p.ration_tier, 0, "expired status loses its tier")
	t.near(p.survival.hunger_mult, base_mult, 0.00001,
		"the character skill multiplier is restored after the tick")
	t.eq(TrailRation.hunger_factor(1, 0.0, 4.0), 1.0,
		"expired rations have no passive benefit")
	var split_factor: float = TrailRation.hunger_factor(2, 1.0, 4.0)
	t.near(split_factor, 1.0 - TrailRation.hunger_savings(2) / 4.0, 0.00001,
		"partial final tick cannot grant extra protection")
	t.near(TrailRation.hunger_factor(1, 2.0, 0.0), 1.0, 0.00001,
		"zero delta is safe")

	t.current = "stronger ration replaces weaker instead of stacking durations"
	p.survival.hunger = 30.0
	p.inventory.add("smoked_fish_2", 1)
	t.check(bool(sim.cmd_use(p.id, "smoked_fish_2").get("ok", false)),
		"a carried T2 ration can replace a finished T1 ration")
	t.eq(p.ration_tier, 2, "stronger ration rank is applied")
	t.eq(p.ration_seconds, TrailRation.duration(2), "stronger ration gets own duration")
	p.inventory.add("smoked_fish", 1)
	p.survival.hunger = 30.0
	t.check(bool(sim.cmd_use(p.id, "smoked_fish").get("ok", false)),
		"weaker smoked fish remains useful as food")
	t.eq(p.ration_tier, 2, "weaker food does not overwrite stronger protection")
	t.eq(p.ration_seconds, TrailRation.duration(2),
		"weaker food cannot extend a stronger timed buff")

	t.current = "strict persistence, no timer injection and pre-feature migration"
	var saved: Dictionary = sim.character_data(p)
	t.eq(saved["ration_seconds"], TrailRation.duration(2),
		"ration duration is saved on the character")
	t.check(sim.valid_character_data(saved), "legitimate saved ration is accepted")
	p.ration_seconds = 0.0
	p.ration_tier = 0
	t.check(sim.apply_character(p, saved), "rejoin restores a paid ration")
	t.eq(p.ration_tier, 2, "reconnect restores proper tier")
	t.eq(p.ration_seconds, TrailRation.duration(2),
		"reconnect cannot reset or increase the earned countdown")
	for forged in [
		{"ration_seconds": -1.0, "ration_tier": 2},
		{"ration_seconds": INF, "ration_tier": 2},
		{"ration_seconds": NAN, "ration_tier": 2},
		{"ration_seconds": "270", "ration_tier": 2},
		{"ration_seconds": TrailRation.MAX_DURATION, "ration_tier": 1},
		{"ration_seconds": 120.0, "ration_tier": 0},
		{"ration_seconds": 0.0, "ration_tier": 3},
		{"ration_seconds": 120.0, "ration_tier": 2.0}
	]:
		var invalid: Dictionary = saved.duplicate(true)
		invalid.merge(forged, true)
		t.check(not sim.apply_character(p, invalid),
			"invalid ration save cannot create unearned hunger protection")
		t.eq(p.ration_tier, 2, "rejected save leaves earned rank intact")
		t.eq(p.ration_seconds, TrailRation.duration(2),
			"rejected save leaves earned duration intact")
	var legacy: Dictionary = saved.duplicate(true)
	legacy.erase("ration_seconds")
	legacy.erase("ration_tier")
	t.check(sim.apply_character(p, legacy), "old saves remain compatible")
	t.eq(p.ration_seconds, 0.0, "legacy account begins without ration")
	t.eq(p.ration_tier, 0, "legacy account has no fabricated tier")
	t.check(sim.apply_character(p, saved), "ordinary save can be reloaded again")
	sim._spawn_player(p)
	t.eq(p.ration_seconds, 0.0, "respawn removes transient travel protection")
	t.eq(p.ration_tier, 0, "respawn clears expired tier too")
