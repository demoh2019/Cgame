extends RefCounted
## Real paid one-hit fortification: ownership, finite-time, no charge stacking,
## proper explosion mitigation and original vulnerable PvP wall rules.
const GameServer = preload("res://scripts/server/game_server.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const Structures = preload("res://scripts/shared/structures.gd")
const Brace = preload("res://scripts/shared/siege_blast_brace.gd")
const Charge = preload("res://scripts/shared/siege_charge.gd")
const Crafting = preload("res://scripts/shared/crafting.gd")
const Inventory = preload("res://scripts/shared/inventory.gd")
const Defs = preload("res://scripts/shared/defs.gd")
const Net = preload("res://scripts/shared/net.gd")


func _at(world, point: Vector2) -> Vector3:
	return Vector3(point.x, world.height_at(point.x, point.y), point.y)


func _site(world) -> Vector2:
	for x in range(660, 1050, 16):
		for z in range(-200, 201, 16):
			var pos := Vector2(float(x), float(z))
			if world.zone_at(pos.x, pos.y) != 2 or world.is_water(pos.x, pos.y):
				continue
			if world.normal_at(pos.x, pos.y).y < Structures.MIN_SLOPE_NORMAL_Y:
				continue
			var clear := true
			for obstacle in world.blockers_near(pos.x, pos.y, 5.0):
				if pos.distance_to(Vector2(float(obstacle["x"]), float(obstacle["z"]))) < \
						float(obstacle["radius"]) + 3.6:
					clear = false
					break
			if clear:
				return pos
	return Vector2.INF


func run(t) -> void:
	t.current = "craft finite tier-two siege reinforcement"
	var recipe: Dictionary = Defs.recipes().get(Brace.ITEM_ID, {})
	t.eq(Defs.item(Brace.ITEM_ID).get("kind", ""), "siege_brace",
		"physical counter-siege item is registered")
	t.eq(recipe.get("station", ""), "workbench",
		"crafting requires workstation")
	t.eq(recipe.get("inputs", {}), {"bar_2": 2, "plank_2": 3,
		"scrap": 5, "cloth_2": 1}, "cost pays for protection")
	var stock := Inventory.new()
	for item in recipe.get("inputs", {}):
		stock.add(str(item), int(recipe["inputs"][item]))
	t.eq(Crafting.craft(stock, Brace.ITEM_ID, false),
		Crafting.Result.NO_STATION, "field crafting denied")
	t.eq(Crafting.craft(stock, Brace.ITEM_ID, true),
		Crafting.Result.OK, "craft consumes inventory")
	t.eq(stock.count(Brace.ITEM_ID), 1, "one kit created")

	t.current = "owner-only server placement; one brace per wall"
	var world := WorldGen.new(319)
	var server := GameServer.new(world, 319)
	var site: Vector2 = _site(world)
	t.check(site.is_finite(), "safe physical PvP building position exists")
	if not site.is_finite():
		return
	var owner = server.add_player(401, "Owner", "auth-401")
	var attacker = server.add_player(402, "Attacker", "auth-402")
	var stranger = server.add_player(403, "Stranger", "auth-403")
	var distant = server.add_player(404, "Distant")
	owner.position = _at(world, site + Vector2(-2.8, 0))
	attacker.position = _at(world, site + Vector2(2.8, 0))
	stranger.position = _at(world, site + Vector2(-2.8, 0))
	distant.position = _at(world, site + Vector2(300, 0))
	owner.inventory.add("wood_1", 12)
	owner.inventory.add("stone_1", 6)
	var built: Dictionary = server.cmd_build(owner.id, site.x, site.y)
	t.check(bool(built.get("ok", false)), "server constructed real T1 wall")
	if not bool(built.get("ok", false)):
		return
	var wall_id: int = int(built["id"])
	owner.inventory.add(Brace.ITEM_ID, 2)
	stranger.inventory.add(Brace.ITEM_ID, 1)
	attacker.inventory.add(Charge.ITEM_ID, 1)
	t.eq(server.cmd_use(stranger.id, Brace.ITEM_ID).get("reason", ""),
		"not_owner", "unauthorized raider cannot reinforce wall")
	t.eq(stranger.inventory.count(Brace.ITEM_ID), 1, "rejected kit not spent")
	owner.position = _at(world, site + Vector2(-30, 0))
	t.eq(server.cmd_use(owner.id, Brace.ITEM_ID).get("reason", ""),
		"no_barricade", "cannot place a brace from anywhere")
	owner.position = _at(world, site + Vector2(-2.8, 0))
	t.check(server.cmd_use(owner.id, Brace.ITEM_ID).get("ok", false),
		"owner has applied one real prepared brace")
	t.eq(owner.inventory.count(Brace.ITEM_ID), 1, "exactly one kit consumed")
	t.eq(server.cmd_use(owner.id, Brace.ITEM_ID).get("reason", ""),
		"already_braced", "unlimited reinforcement stacking blocked")
	t.near(float(server.snapshot_for(owner.id)["barricades"][0].get(
		"blast_brace_seconds", 0.0)), Brace.DURATION, 0.01,
		"players can see nearby brace lifetime")

	t.current = "real siege blast consumes one brace, not ordinary wall damage"
	t.check(not server.damage_barricade(wall_id, 10.0),
		"normal damage reduces wall health")
	t.check(Brace.active(server.siege_braces, wall_id, server.time),
		"zombie and ranged damage do not spend bracing")
	var arming: Dictionary = server.cmd_use(attacker.id, Charge.ITEM_ID)
	t.check(bool(arming.get("ok", false)), "actual enemy explosive armed")
	if not bool(arming.get("ok", false)):
		return
	server.time = float(server.siege_charges[int(arming["id"])]["until"])
	server._tick_siege_charges()
	t.check(server.barricades.has(wall_id),
		"single braced T1 wall survives 160 raw damage")
	if not server.barricades.has(wall_id):
		return
	t.near(float(server.barricades[wall_id]["hp"]), 38.0, 0.01,
		"raw shield blocks 88 and remaining blast damages real HP")
	t.check(not Brace.active(server.siege_braces, wall_id, server.time),
		"shield is spent before any second detonation")
	var events: Array = server.events.filter(
		func(e): return str(e.get("type", "")) == "siege_brace_absorbed")
	t.eq(events.size(), 1, "only one absorbed-blast event")
	if not events.is_empty():
		t.near(float(events[0]["raw_absorbed"]), 88.0, 0.01,
			"exactly 55 percent of T3 charge mitigated")
		var network := Net.new()
		network.role = "server"
		network.sim = server
		t.check(network._event_visible_to(events[0], owner.id),
			"local defender gets warning")
		t.check(not network._event_visible_to(events[0], distant.id),
			"remote outsiders cannot track structures")
		network.free()

	t.current = "expiration, dismantle and destruction remove temporary brace"
	t.check(server.cmd_use(owner.id, Brace.ITEM_ID).get("ok", false),
		"a still-living wall may be reinforced for another encounter")
	t.eq(owner.inventory.count(Brace.ITEM_ID), 0, "second real kit consumed")
	server.time += Brace.DURATION
	Brace.sweep(server.siege_braces, server.barricades, server.time)
	t.check(server.siege_braces.is_empty(),
		"brace expires at exact server deadline")
	t.check(server.damage_barricade(wall_id, 160.0),
		"unprotected damaged T1 wall dies normally")
	t.check(server.siege_braces.is_empty(),
		"destroyed wall leaves no reusable shield")
