extends RefCounted
## Last-escort death emits exactly one local, public-objective clearance alert.

const WorldGen = preload("res://scripts/shared/world_gen.gd")
const GameServer = preload("res://scripts/server/game_server.gd")
const SupplyDrops = preload("res://scripts/shared/supply_drops.gd")
const Zombie = preload("res://scripts/shared/zombie.gd")
const Net = preload("res://scripts/shared/net.gd")


func _site(world) -> Vector3:
	for index in 72:
		var point := Vector2.from_angle(float(index) * TAU / 72.0) * 800.0
		if world.zone_at(point.x, point.y) == 2 and not world.is_water(point.x, point.y):
			return Vector3(point.x, world.height_at(point.x, point.y), point.y)
	return Vector3.INF


func run(t) -> void:
	t.current = "clear event cannot be forged by ordinary or empty bags"
	t.check(not SupplyDrops.mark_cleared({"supply_drop": false,
		"supply_guard_ids": [2]}, {}), "normal loot never broadcasts clearance")
	t.check(not SupplyDrops.mark_cleared({"supply_drop": true,
		"supply_guard_ids": []}, {}), "unguarded crate has no clearance notification")

	var world := WorldGen.new(73)
	var sim := GameServer.new(world, 73)
	var here: Vector3 = _site(world)
	t.check(here.is_finite(), "found a valid red-zone objective site")
	if not here.is_finite():
		return
	var killer = sim.add_player(901, "Supply Hunter")
	killer.position = here
	var witness = sim.add_player(902, "Witness")
	witness.position = here + Vector3(4, 0, 0)
	var far = sim.add_player(903, "Distant Survivor")
	far.position = Vector3(0, world.height_at(0, 0), 0)

	var bag_id: int = sim._make_bag(here, {"silver": 24})
	var bag: Dictionary = sim.bags[bag_id]
	bag["supply_drop"] = true
	var first := Zombie.new(sim.new_id(), "walker", here + Vector3(7, 0, 0), -1)
	var last := Zombie.new(sim.new_id(), "runner", here + Vector3(-8, 0, 0), -1)
	first.supply_cache_id = bag_id
	last.supply_cache_id = bag_id
	sim.zombies[first.id] = first
	sim.zombies[last.id] = last
	bag["supply_guard_ids"] = [first.id, last.id]
	t.eq(SupplyDrops.living_guards(bag, sim.zombies), 2, "both real escorts lock the cache")
	t.eq(sim.cmd_loot(901, bag_id).get("reason"), "guards_alive",
		"looting is forbidden while original escorts survive")
	sim.drain_events()

	t.current = "first kill preserves lock, final kill opens the public crate"
	t.check(first.take_damage(100000), "first guard dies")
	sim._on_zombie_death(first, killer)
	var first_clear_count: int = 0
	for event in sim.drain_events():
		if event.get("type") == "supply_cleared":
			first_clear_count += 1
	t.eq(first_clear_count, 0, "partial clearance does not claim objective")
	t.eq(SupplyDrops.living_guards(bag, sim.zombies), 1, "one living guard still blocks loot")
	t.eq(sim.cmd_loot(901, bag_id).get("reason"), "guards_alive",
		"still locked after first kill")
	t.check(last.take_damage(100000), "last guard dies")
	sim._on_zombie_death(last, killer)
	var cleared: Dictionary = {}
	var clearance_count: int = 0
	for event in sim.drain_events():
		if event.get("type") == "supply_cleared":
			cleared = event
			clearance_count += 1
	t.eq(clearance_count, 1, "exactly one clearance announcement")
	t.eq(int(cleared.get("id", -1)), bag_id, "event references the public cache only")
	t.check(not cleared.has("peer") and not cleared.has("killer"),
		"public message leaks no survivor identity")
	t.check(not cleared.has("supply_guard_ids"), "private guard IDs are not shared")
	t.eq(SupplyDrops.living_guards(bag, sim.zombies), 0, "all escorts defeated")
	t.check(not SupplyDrops.mark_cleared(bag, sim.zombies),
		"clearance latch cannot be replayed")
	t.check(bool(bag["clear_announced"]), "per-cache latch survives until pickup")
	t.check(bool(sim.cmd_loot(901, bag_id).get("ok", false)),
		"looting is permitted once escorts have been defeated")
	t.check(not sim.bags.has(bag_id), "one-time reward is consumed")
	var net := Net.new()
	net.role = "server"
	net.sim = sim
	t.check(net._event_visible_to(cleared, 901), "killer receives clearance")
	t.check(net._event_visible_to(cleared, 902), "nearby rival receives public opening")
	t.check(not net._event_visible_to(cleared, 903),
		"far away players do not receive objective tracking data")
	net.free()

	t.current = "missing and expired caches cannot announce a victory"
	t.check(not SupplyDrops.mark_cleared({"supply_drop": true,
		"supply_guard_ids": []}, sim.zombies), "no escort means no fake victory")
	var gone := Zombie.new(sim.new_id(), "walker", here, -1)
	gone.supply_cache_id = bag_id
	gone.take_damage(100000)
	sim.zombies[gone.id] = gone
	sim._on_zombie_death(gone, killer)
	var spurious: int = 0
	for event in sim.drain_events():
		if event.get("type") == "supply_cleared":
			spurious += 1
	t.eq(spurious, 0, "removed cache cannot emit a later clear event")
