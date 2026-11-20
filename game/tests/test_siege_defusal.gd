extends RefCounted
## Physical siege charge counterplay: real item cost, nearest active fuse,
## owner authorization, obstacles, deadline and one-shot event filtering.
const Defs = preload("res://scripts/shared/defs.gd")
const Crafting = preload("res://scripts/shared/crafting.gd")
const Inventory = preload("res://scripts/shared/inventory.gd")
const SiegeCharge = preload("res://scripts/shared/siege_charge.gd")
const SiegeDefusal = preload("res://scripts/shared/siege_defusal.gd")
const Structures = preload("res://scripts/shared/structures.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const GameServer = preload("res://scripts/server/game_server.gd")
const Net = preload("res://scripts/shared/net.gd")


func _position(world, point: Vector2) -> Vector3:
	return Vector3(point.x, world.height_at(point.x, point.y), point.y)


func _build_site(world) -> Vector2:
	for x in range(660, 1050, 16):
		for z in range(-200, 201, 16):
			var point := Vector2(float(x), float(z))
			if world.zone_at(point.x, point.y) != 2 or world.is_water(point.x, point.y):
				continue
			if world.normal_at(point.x, point.y).y < Structures.MIN_SLOPE_NORMAL_Y:
				continue
			var clear := true
			for obstacle in world.blockers_near(point.x, point.y, 5.0):
				if point.distance_to(Vector2(float(obstacle["x"]), float(obstacle["z"]))) < \
						float(obstacle["radius"]) + 3.6:
					clear = false
					break
			if clear:
				return point
	return Vector2.INF


func run(t) -> void:
	t.current = "crafted counter-siege tool has real workbench materials"
	t.eq(Defs.item(SiegeDefusal.ITEM_ID).get("kind", ""), "siege_defusal",
		"only distinct T2 item can disarm charges")
	var recipe: Dictionary = Defs.recipes().get(SiegeDefusal.ITEM_ID, {})
	t.eq(recipe.get("station", ""), "workbench", "workbench required")
	t.eq(recipe.get("inputs", {}), {"bar_2": 1, "scrap": 4, "cloth_2": 1,
		"fiber_2": 1}, "finite material bill")
	var bag := Inventory.new()
	for item in recipe.get("inputs", {}):
		bag.add(str(item), int(recipe["inputs"][item]))
	t.eq(Crafting.craft(bag, SiegeDefusal.ITEM_ID, false),
		Crafting.Result.NO_STATION, "can't craft remotely")
	t.eq(Crafting.craft(bag, SiegeDefusal.ITEM_ID, true),
		Crafting.Result.OK, "defender builds a real toolkit")
	t.eq(bag.count(SiegeDefusal.ITEM_ID), 1, "one paid kit exists")

	t.current = "server chooses only real reachable live charge"
	var world := WorldGen.new(319)
	var server := GameServer.new(world, 319)
	var site: Vector2 = _build_site(world)
	t.check(site.is_finite(), "real safe placement site for red-zone barricade")
	if not site.is_finite():
		return
	var owner = server.add_player(401, "Defender", "owner-account")
	var attacker = server.add_player(402, "Attacker", "raider-account")
	var other = server.add_player(403, "Intruder", "intruder-account")
	var distant = server.add_player(404, "Far Away")
	owner.position = _position(world, site + Vector2(-2.8, 0))
	attacker.position = _position(world, site + Vector2(2.8, 0))
	other.position = _position(world, site + Vector2(-2.8, 0))
	distant.position = _position(world, site + Vector2(300, 0))
	owner.inventory.add("wood_1", 12)
	owner.inventory.add("stone_1", 6)
	var build: Dictionary = server.cmd_build(owner.id, site.x, site.y)
	t.check(bool(build.get("ok", false)), "real owner pays to build a wall")
	if not bool(build.get("ok", false)):
		return
	var wall_id: int = int(build["id"])
	attacker.inventory.add(SiegeCharge.ITEM_ID, 2)
	var armed: Dictionary = server.cmd_use(attacker.id, SiegeCharge.ITEM_ID)
	t.check(bool(armed.get("ok", false)), "hostile charge really planted")
	if not bool(armed.get("ok", false)):
		return
	var charge_id: int = int(armed["id"])
	t.eq(server.cmd_use(owner.id, SiegeDefusal.ITEM_ID).get("reason", ""),
		"not_carried", "no free defusing without crafted item")
	owner.inventory.add(SiegeDefusal.ITEM_ID, 2)
	attacker.inventory.add(SiegeDefusal.ITEM_ID, 1)
	other.inventory.add(SiegeDefusal.ITEM_ID, 1)
	t.eq(server.cmd_use(other.id, SiegeDefusal.ITEM_ID).get("reason", ""),
		"not_owner", "nearby outsider denied")
	t.eq(server.cmd_use(attacker.id, SiegeDefusal.ITEM_ID).get("reason", ""),
		"not_owner", "attackers cannot disarm defender walls")
	t.eq(other.inventory.count(SiegeDefusal.ITEM_ID), 1,
		"denied attempt never spends toolkit")
	owner.position = _position(world, site + Vector2(-26, 0))
	t.eq(server.cmd_use(owner.id, SiegeDefusal.ITEM_ID).get("reason", ""),
		"no_armed_charge", "remote defuse cannot reach")
	owner.position = _position(world, site + Vector2(-2.8, 0))
	var blocker_id: int = 991111
	world.add_dynamic_blocker(blocker_id, site.x - 1.5, site.y, 0.35)
	t.eq(server.cmd_use(owner.id, SiegeDefusal.ITEM_ID).get("reason", ""),
		"blocked", "solid cover prevents remote interaction")
	t.eq(owner.inventory.count(SiegeDefusal.ITEM_ID), 2,
		"blocked attempt doesn't spend materials")
	world.remove_dynamic_blocker(blocker_id)
	var old_health: float = float(server.barricades[wall_id]["hp"])
	server.time = SiegeCharge.FUSE_SECONDS - 0.1
	var resolved: Dictionary = server.cmd_use(owner.id, SiegeDefusal.ITEM_ID)
	t.check(bool(resolved.get("ok", false)), "wall owner defuses live bomb")
	t.eq(resolved.get("id", 0), charge_id, "server picked the actual live charge")
	t.eq(owner.inventory.count(SiegeDefusal.ITEM_ID), 1, "exactly one kit spent")
	t.check(server.siege_charges.is_empty(), "defused charge erased before blast")
	t.eq(server.cmd_use(owner.id, SiegeDefusal.ITEM_ID).get("reason", ""),
		"no_armed_charge", "replayed disarm fails without spending items")
	server.time += 5.0
	server._tick_siege_charges()
	t.eq(float(server.barricades[wall_id]["hp"]), old_health,
		"removed charge can never damage wall later")
	t.eq(server.decoys.size(), 0, "no zombie-attracting fake explosion")
	var events: Array = server.events.filter(
		func(event): return str(event.get("type", "")) == "siege_charge_disarmed")
	t.eq(events.size(), 1, "exactly one removal event")
	if events.size() == 1:
		var network := Net.new()
		network.role = "server"
		network.sim = server
		t.check(network._event_visible_to(events[0], owner.id), "defender witnesses disarm")
		t.check(network._event_visible_to(events[0], attacker.id), "raider sees disarm")
		t.check(not network._event_visible_to(events[0], distant.id),
			"no distant base tracking leaked")
		network.free()

	t.current = "server fuse wins when disarm arrives too late"
	var next: Dictionary = server.cmd_use(attacker.id, SiegeCharge.ITEM_ID)
	t.check(bool(next.get("ok", false)), "another enemy device armed")
	if not bool(next.get("ok", false)):
		return
	var next_id: int = int(next["id"])
	server.time = float(server.siege_charges[next_id]["until"])
	t.eq(server.cmd_use(owner.id, SiegeDefusal.ITEM_ID).get("reason", ""),
		"fuse_expired", "can't use tool at exact detonation deadline")
	t.eq(owner.inventory.count(SiegeDefusal.ITEM_ID), 1,
		"missed window is not charged")
	server._tick_siege_charges()
	t.check(not server.barricades.has(wall_id),
		"normal enemy blast proceeds after missed defuse")
