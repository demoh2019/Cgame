extends RefCounted
## Completing a real caravan shares existing silver only with live co-travel
## guards: ordered checkpoints, genuine movement, proximity, atomic wallets.
const Rewards = preload("res://scripts/shared/caravan_escort_rewards.gd")
const GameServer = preload("res://scripts/server/game_server.gd")
const CaravanRoutes = preload("res://scripts/shared/caravan_routes.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const Net = preload("res://scripts/shared/net.gd")
const Inventory = preload("res://scripts/shared/inventory.gd")


func _source(world) -> Dictionary:
	for rx in range(-4, 5):
		for rz in range(-4, 5):
			for site in world.poi.sites_in_region(rx, rz):
				if not CaravanRoutes.offer_for(world, site).is_empty():
					return site
	return {}


func _travel(ledger: Dictionary, owner: int, escort: int, group: int,
		offer: Dictionary) -> void:
	var start := Vector2(float(offer["src_x"]), float(offer["src_z"]))
	var goal := Vector2(float(offer["dst_x"]), float(offer["dst_z"]))
	var movement: Vector2 = (goal - start) / 300.0
	for step in range(1, 284):
		var pos: Vector2 = start + movement * float(step)
		var actor := Vector3(pos.x, 0, pos.y)
		Rewards.record(ledger, owner, escort, group, offer, actor, actor,
			movement.length())


func run(t) -> void:
	t.current = "guards earn credit only from genuine convoy milestones"
	var world := WorldGen.new(205)
	var site: Dictionary = _source(world)
	t.check(not site.is_empty(), "deterministic NPC settlement route exists")
	if site.is_empty():
		return
	var offer: Dictionary = CaravanRoutes.offer_for(world, site)
	var ledger: Dictionary = {}
	var start := Vector3(float(offer["src_x"]), 0, float(offer["src_z"]))
	var finish := Vector3(float(offer["dst_x"]), 0, float(offer["dst_z"]))
	Rewards.record(ledger, 101, 102, 1, offer, start, start, 0.0)
	t.eq(ledger, {}, "stationary player gains no departure credit")
	Rewards.record(ledger, 101, 102, 1, offer, finish, finish, 1.0)
	t.eq(ledger, {}, "late joiner cannot skip the departure checkpoint")
	Rewards.record(ledger, 101, 102, 1, offer, start, start + Vector3(50, 0, 0), 1.0)
	t.eq(ledger, {}, "distant escorts never start group journey")
	_travel(ledger, 101, 102, 1, offer)
	t.eq(int(Rewards.status(ledger, 101, 102, 1, offer).get("stage", 0)), 4,
		"four actual, ordered source-to-destination waypoints reached")
	t.check(float(Rewards.status(ledger, 101, 102, 1, offer).get("meters", 0.0)) >=
		Rewards.MIN_ESCORT_METERS, "the guard traveled at least 80 shared metres")
	t.check(Rewards.qualifies(ledger, 101, 102, 1, offer, finish, finish),
		"escort present at destination is eligible")
	t.check(not Rewards.qualifies(ledger, 101, 102, 2, offer, finish, finish),
		"reformed group ID cannot reuse previous escort effort")
	t.check(not Rewards.qualifies(ledger, 101, 102, 1, offer, finish,
		finish + Vector3(Rewards.FOLLOW_RADIUS + 5.0, 0, 0)),
		"absent escort cannot claim remote reward")
	var another: Dictionary = offer.duplicate()
	another["dst_id"] = int(offer["dst_id"]) + 1
	t.check(not Rewards.qualifies(ledger, 101, 102, 1, another, finish, finish),
		"old route progress cannot be recycled into a different mission")

	t.current = "real game delivery conserves original silver and rewards co-travel"
	var sim := GameServer.new(world, 205)
	var courier = sim.add_player(101, "Courier")
	var guard = sim.add_player(102, "Guard")
	var bystander = sim.add_player(103, "Bystander")
	courier.position = start
	guard.position = start + Vector3(1, 0, 0)
	bystander.position = start + Vector3(2, 0, 0)
	t.check(sim.cmd_party_invite(101, 102).get("ok", false), "real invite sent")
	t.check(sim.cmd_party_accept(102).get("ok", false), "real party formed")
	var group: int = sim.parties.group_of(101)
	t.check(sim.cmd_caravan(101, "accept").get("ok", false),
		"generated NPC station accepts original courier")
	courier.inventory.add(str(offer["cargo"]), CaravanRoutes.CARGO_COUNT)
	_travel(sim.caravan_escort_progress, 101, 102, group, offer)
	var progress: Dictionary = sim.snapshot_for(102)["you"]["party"]["escort_progress"]
	t.eq(int(progress.get("stage", 0)), 4, "private snapshot shows completed milestones")
	t.eq(sim.snapshot_for(103)["you"]["party"].get("escort_progress", {}), {},
		"unrelated player receives no guard contribution")
	courier.position = finish
	guard.position = finish + Vector3(2, 0, 0)
	var before_owner: int = courier.inventory.count("silver")
	var before_guard: int = guard.inventory.count("silver")
	var result: Dictionary = sim.cmd_caravan(101, "deliver")
	t.check(bool(result.get("ok", false)), "real delivery settles with authenticated guard")
	var gross: int = int(offer["silver"])
	var guard_cut: int = floori(float(gross) * Rewards.MAX_ESCORT_SHARE)
	t.eq(result.get("silver", -1), gross - guard_cut,
		"courier receives at least 80% of their original fare")
	t.eq(courier.inventory.count("silver") - before_owner, gross - guard_cut,
		"courier payout is funded solely from the original vendor fare")
	t.eq(guard.inventory.count("silver") - before_guard, guard_cut,
		"qualified guard is paid exact withheld share")
	t.eq(courier.inventory.count("silver") - before_owner +
		guard.inventory.count("silver") - before_guard, gross,
		"trade cannot mint a second fare")
	t.eq(bystander.inventory.count("silver"), 0,
		"nearby ungrouped bystander earns nothing")
	t.check(guard.dirty_inventory, "escort payout schedules a persistent save")
	t.check(courier.caravan_state.is_empty(), "completed mission clears the route")
	t.eq(sim.cmd_caravan(101, "deliver").get("reason", ""), "no_active",
		"repeat transaction cannot pay an escort twice")
	var payments: Array = sim.drain_events().filter(
		func(e): return str(e.get("type", "")) == "caravan_escort_paid")
	t.eq(payments.size(), 1, "only one guard receives a private receipt")
	var net := Net.new()
	net.role = "server"
	net.sim = sim
	t.check(net._event_visible_to(payments[0], 102), "guard receives their payout")
	t.check(not net._event_visible_to(payments[0], 103),
		"stranger cannot view confidential payment")
	net.free()

	t.current = "full inventories and invalid party members cannot mint rewards"
	var cramped := Inventory.new(1)
	cramped.add("wood_1", 1)
	var guard_before: Dictionary = guard.inventory.to_dict()
	guard.inventory = cramped
	courier.inventory.add(str(offer["cargo"]), CaravanRoutes.CARGO_COUNT)
	var before: Dictionary = courier.inventory.to_dict()
	t.eq(Rewards.settle(courier, [guard], offer).get("reason", ""),
		"escort_no_space", "payout requires room in a qualifying escort's backpack")
	t.eq(courier.inventory.to_dict(), before, "refused transfer never consumes cargo")
	t.eq(guard.inventory.to_dict(), cramped.to_dict(), "refused transfer never moves guard goods")
	guard.inventory.load_dict(guard_before)
	var fake: Dictionary = ledger.duplicate(true)
	Rewards.clear_peer(fake, 102)
	t.eq(Rewards.status(fake, 101, 102, 1, offer), {},
		"leaving or disconnecting removes accrued journey record")
