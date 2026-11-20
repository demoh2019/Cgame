extends RefCounted
## No free instant teleport, no extraction from full-loot regions.

const HubRecall = preload("res://scripts/shared/hub_recall.gd")
const Defs = preload("res://scripts/shared/defs.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const GameServer = preload("res://scripts/server/game_server.gd")
const Zombie = preload("res://scripts/shared/zombie.gd")
const Net = preload("res://scripts/shared/net.gd")


func _dry(world, radius: float) -> Vector3:
	for index in 96:
		var p := Vector2.from_angle(TAU * float(index) / 96.0) * radius
		if not world.is_water(p.x, p.y) and world.normal_at(p.x, p.y).y > 0.8:
			return Vector3(p.x, world.height_at(p.x, p.y), p.y)
	return Vector3.INF


func run(t) -> void:
	t.current = "real T2 item and deterministic safe landing"
	t.eq(Defs.tier_of(HubRecall.ITEM_ID), 2, "return requires T2 materials")
	t.eq(Defs.recipes()[HubRecall.ITEM_ID]["station"], "workbench",
		"return charms use the existing workbench economy")
	var world := WorldGen.new(411)
	var home: Vector3 = HubRecall.destination(world)
	t.check(home.is_finite() and world.is_safe(home.x, home.z),
		"server destination is walkable and in the safe hub")
	var sim := GameServer.new(world, 411)
	var player = sim.add_player(601, "Expeditioner")
	var outer: Vector3 = _dry(world, 180.0)
	t.check(outer.is_finite(), "walkable green/yellow expedition location exists")
	if not outer.is_finite() or not home.is_finite():
		return
	player.position = outer
	t.eq(sim.cmd_use(601, HubRecall.ITEM_ID).get("reason"), "not_carried",
		"unowned charm cannot be used")
	player.inventory.add(HubRecall.ITEM_ID, 2)
	player.inventory.add("bandage", 1)
	t.current = "combat, full-loot and nearby enemies reject cast"
	player.action = {"node": 1}
	t.eq(sim.cmd_use(601, HubRecall.ITEM_ID).get("reason"), "in_combat",
		"cannot overlap gathering or fishing")
	player.action = {}
	var enemy := Zombie.new(sim.new_id(), "walker", outer + Vector3(8, 0, 0))
	sim.zombies[enemy.id] = enemy
	t.eq(sim.cmd_use(601, HubRecall.ITEM_ID).get("reason"), "infected_nearby",
		"cannot teleport out of a nearby infected encounter")
	sim.zombies.erase(enemy.id)
	var red: Vector3 = _dry(world, 800.0)
	t.check(red.is_finite(), "red-zone test site exists")
	if not red.is_finite():
		return
	player.position = red
	t.eq(sim.cmd_use(601, HubRecall.ITEM_ID).get("reason"), "full_loot_zone",
		"no red-zone full-loot escape")
	player.position = outer
	player.combat_tag_until = sim.time + 10.0
	t.eq(sim.cmd_use(601, HubRecall.ITEM_ID).get("reason"), "in_combat",
		"combat tagged player cannot cast")
	player.combat_tag_until = 0.0

	t.current = "successful eight-second paid return"
	var started: Dictionary = sim.cmd_use(601, HubRecall.ITEM_ID)
	t.check(bool(started.get("ok", false)), "valid survivor starts cast")
	t.eq(player.inventory.count(HubRecall.ITEM_ID), 2, "start costs no items")
	t.eq(sim.cmd_use(601, HubRecall.ITEM_ID).get("reason"), "recall_channeling",
		"cannot overlap returns")
	t.eq(sim.cmd_use(601, "bandage").get("reason"), "recall_channeling",
		"no instant healing while channeling")
	t.eq(sim.cmd_craft(601, "shore_bait").get("reason"), "recall_channeling",
		"crafting blocked during return")
	t.eq(float(sim.snapshot_for(601)["you"]["recall_seconds"]), HubRecall.CHANNEL_SECONDS,
		"snapshot exposes only the remaining duration")
	t.check(not sim.snapshot_for(601)["you"].has("recall"),
		"server-only origin is private")
	sim.time += HubRecall.CHANNEL_SECONDS - 0.1
	sim._tick_recalls()
	t.eq(player.position, outer, "time cannot be skipped by premature tick")
	sim.time += 0.11
	sim._tick_recalls()
	t.check(world.is_safe(player.position.x, player.position.z), "player returned to safe hub")
	t.eq(player.inventory.count(HubRecall.ITEM_ID), 1, "exactly one item spent on arrival")
	t.check(player.recall.is_empty(), "channel cleared")
	sim._tick_recalls()
	t.eq(player.inventory.count(HubRecall.ITEM_ID), 1, "extra tick cannot duplicate completion")
	var complete: int = 0
	for event in sim.drain_events():
		if event.get("type") == "recall_completed":
			complete += 1
	t.eq(complete, 1, "one success event")
	var net := Net.new()
	net.role = "server"
	net.sim = sim
	t.check(net._event_visible_to({"type": "recall_completed", "peer": 601}, 601),
		"only owner receives recall confirmation")
	t.check(not net._event_visible_to({"type": "recall_completed", "peer": 601}, 602),
		"other players cannot track the return event")
	net.free()

	t.current = "movement, damage and last-frame combat cancel without charge"
	player.position = outer
	t.eq(sim.cmd_use(601, HubRecall.ITEM_ID).get("reason"), "cooldown",
		"immediate repeat blocked by server cooldown")
	sim.time = player.recall_ready_at + 0.1
	t.check(bool(sim.cmd_use(601, HubRecall.ITEM_ID).get("ok", false)),
		"second charm available after cooldown")
	player.position += Vector3(1, 0, 0)
	sim._tick_recalls()
	t.check(player.recall.is_empty(), "walking beyond tolerance interrupts")
	t.eq(player.inventory.count(HubRecall.ITEM_ID), 1, "movement preserves item")
	player.position = outer
	t.check(bool(sim.cmd_use(601, HubRecall.ITEM_ID).get("ok", false)),
		"cancelled channel can restart")
	sim._hurt_player(player, 2.0)
	t.check(player.recall.is_empty(), "real injury interrupts immediately")
	t.eq(player.inventory.count(HubRecall.ITEM_ID), 1, "injury preserves item")
	t.check(bool(sim.cmd_use(601, HubRecall.ITEM_ID).get("ok", false)),
		"wounded survivor can attempt a fresh cast")
	player.combat_tag_until = sim.time + 30.0
	sim.time += HubRecall.CHANNEL_SECONDS
	sim._tick_recalls()
	t.check(player.recall.is_empty() and player.position.distance_to(outer) < 0.01,
		"new combat tag rejects completion")
	t.eq(player.inventory.count(HubRecall.ITEM_ID), 1,
		"cancelled combat escape costs no consumable")
