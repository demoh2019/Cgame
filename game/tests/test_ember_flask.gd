extends RefCounted
## Real inventory transactions and bounded server-owned environmental damage.
const EmberFlask = preload("res://scripts/shared/ember_flask.gd")
const Defs = preload("res://scripts/shared/defs.gd")
const Inventory = preload("res://scripts/shared/inventory.gd")
const Crafting = preload("res://scripts/shared/crafting.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const GameServer = preload("res://scripts/server/game_server.gd")
const Zombie = preload("res://scripts/shared/zombie.gd")
const Net = preload("res://scripts/shared/net.gd")


class CoverWorld:
	extends RefCounted
	var wall: bool = false

	func is_safe(_x: float, _z: float) -> bool:
		return false

	func height_at(_x: float, _z: float) -> float:
		return 0.0

	func blockers_near(_x: float, _z: float, _radius: float) -> Array:
		return [{"x": 1.0, "z": 0.0, "radius": 0.3}] if wall else []


func _open_origin(world) -> Vector3:
	for x in range(140, 300, 16):
		for z in range(140, 300, 16):
			var start := Vector3(float(x),
				world.height_at(float(x), float(z)), float(z))
			if not EmberFlask.landing(world, start, Vector2.RIGHT).is_empty():
				return start
	return Vector3.INF


func _at(world, point: Vector2) -> Vector3:
	return Vector3(point.x, world.height_at(point.x, point.y), point.y)


func run(t) -> void:
	t.current = "workbench crafting and server geometry"
	t.check(Defs.is_item(EmberFlask.ITEM_ID), "flask is registered")
	t.eq(Defs.recipes()[EmberFlask.ITEM_ID]["station"], "workbench",
		"thermal flasks need real workbench")
	t.eq(Defs.recipes()[EmberFlask.ITEM_ID]["inputs"],
		{"bar_2": 1, "cloth_1": 2, "wood_1": 3, "scrap": 1},
		"recipe spends actual metal and scavenged materials")
	var bag := Inventory.new()
	for id in ["bar_2", "scrap"]:
		bag.add(id, 1)
	bag.add("cloth_1", 2)
	bag.add("wood_1", 3)
	t.eq(Crafting.craft(bag, EmberFlask.ITEM_ID, false),
		Crafting.Result.NO_STATION, "no field forging")
	t.eq(bag.count("scrap"), 1, "failed craft keeps materials")
	t.eq(Crafting.craft(bag, EmberFlask.ITEM_ID, true),
		Crafting.Result.OK, "workbench creates real flask")
	t.eq(bag.count(EmberFlask.ITEM_ID), 1, "exactly one flask gained")
	t.eq(Crafting.craft(bag, EmberFlask.ITEM_ID, true),
		Crafting.Result.MISSING_INPUTS, "cannot duplicate flasks")
	var geom := CoverWorld.new()
	t.check(EmberFlask.affects(geom, Vector2.ZERO, Vector3(2, 0, 0)),
		"inside radius is eligible")
	geom.wall = true
	t.check(not EmberFlask.affects(geom, Vector2.ZERO, Vector3(2, 0, 0)),
		"solid cover blocks area damage")
	geom.wall = false
	t.check(not EmberFlask.affects(geom, Vector2.ZERO, Vector3(3.1, 0, 0)),
		"outside radius cannot burn")
	t.check(not EmberFlask.affects(geom, Vector2.ZERO, Vector3(0, 3, 0)),
		"height checks block other floors")
	t.check(not EmberFlask.affects(geom, Vector2.ZERO, Vector3(NAN, 0, 0)),
		"invalid positions fail closed")
	t.eq(EmberFlask.make_pool(1, {"x": NAN, "y": 0, "z": 2}, 11, 0.0),
		{}, "malformed pool geometry is invalid")

	t.current = "server validates throw and consumes one real item"
	var world := WorldGen.new(721)
	var sim := GameServer.new(world, 721)
	var origin: Vector3 = _open_origin(world)
	t.check(origin.is_finite(), "world has a safe throwing corridor")
	if not origin.is_finite():
		return
	var player = sim.add_player(811, "Ember Ranger")
	player.position = origin
	var landing: Dictionary = EmberFlask.landing(world, origin, Vector2.RIGHT)
	t.eq(sim.cmd_throw_ember(999, 1.0, 0.0).get("reason", ""), "dead",
		"unknown sender cannot create a field")
	t.eq(sim.cmd_throw_ember(811, NAN, 0.0).get("reason", ""),
		"invalid_landing", "nonfinite aim rejected")
	t.eq(sim.cmd_throw_ember(811, 1.0, 0.0).get("reason", ""),
		"not_carried", "server never mints free flasks")
	t.eq(EmberFlask.landing(world, Vector3.ZERO, Vector2.RIGHT), {},
		"safe hub cannot throw burning hazards")
	player.inventory.add(EmberFlask.ITEM_ID, 3)
	var result: Dictionary = sim.cmd_throw_ember(811, 1.0, 0.0)
	t.check(result.get("ok", false), "valid paid throw creates field")
	t.eq(sim.ember_pools.size(), 1, "one active field exists")
	t.eq(player.inventory.count(EmberFlask.ITEM_ID), 2,
		"throw pays exactly one flask")
	t.near(player.flash_cooldown, EmberFlask.COOLDOWN_SECONDS, 0.001,
		"persistent cooldown shared with flash charges")
	t.near(player.noise_radius, EmberFlask.NOISE_RADIUS, 0.001,
		"throw attracts infected within fixed noise distance")
	t.eq(sim.cmd_throw_ember(811, 1.0, 0.0).get("reason", ""),
		"cooldown", "immediate replay does not duplicate fields")
	t.eq(player.inventory.count(EmberFlask.ITEM_ID), 2,
		"rejected replay pays nothing")
	var state: Array = sim.snapshot_for(811).get("ember_pools", [])
	t.eq(state.size(), 1, "clients receive one nearby fire patch")
	if not state.is_empty():
		t.check(not state[0].has("owner") and not state[0].has("expires"),
			"replication excludes owner and private timers")
		t.near(float(state[0]["remaining"]), EmberFlask.DURATION, 0.001,
			"public lifetime is server-authorized")
	var distant = sim.add_player(812, "FarAway")
	distant.position = Vector3(-500, world.height_at(-500, -500), -500)
	t.eq(sim.snapshot_for(distant.id)["ember_pools"].size(), 0,
		"remote peers cannot inspect distant danger areas")

	t.current = "PvE damage, boss resistance and no player friendly fire"
	var center := Vector2(float(landing["x"]), float(landing["z"]))
	var survivor = sim.add_player(813, "NoFriendlyFire")
	survivor.position = _at(world, center)
	var safe_hp: float = survivor.survival.health
	var brute := Zombie.new(sim.new_id(), "brute", _at(world, center))
	var boss := Zombie.new(sim.new_id(), "brute",
		_at(world, center + Vector2(0, 0.4)))
	boss.raid_boss = true
	sim.zombies[brute.id] = brute
	sim.zombies[boss.id] = boss
	var brute_hp: float = brute.health
	var boss_hp: float = boss.health
	sim.time += 1.0
	sim._tick_ember_pools()
	t.near(brute.health, brute_hp - EmberFlask.DAMAGE_PER_TICK, 0.001,
		"server burns ordinary infected once per second")
	t.near(boss.health, boss_hp - EmberFlask.DAMAGE_PER_TICK * 0.5,
		0.001, "raid boss resists half fire damage")
	t.near(survivor.survival.health, safe_hp, 0.001,
		"other players are never damaged by the fire")
	var before: float = brute.health
	sim.time += 0.2
	sim._tick_ember_pools()
	t.near(brute.health, before, 0.001,
		"rapid tick calls cannot multiply burn damage")

	t.current = "overlapping fire cannot stack ticks or spam inventory"
	player.flash_cooldown = 0.0
	t.check(sim.cmd_throw_ember(811, 1.0, 0.0).get("ok", false),
		"second physical flask creates second overlapping patch")
	t.eq(player.inventory.count(EmberFlask.ITEM_ID), 1,
		"second patch spends one more flask")
	sim.time += 1.0
	before = brute.health
	sim._tick_ember_pools()
	t.near(brute.health, before - EmberFlask.DAMAGE_PER_TICK, 0.001,
		"two flames inflict only one damage pulse per infected")
	player.flash_cooldown = 0.0
	t.eq(sim.cmd_throw_ember(811, 1.0, 0.0).get("reason", ""),
		"owner_limit", "owner cannot exceed two live flasks")
	t.eq(player.inventory.count(EmberFlask.ITEM_ID), 1,
		"owner limit consumes no extra item")
	var net := Net.new()
	net.role = "server"
	net.sim = sim
	t.check(net.has_method("c_throw_ember"), "online clients have authorized RPC")
	t.check(net._event_visible_to({"type": "ember_thrown",
		"x": center.x, "z": center.y}, 811),
		"nearby clients may see the throw")
	t.check(not net._event_visible_to({"type": "ember_thrown",
		"x": center.x, "z": center.y}, 812),
		"far clients receive no tactical location leak")
	net.free()

	t.current = "expiry, privacy and safe-hub retreat"
	sim.time += EmberFlask.DURATION + 1.0
	sim._tick_ember_pools()
	t.eq(sim.ember_pools.size(), 0, "all fire patches expire")
	t.eq(sim._ember_last_hit.size(), 0, "throttle memory is reclaimed")
	t.check(not sim.character_data(player).has("ember_pools"),
		"temporary hazards are never saved to character data")
	player.flash_cooldown = 0.0
	t.check(sim.cmd_throw_ember(811, 1.0, 0.0).get("ok", false),
		"owner may throw again after expiry")
	player.position = Vector3.ZERO
	sim.time += 1.0
	sim._tick_ember_pools()
	t.eq(sim.ember_pools.size(), 0,
		"safe-hub retreat extinguishes orphaned fire")
