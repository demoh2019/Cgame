extends RefCounted
## Real server PvP, safe-zone immunity, vendor economics and save validation.

const WorldGen = preload("res://scripts/shared/world_gen.gd")
const GameServer = preload("res://scripts/server/game_server.gd")
const PvpInfamy = preload("res://scripts/shared/pvp_infamy.gd")
const Vendor = preload("res://scripts/shared/vendor.gd")
const Zombie = preload("res://scripts/shared/zombie.gd")


func _at(world, x: float, z: float) -> Vector3:
	return Vector3(x, world.height_at(x, z), z)


func run(t) -> void:
	t.current = "infamy values, decay and deterministic prices"
	t.check(PvpInfamy.valid(0.0) and PvpInfamy.valid(100.0), "bounds are valid")
	for invalid in [-1.0, 101.0, NAN, INF, "10", true]:
		t.check(not PvpInfamy.valid(invalid), "invalid persistent score rejected")
	t.near(PvpInfamy.gain_for_kill(80.0), 100.0, 0.0001,
		"confirmed kills cap at 100")
	t.near(PvpInfamy.decay(25.0, 180.0), 24.0, 0.0001,
		"one point fades over three online minutes")
	t.near(PvpInfamy.decay(1.0, 360.0), 0.0, 0.0001,
		"decay never makes a negative score")
	t.near(PvpInfamy.decay(25.0, NAN), 25.0, 0.0001,
		"invalid clock advances do not remove reputation")
	t.check(not PvpInfamy.is_outlaw(49.99) and PvpInfamy.is_outlaw(50.0),
		"outlaw threshold requires two kills")
	t.eq(PvpInfamy.vendor_unit_price(12, 0.0, true), 12,
		"new and legacy characters pay normal purchase price")
	t.eq(PvpInfamy.vendor_unit_price(12, 50.0, true), 15,
		"infamy raises supply purchase cost")
	t.eq(PvpInfamy.vendor_unit_price(32, 50.0, false), 28,
		"infamy lowers salvage payout")
	t.eq(PvpInfamy.vendor_unit_price(3, 100.0, false), 2,
		"cheap items keep a positive payout")
	t.eq(PvpInfamy.vendor_unit_price(12, NAN, true), 0,
		"invalid score cannot calculate a discounted vendor price")

	t.current = "confirmed red-zone player kills only"
	var world := WorldGen.new(163)
	var server := GameServer.new(world, 163)
	var killer = server.add_player(101, "Ranger")
	var victim = server.add_player(102, "Challenger")
	var neutral = server.add_player(103, "Trader")
	killer.inventory.add("club_1", 1)
	killer.inventory.equip("club_1")
	killer.position = _at(world, 800.0, 0.0)
	victim.position = _at(world, 801.5, 0.0)
	victim.survival.hurt(95.0)
	var hit: Dictionary = server.cmd_attack(101, 1.0, 0.0)
	t.check(hit.get("ok", false) and hit.get("hit", false),
		"real server combat accepts lethal hit in red zone")
	t.check(not victim.survival.alive, "first victim is dead")
	t.near(killer.pvp_infamy, 25.0, 0.0001, "PvP kill grants infamy once")
	t.check(not PvpInfamy.is_outlaw(killer.pvp_infamy),
		"first kill does not yet mark an outlaw")
	var count_before: int = killer.kills
	killer.attack_timer = 0.0
	server.cmd_attack(101, 1.0, 0.0)
	t.eq(killer.kills, count_before, "dead victim cannot be re-killed for reputation")
	t.near(killer.pvp_infamy, 25.0, 0.0001, "corpse hits award no more infamy")
	server._spawn_player(victim)
	victim.position = _at(world, 801.5, 0.0)
	victim.survival.hurt(95.0)
	killer.attack_timer = 0.0
	var second: Dictionary = server.cmd_attack(101, 1.0, 0.0)
	t.check(second.get("ok", false) and second.get("hit", false),
		"another real fatal PvP attack succeeds")
	t.near(killer.pvp_infamy, 50.0, 0.0001, "second kill reaches outlaw threshold")
	t.check(PvpInfamy.is_outlaw(killer.pvp_infamy), "criminal flag is authoritative")
	var killer_view: Dictionary = server.snapshot_for(101)["you"]
	t.near(float(killer_view["pvp_infamy"]), 50.0, 0.0001,
		"owner receives exact reputation from server")
	t.check(killer_view["outlaw"], "owner sees outlaw status")

	t.current = "PvE and protected zones do not grant PvP infamy"
	killer.position = _at(world, 100.0, 0.0)
	neutral.position = _at(world, 101.5, 0.0)
	killer.attack_timer = 0.0
	var protected: Dictionary = server.cmd_attack(101, 1.0, 0.0)
	t.check(protected.get("ok", false) and not protected.get("hit", true),
		"protected green zone ignores PvP attacks")
	t.near(killer.pvp_infamy, 50.0, 0.0001, "safe-zone attacks do not affect infamy")
	var infected = Zombie.new(server.new_id(), "walker", _at(world, 105.0, 0.0))
	server.zombies[infected.id] = infected
	server._damage_target(killer, {"kind": "zombie", "id": infected.id}, 1000.0)
	t.near(killer.pvp_infamy, 50.0, 0.0001,
		"killing infected cannot increase criminal reputation")
	var neutral_view: Dictionary = server.snapshot_for(103)["players"][0]
	t.check(neutral_view.get("outlaw", false), "other survivors can identify an outlaw")
	t.check(not neutral_view.has("pvp_infamy"), "private score is not sent to observers")

	t.current = "safe hub vendor uses server-owned infamy"
	var workbench: Vector3 = _at(world, 9.0, 0.0)
	killer.position = workbench
	neutral.position = workbench
	killer.inventory.add("silver", 100)
	neutral.inventory.add("silver", 100)
	var outlaw_buy: Dictionary = server.cmd_vendor(101, "water_bottle", 1, true)
	var neutral_buy: Dictionary = server.cmd_vendor(103, "water_bottle", 1, true)
	t.check(outlaw_buy.get("ok", false) and neutral_buy.get("ok", false),
		"both buyers receive one real water bottle")
	t.eq(outlaw_buy["unit_price"], 15, "notorious buyer pays the penalty")
	t.eq(neutral_buy["unit_price"], 12, "neutral buyer pays the base price")
	killer.inventory.add("bar_4", 1)
	neutral.inventory.add("bar_4", 1)
	var outlaw_sale: Dictionary = server.cmd_vendor(101, "bar_4", 1, false)
	var neutral_sale: Dictionary = server.cmd_vendor(103, "bar_4", 1, false)
	t.check(outlaw_sale.get("ok", false) and neutral_sale.get("ok", false),
		"sale rewards are transferred on the server")
	t.eq(outlaw_sale["unit_price"], 28, "outlaw receives reduced material payout")
	t.eq(neutral_sale["unit_price"], 32, "neutral receives standard material payout")
	var before_inventory: Dictionary = killer.inventory.to_dict()
	t.eq(Vendor.transact(killer.inventory, "water_bottle", 1, true, NAN)["reason"],
		"invalid_infamy", "corrupt vendor reputation is rejected")
	t.eq(killer.inventory.to_dict(), before_inventory,
		"invalid transaction does not mutate carried items")

	t.current = "survivor renown and outlaw penalties stack safely"
	killer.renown = 500 # Existing Warden rank: 20% vendor buying discount.
	var stacked_buy: Dictionary = server.cmd_vendor(101, "water_bottle", 1, true)
	t.check(stacked_buy.get("ok", false), "existing renown rank can still buy supplies")
	t.eq(stacked_buy["unit_price"], 13,
		"20% renown discount first, then 25% notoriety surcharge")
	var batch_buy: Dictionary = server.cmd_vendor(101, "water_bottle", 2, true)
	t.check(batch_buy.get("ok", false), "stacked discount supports bulk orders")
	t.eq(batch_buy["silver_delta"], -26,
		"splitting the bulk purchase cannot reduce the final cost")

	t.current = "online decay, death, snapshots and persistence"
	killer.dirty_character = false
	server._tick_players(1.0)
	t.near(killer.pvp_infamy, PvpInfamy.decay(50.0, 1.0), 0.0001,
		"live player slowly loses notoriety")
	t.check(killer.dirty_character, "decay triggers account save")
	var stored_score: float = killer.pvp_infamy
	var saved: Dictionary = server.character_data(killer)
	killer.pvp_infamy = 0.0
	t.check(server.apply_character(killer, saved), "infamy survives normal save load")
	t.near(killer.pvp_infamy, stored_score, 0.0001,
		"restored infamy matches the saved score")
	var legacy: Dictionary = saved.duplicate(true)
	legacy.erase("pvp_infamy")
	t.check(server.apply_character(killer, legacy),
		"legacy version-1 character without infamy still loads")
	t.near(killer.pvp_infamy, 0.0, 0.0001, "legacy save starts neutral")
	t.check(server.apply_character(killer, saved), "restore prior reputation")
	for bad in [-1.0, 101.0, NAN, INF, "50", true]:
		var corrupted: Dictionary = saved.duplicate(true)
		corrupted["pvp_infamy"] = bad
		t.check(not server.apply_character(killer, corrupted),
			"malformed infamy cannot restore or modify a live survivor")
		t.near(killer.pvp_infamy, stored_score, 0.0001,
			"failed restore preserves preexisting reputation")
	killer.survival.hurt(1000.0)
	server._on_player_death(killer, -1)
	server._spawn_player(killer)
	t.near(killer.pvp_infamy, stored_score, 0.0001,
		"dying and respawning does not erase criminal reputation")
