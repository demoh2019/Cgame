extends RefCounted
## Server-authoritative cooked-meal effects, persistence and anti-forgery tests.
const Defs = preload("res://scripts/shared/defs.gd")
const HeartyMeal = preload("res://scripts/shared/hearty_meal.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const GameServer = preload("res://scripts/server/game_server.gd")


func run(t) -> void:
	t.current = "tiered cooked meals, no bonus for raw or canned food"
	for tier in range(1, Defs.MAX_TIER + 1):
		var id: String = "cooked_fish" if tier == 1 else "cooked_fish_%d" % tier
		t.eq(HeartyMeal.tier_for_food(id), tier, "prepared fish is recognized")
		t.near(HeartyMeal.duration(tier), 90.0 + 30.0 * tier, 0.001,
			"higher-tier meals last longer")
		t.check(HeartyMeal.stamina_per_second(tier) > 0.0,
			"prepared food improves stamina recovery")
		t.check(HeartyMeal.energy_per_second(tier) > 0.0,
			"prepared food improves combat energy recovery")
	t.eq(HeartyMeal.tier_for_food("raw_fish"), 0, "raw fish has no meal bonus")
	t.eq(HeartyMeal.tier_for_food("canned_food"), 0, "cans have no meal bonus")
	t.eq(HeartyMeal.tier_for_food("berries"), 0, "berries have no meal bonus")
	t.eq(HeartyMeal.tier_for_food("cooked_fish_999"), 0, "forged high tier cannot create bonus")
	t.eq(HeartyMeal.stamina_per_second(999), 0.0, "invalid rank has no recovery")

	t.current = "only bounded consistent states can be saved"
	t.check(HeartyMeal.valid_state(0.0, 0), "inactive state is valid")
	t.check(HeartyMeal.valid_state(120.0, 1), "first-tier active meal is valid")
	t.check(HeartyMeal.valid_state(210.0, 4), "highest-tier active meal is valid")
	for bad in [NAN, INF, -1.0, 211.0, "100", true]:
		t.check(not HeartyMeal.valid_state(bad, 1), "bad remaining time is refused")
	for bad_tier in [-1, 0, 5, 2.0, true, "2"]:
		t.check(not HeartyMeal.valid_state(60.0, bad_tier),
			"bad or non-integer meal tier is refused")
	t.check(not HeartyMeal.valid_state(130.0, 1), "tier one cannot claim tier four duration")
	t.check(not HeartyMeal.valid_state(0.0, 1), "expired timer cannot retain an active tier")
	t.near(HeartyMeal.bonus_seconds(1.0, 4.0), 1.0, 0.001,
		"oversized tick cannot over-award an expiring meal")
	t.near(HeartyMeal.stamina_seconds(2.0, 3.0), 0.0, 0.001,
		"existing stamina recovery delay is preserved")

	t.current = "server consumes real cooked food and awards bounded energy and stamina"
	var world := WorldGen.new(1231)
	var sim := GameServer.new(world, 1231)
	var player = sim.add_player(411, "CoastalChef")
	player.inventory.add("cooked_fish", 2)
	player.inventory.add("canned_food", 1)
	player.inventory.add("cooked_fish_3", 1)
	t.check(sim.cmd_use(411, "canned_food").get("ok", false),
		"ordinary food still satisfies hunger")
	t.near(player.meal_seconds, 0.0, 0.001, "canned food gives no temporary buff")
	t.eq(player.meal_tier, 0, "canned food leaves tier inactive")
	var fish_before: int = player.inventory.count("cooked_fish")
	t.check(sim.cmd_use(411, "cooked_fish").get("ok", false),
		"eating carried cooked fish grants meal recovery")
	t.eq(player.inventory.count("cooked_fish"), fish_before - 1,
		"meal consumes exactly one carried food item")
	t.near(player.meal_seconds, 120.0, 0.001, "T1 cooked meal lasts two minutes")
	t.eq(player.meal_tier, 1, "server sets cooked-meal tier")
	player.survival.hunger = 80.0
	player.survival.thirst = 80.0
	player.survival.stamina = 15.0
	player.survival.stamina_recovery_delay = 0.0
	player.combat_energy = 20.0
	var base_stamina: float = Defs.STAMINA_REGEN_PER_SECOND * player.survival.stamina_regen_mult
	sim._tick_players(2.0)
	t.near(player.combat_energy, 20.0 + Defs.COMBAT_ENERGY_REGEN * 2.0 +
		HeartyMeal.energy_per_second(1) * 2.0, 0.001,
		"energy regeneration includes just two seconds of meal buff")
	t.near(player.survival.stamina, 15.0 + base_stamina * 2.0 +
		HeartyMeal.stamina_per_second(1) * 2.0, 0.001,
		"stamina regeneration includes cooked fish bonus")
	t.near(player.meal_seconds, 118.0, 0.001, "server tick reduces remaining time")
	t.eq(sim.snapshot_for(411)["you"]["meal_tier"], 1,
		"owner network snapshot exposes buff rank")
	t.near(float(sim.snapshot_for(411)["you"]["meal_seconds"]), 118.0, 0.001,
		"owner network snapshot exposes remaining duration")

	t.current = "rest delay, starvation, dehydration and expiry do not exploit buff"
	player.survival.stamina = 15.0
	player.survival.stamina_recovery_delay = 3.0
	sim._tick_players(1.0)
	t.near(player.survival.stamina, 15.0, 0.001,
		"meal cannot bypass the server stamina recovery delay")
	player.survival.stamina_recovery_delay = 0.0
	player.survival.hunger = 5.0
	player.combat_energy = 10.0
	sim._tick_players(1.0)
	t.near(player.combat_energy, 10.0 + Defs.COMBAT_ENERGY_REGEN, 0.001,
		"near-starving survivors do not gain extra combat energy")
	player.survival.hunger = 80.0
	player.survival.thirst = 4.0
	player.combat_energy = 10.0
	sim._tick_players(1.0)
	t.near(player.combat_energy, 10.0 + Defs.COMBAT_ENERGY_REGEN, 0.001,
		"dehydrated survivors do not gain extra combat energy")
	player.survival.thirst = 80.0
	player.meal_seconds = 1.0
	player.meal_tier = 1
	player.combat_energy = 10.0
	sim._tick_players(4.0)
	t.near(player.combat_energy, 10.0 + Defs.COMBAT_ENERGY_REGEN * 4.0 +
		HeartyMeal.energy_per_second(1), 0.001,
		"final partial second never multiplies the bonus by the whole tick")
	t.near(player.meal_seconds, 0.0, 0.001, "expired buff has no remaining time")
	t.eq(player.meal_tier, 0, "expired buff removes active tier")

	t.current = "higher-tier cooked fish refreshes but never stacks the bonus"
	t.check(sim.cmd_use(411, "cooked_fish_3").get("ok", false),
		"tier three food can be eaten in ordinary item flow")
	t.eq(player.meal_tier, 3, "higher food overwrites prior tier")
	t.near(player.meal_seconds, 180.0, 0.001, "T3 meal lasts three minutes")
	t.check(sim.cmd_use(411, "cooked_fish").get("ok", false),
		"next meal refreshes effect instead of adding two timers")
	t.eq(player.meal_tier, 1, "replaced meal has exactly one rank")
	t.near(player.meal_seconds, 120.0, 0.001, "food never stacks time beyond its tier")

	t.current = "meal bonus round trips with strict atomic save validation"
	var saved: Dictionary = sim.character_data(player)
	t.check(sim.valid_character_data(saved), "active cooked meal is a valid saved character")
	player.meal_seconds = 0.0
	player.meal_tier = 0
	t.check(sim.apply_character(player, saved), "valid save restores cooked-food status")
	t.eq(player.meal_tier, 1, "meal tier returns after logout")
	t.near(player.meal_seconds, 120.0, 0.001, "saved meal duration returns")
	for bad in [NAN, INF, -10.0, "80", 10000.0]:
		var forged: Dictionary = saved.duplicate(true)
		forged["meal_seconds"] = bad
		var hp_before: float = player.survival.health
		t.check(not sim.apply_character(player, forged), "invalid saved food timer rejected")
		t.eq(player.meal_tier, 1, "corrupt food timer cannot rewrite tier")
		t.near(player.meal_seconds, 120.0, 0.001,
			"corrupt food timer cannot partially overwrite effect")
		t.near(player.survival.health, hp_before, 0.001,
			"bad food buff cannot partially overwrite health")
	var invalid_tier: Dictionary = saved.duplicate(true)
	invalid_tier["meal_tier"] = 99
	t.check(not sim.apply_character(player, invalid_tier), "forged food tier rejected")
	var legacy: Dictionary = saved.duplicate(true)
	legacy.erase("meal_seconds")
	legacy.erase("meal_tier")
	t.check(sim.apply_character(player, legacy), "legacy characters without food buffs load")
	t.near(player.meal_seconds, 0.0, 0.001, "older account starts without buff")
	t.eq(player.meal_tier, 0, "older account has inactive rank")

	t.current = "death and respawn remove the temporary bonus"
	t.check(sim.cmd_use(411, "cooked_fish").get("reason", "") == "not_carried",
		"consumed food cannot be re-used by replaying the request")
	player.inventory.add("cooked_fish", 1)
	t.check(sim.cmd_use(411, "cooked_fish").get("ok", false),
		"re-eating legitimately restores the buff")
	player.survival.hurt(1000.0)
	sim._on_player_death(player, -1)
	t.eq(player.meal_tier, 0, "death removes active recovery rank")
	t.near(player.meal_seconds, 0.0, 0.001, "death removes remaining buff time")
	sim._spawn_player(player)
	t.eq(player.meal_tier, 0, "respawn cannot restore a pre-death meal buff")
