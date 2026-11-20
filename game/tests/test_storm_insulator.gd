extends RefCounted
## Crafting, relog protection, anti-replay and real lightning combat checks.
const Defs = preload("res://scripts/shared/defs.gd")
const Kit = preload("res://scripts/shared/storm_insulator.gd")
const Storm = preload("res://scripts/shared/storm_lightning.gd")
const StormTest = preload("res://tests/test_storm_lightning.gd")
const Crafting = preload("res://scripts/shared/crafting.gd")
const Inventory = preload("res://scripts/shared/inventory.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const GameServer = preload("res://scripts/server/game_server.gd")

func run(t) -> void:
	t.current = "workbench-paid storm protection"
	t.eq(Defs.item(Kit.ITEM_ID)["kind"], "storm_insulator", "new real item")
	t.eq(Defs.recipes()[Kit.ITEM_ID]["station"], "workbench", "must use bench")
	var bag := Inventory.new()
	bag.add("bar_2", 1)
	bag.add("cloth_2", 2)
	bag.add("scrap", 2)
	t.eq(Crafting.craft(bag, Kit.ITEM_ID, false), Crafting.Result.NO_STATION,
		"cannot make kit away from bench")
	t.eq(Crafting.craft(bag, Kit.ITEM_ID, true), Crafting.Result.OK,
		"materials create one paid insulation kit")
	t.eq(bag.count(Kit.ITEM_ID), 1, "one unit is minted")
	t.eq(Kit.apply_reason(0.0), "", "inactive timer is ready")
	t.eq(Kit.apply_reason(20.0), "already_insulated", "no stacking")
	for wrong in [-1.0, INF, NAN, Kit.DURATION_SECONDS + 1.0]:
		t.eq(Kit.apply_reason(wrong), "invalid_state", "invalid timer refused")
	t.near(Kit.lightning_damage(Storm.DAMAGE, 10.0), Storm.DAMAGE * 0.4,
		0.0001, "only forty percent of bolt damage remains")
	t.eq(Kit.lightning_damage(Storm.DAMAGE, 0.0), Storm.DAMAGE,
		"expired buff cannot absorb lightning")
	t.eq(Kit.lightning_damage(Storm.DAMAGE, INF), Storm.DAMAGE,
		"invalid buff cannot absorb lightning")
	t.eq(Kit.remaining(5.0, 10.0), 0.0, "timer does not go negative")

	t.current = "authoritative item use and strict saves"
	var world := WorldGen.new(846)
	var sim := GameServer.new(world, 846)
	var player = sim.add_player(71, "Storm Ranger")
	t.eq(sim.cmd_use(999, Kit.ITEM_ID)["reason"], "dead", "unknown peer cannot act")
	t.eq(sim.cmd_use(71, Kit.ITEM_ID)["reason"], "not_carried",
		"unowned item cannot be used")
	player.inventory.add(Kit.ITEM_ID, 2)
	t.check(bool(sim.cmd_use(71, Kit.ITEM_ID).get("ok", false)),
		"server consumes a real kit")
	t.eq(player.inventory.count(Kit.ITEM_ID), 1, "exactly one kit removed")
	t.eq(sim.cmd_use(71, Kit.ITEM_ID)["reason"], "already_insulated",
		"replaying use cannot renew timer")
	t.eq(player.inventory.count(Kit.ITEM_ID), 1, "failed call cannot consume kit")
	t.near(float(sim.snapshot_for(71)["you"]["storm_insulator_seconds"]),
		Kit.DURATION_SECONDS, 0.0001, "owner sees true countdown")
	var saved: Dictionary = sim.character_data(player)
	t.check(sim.apply_character(player, saved), "valid save restores effect")
	for bad_value in [-1.0, INF, NAN, Kit.DURATION_SECONDS + 1.0, "180"]:
		var bad: Dictionary = saved.duplicate(true)
		bad["storm_insulator_seconds"] = bad_value
		t.check(not sim.apply_character(player, bad),
			"untrusted save cannot grant extra protection")
		t.eq(player.storm_insulator_seconds, Kit.DURATION_SECONDS,
			"rejected save leaves existing buff alone")
	var legacy: Dictionary = saved.duplicate(true)
	legacy.erase("storm_insulator_seconds")
	t.check(sim.apply_character(player, legacy), "legacy saves remain compatible")
	t.eq(player.storm_insulator_seconds, 0.0, "old save has no free kit")
	t.check(bool(sim.cmd_use(71, Kit.ITEM_ID).get("ok", false)),
		"second paid kit works after old buff expires")
	sim._tick_players(0.5)
	t.check(player.storm_insulator_seconds < Kit.DURATION_SECONDS,
		"server ticks down duration")

	t.current = "real weather strike applies only shock mitigation"
	var weather_site: Dictionary = StormTest.new()._storm_site(world)
	t.check(not weather_site.is_empty(), "real storm location exists")
	if weather_site.is_empty():
		return
	var at: Vector3 = weather_site["position"]
	var now: float = weather_site["time"]
	player.position = at
	player.survival.health = player.survival.max_health
	sim.lightning_pending = Storm.create_warning(world, at, now)
	t.check(not sim.lightning_pending.is_empty(), "valid storm bolt generated")
	if sim.lightning_pending.is_empty():
		return
	sim.time = float(sim.lightning_pending["at"])
	var initial_hp: float = player.survival.health
	sim._tick_lightning()
	t.near(initial_hp - player.survival.health, Storm.DAMAGE * 0.4,
		0.0001, "server strike inflicts reduced bolt damage")
	t.check(sim.lightning_pending.is_empty(), "bolt cannot repeat")
	var after_first: float = player.survival.health
	player.dodge_immunity = 1.0
	sim.lightning_pending = Storm.create_warning(world, at, now)
	sim.time = float(sim.lightning_pending["at"])
	sim._tick_lightning()
	t.eq(player.survival.health, after_first, "actual dodge still avoids all damage")
	player.dodge_immunity = 0.0
	player.storm_insulator_seconds = 0.0
	sim.lightning_pending = Storm.create_warning(world, at, now)
	sim.time = float(sim.lightning_pending["at"])
	sim._tick_lightning()
	t.near(after_first - player.survival.health, Storm.DAMAGE, 0.0001,
		"expired kit no longer reduces a real lightning strike")
	sim._spawn_player(player)
	t.eq(player.storm_insulator_seconds, 0.0, "respawn clears old protection")
