extends RefCounted
## Verified caravan-wave clears pay a bounded one-time NPC risk premium.
## Expiration, fake kills, death and invalid saves must never mint silver.
const CaravanAmbush = preload("res://scripts/shared/caravan_ambush.gd")
const CaravanRoutes = preload("res://scripts/shared/caravan_routes.gd")
const Rewards = preload("res://scripts/shared/caravan_escort_rewards.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const GameServer = preload("res://scripts/server/game_server.gd")
const Inventory = preload("res://scripts/shared/inventory.gd")
const Net = preload("res://scripts/shared/net.gd")
const Zombie = preload("res://scripts/shared/zombie.gd")


func _source(world) -> Dictionary:
	for rx in range(-4, 5):
		for rz in range(-4, 5):
			for site in world.poi.sites_in_region(rx, rz):
				if not CaravanRoutes.offer_for(world, site).is_empty():
					return site
	return {}


func _at(sim, player, x: float, z: float) -> void:
	player.position = Vector3(x, sim.world.height_at(x, z), z)


func run(t) -> void:
	t.current = "caravan defense requires every distinct confirmed kill"
	var wave := {"ids": [11, 12, 13], "defeated": []}
	t.check(not CaravanAmbush.record_kill(wave, 99),
		"stranger zombie death cannot advance contracted ambush")
	t.check(not CaravanAmbush.record_kill(wave, 11),
		"one attacker killed is not a complete defense")
	t.check(not CaravanAmbush.record_kill(wave, 11),
		"duplicate enemy death cannot count again")
	t.check(not CaravanAmbush.record_kill(wave, 12), "two of three are incomplete")
	t.eq(wave["defeated"], [11, 12], "ledger contains only distinct original IDs")
	t.check(CaravanAmbush.record_kill(wave, 13),
		"last actual attacker death completes the defense exactly once")
	t.check(not CaravanAmbush.record_kill(wave, 13),
		"replayed last kill grants no second defense")
	t.eq(CaravanAmbush.defense_bonus(0), 0, "invalid zero fare has no premium")
	t.eq(CaravanAmbush.defense_bonus(49), 0, "forged low fare has no premium")
	t.eq(CaravanAmbush.defense_bonus(140), 21, "highest route has capped 15 percent bonus")
	t.eq(CaravanAmbush.defense_bonus(50), 8, "minimum route has rounded 15 percent bonus")
	t.eq(CaravanAmbush.defense_bonus(141), 0, "out-of-range fare has no bonus")

	t.current = "premium settlement is atomic and never diverts escort shares"
	var world := WorldGen.new(205)
	var site := _source(world)
	t.check(not site.is_empty(), "world generates at least one canonical delivery")
	if site.is_empty():
		return
	var route: Dictionary = CaravanRoutes.offer_for(world, site)
	var sim := GameServer.new(world, 205)
	var courier = sim.add_player(1001, "Defender")
	var escort = sim.add_player(1002, "Escort")
	var cargo_id: String = str(route["cargo"])
	courier.inventory.add(cargo_id, CaravanRoutes.CARGO_COUNT)
	var base: int = int(route["silver"])
	var expected_bonus: int = CaravanAmbush.defense_bonus(base)
	var result: Dictionary = Rewards.settle(courier, [escort], route, true)
	t.check(result.get("ok", false), "verified completed defense may settle")
	t.eq(result.get("gross_silver", 0), base, "escort fare keeps original NPC base")
	t.eq(result.get("defense_bonus", 0), expected_bonus, "receipt shows exact risk premium")
	t.eq(result.get("silver", 0), base - int(result["escorts"][0]["silver"]) + expected_bonus,
		"only courier receives the extra risk premium")
	t.eq(courier.inventory.count("silver") + escort.inventory.count("silver"),
		base + expected_bonus, "silver supply increases only by authorized NPC premium")
	t.eq(courier.inventory.count(cargo_id), 0, "cargo is genuinely consumed")
	var empty_reward = sim.add_player(1003, "Normal delivery")
	empty_reward.inventory.add(cargo_id, CaravanRoutes.CARGO_COUNT)
	t.eq(Rewards.settle(empty_reward, [], route).get("defense_bonus", -1), 0,
		"ordinary delivery remains unchanged with no defense")
	var overflow = sim.add_player(1004, "Full wallet")
	overflow.inventory = Inventory.new(2)
	overflow.inventory.add(cargo_id, CaravanRoutes.CARGO_COUNT)
	overflow.inventory.add("silver", 100000 - base)
	var before: Dictionary = overflow.inventory.to_dict()
	t.eq(Rewards.settle(overflow, [], route, true).get("reason", ""), "no_space",
		"lack of room for defense bonus rejects whole settlement")
	t.eq(overflow.inventory.to_dict(), before,
		"failed bonus credit never consumes cargo or base fare")

	t.current = "real server wave completion, private notices and verified save"
	var owner = sim.add_player(1101, "Courier", "caravan-1101")
	var unrelated = sim.add_player(1102, "Other")
	_at(sim, owner, float(site["station_x"]), float(site["station_z"]))
	t.check(sim.cmd_caravan(owner.id, "accept").get("ok", false),
		"real station assigns canonical delivery")
	owner.inventory.add(cargo_id, CaravanRoutes.CARGO_COUNT)
	var saved_route: Dictionary = owner.caravan_state.duplicate(true)
	var wave_ids := [92001, 92002, 92003]
	owner.caravan_ambushed = true
	sim.caravan_ambushes.append({"ids": wave_ids.duplicate(), "defeated": [],
		"owner": owner.id, "route": saved_route, "deaths": owner.deaths,
		"expires": sim.time + 120.0})
	for i in range(wave_ids.size()):
		# Real authoritative death callback rather than client-submitted progress.
		var zombie = Zombie.new(wave_ids[i], "walker",
			Vector3(owner.position.x + 2.0, owner.position.y, owner.position.z), -1)
		sim.zombies[zombie.id] = zombie
		zombie.take_damage(99999.0, owner.id)
		sim._on_zombie_death(zombie, owner)
		if i < wave_ids.size() - 1:
			t.check(not owner.caravan_defended,
				"partial wave does not unlock the bonus")
	t.check(owner.caravan_defended, "all server-owned deaths unlock defense")
	t.eq(sim.snapshot_for(owner.id)["you"]["caravan_defended"], true,
		"only owner sees private defense progress in snapshot")
	t.eq(sim.snapshot_for(unrelated.id)["you"]["caravan_defended"], false,
		"unrelated survivor cannot inspect another courier's bonus")
	var notices: Array = sim.drain_events().filter(
		func(event): return str(event.get("type", "")) == "caravan_defended")
	t.eq(notices.size(), 1, "completion emits one private notification")
	if notices.size() == 1:
		var net := Net.new()
		net.role = "server"
		net.sim = sim
		t.check(net._event_visible_to(notices[0], owner.id), "courier receives notification")
		t.check(not net._event_visible_to(notices[0], unrelated.id),
			"other players cannot receive courier's defense result")
		net.free()
	var saved: Dictionary = sim.character_data(owner)
	t.eq(saved.get("caravan_defended"), true, "defense eligibility persists for relog")
	var restore = sim.add_player(1103, "Reloaded", "caravan-1101")
	t.check(sim.apply_character(restore, saved), "valid saved defense and route restore")
	t.check(restore.caravan_defended, "relogin cannot erase earned premium")
	var corrupt: Dictionary = saved.duplicate(true)
	corrupt["caravan_defended"] = "yes"
	t.check(not sim.apply_character(restore, corrupt), "string flag rejected")
	t.check(restore.caravan_defended, "invalid save leaves existing state untouched")
	corrupt = saved.duplicate(true)
	corrupt["caravan_ambushed"] = false
	t.check(not sim.apply_character(restore, corrupt),
		"cannot attach clear bonus to a route with no ambush")
	corrupt = saved.duplicate(true)
	corrupt["caravan"] = {}
	t.check(not sim.apply_character(restore, corrupt),
		"cannot attach bonus to inactive cargo route")
	var legacy: Dictionary = saved.duplicate(true)
	legacy.erase("caravan_defended")
	t.check(sim.apply_character(restore, legacy), "legacy save without bonus field loads")
	t.check(not restore.caravan_defended, "legacy route has no unearned risk bonus")

	t.current = "death, abandoned route and disconnected wave remove claims"
	owner.caravan_defended = true
	# Keep the test independent of full-loot rules: exercise the death latch
	# in the safe hub, then return to the real NPC delivery station.
	_at(sim, owner, 0.0, 0.0)
	sim._on_player_death(owner, -1)
	t.check(not owner.caravan_defended, "courier death forfeits unpaid defense reward")
	_at(sim, owner, float(route["dst_x"]), float(route["dst_z"]))
	var delivered: Dictionary = sim.cmd_caravan(owner.id, "deliver")
	t.check(delivered.get("ok", false), "real cargo can still be delivered after death")
	t.eq(delivered.get("defense_bonus", -1), 0,
		"death blocks premium without cancelling ordinary fare")
	t.eq(sim.cmd_caravan(owner.id, "deliver").get("reason", ""), "no_active",
		"repeated delivery cannot award another premium")
	_at(sim, owner, float(site["station_x"]), float(site["station_z"]))
	t.check(sim.cmd_caravan(owner.id, "accept").get("ok", false), "new route accepted")
	owner.caravan_ambushed = true
	owner.caravan_defended = true
	sim.caravan_ambushes.append({"ids": [95001, 95002], "defeated": [],
		"owner": owner.id, "route": owner.caravan_state.duplicate(true),
		"deaths": owner.deaths, "expires": sim.time + 20.0})
	t.check(sim.cmd_caravan(owner.id, "abandon").get("ok", false),
		"abandoning route explicitly forfeits reward")
	t.check(not owner.caravan_defended, "abandoned route loses bonus latch")
	t.check(sim.caravan_ambushes.is_empty(), "abandon removes orphaned waves")
