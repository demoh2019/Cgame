extends RefCounted
## End-to-end shoreline fishing, server-owned rewards and event privacy.

const Defs = preload("res://scripts/shared/defs.gd")
const Fishing = preload("res://scripts/shared/fishing.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const GameServer = preload("res://scripts/server/game_server.gd")
const Net = preload("res://scripts/shared/net.gd")


func _shore(world) -> Vector3:
	# Deterministic scan so the test does not depend on a handcrafted map.
	for x in range(-260, 261, 4):
		for z in range(-260, 261, 4):
			if world.is_water(float(x), float(z)):
				continue
			var where := Vector3(float(x), world.height_at(float(x), float(z)), float(z))
			if Fishing.water_near(world, where) != Vector2.INF:
				return where
	return Vector3.INF


func run(t) -> void:
	var world := WorldGen.new(42)
	var sim := GameServer.new(world, 43)
	var player = sim.add_player(541, "Shore Survivor")
	var shore: Vector3 = _shore(world)
	t.current = "server-authoritative shore access"
	t.check(shore.is_finite(), "found reproducible shoreline near water")
	if not shore.is_finite():
		return
	player.position = shore
	var without_rod: Dictionary = sim.cmd_fish(541)
	t.eq(without_rod.get("reason", ""), "need_rod", "cannot fish barehanded")
	t.eq(player.inventory.count("raw_fish"), 0, "refused cast gives no fish")
	player.inventory.add("fishing_rod", 1)
	var cast: Dictionary = sim.cmd_fish(541)
	t.check(bool(cast.get("ok", false)), "carried rod and nearby shore allow casting")
	if not bool(cast.get("ok", false)):
		return
	t.check(player.action.has("fish"), "server starts timed fishing action")
	t.eq(sim.cmd_fish(541).get("reason", ""), "busy", "cannot double-cast while fishing")
	t.eq(player.inventory.count("raw_fish"), 0, "no instant fish is awarded")

	t.current = "server owns timing, catch and experience"
	var xp_before: int = int(player.progression.gathering_xp["fishing"])
	for i in range(55):
		sim.time += 0.1
		sim._tick_players(0.1)
	t.check(player.action.is_empty(), "cast completes after five seconds")
	var caught: int = player.inventory.count("raw_fish")
	t.check(caught >= 1 and caught <= 2, "server picks a bounded 1–2 fish catch")
	t.eq(int(player.progression.gathering_xp["fishing"]) - xp_before,
		caught * player.progression.GATHER_XP_PER_ITEM, "only credited fish earn skill XP")
	t.eq(sim.cmd_fish(541).get("reason", ""), "cooldown", "fishing cooldown is enforced")

	t.current = "private network catch notification"
	var net := Net.new()
	net.role = "server"
	net.sim = sim
	var catch_event: Dictionary = {}
	for event in sim.events:
		if event.get("type", "") == "fished":
			catch_event = event
	t.check(not catch_event.is_empty(), "server emitted catch notification")
	if not catch_event.is_empty():
		t.eq(int(catch_event.get("amount", 0)), caught, "event contains actual credited fish")
		t.check(net._event_visible_to(catch_event, 541), "fisher receives their catch")
		t.check(not net._event_visible_to(catch_event, 542), "other peers cannot see private catch")
	net.free()

	t.current = "cancelled casts"
	sim.time += Fishing.COOLDOWN_SECONDS + 1.0
	t.check(bool(sim.cmd_fish(541).get("ok", false)), "can fish again after cooldown")
	var before_cancel := player.inventory.count("raw_fish")
	player.position += Vector3(5, 0, 0)
	sim._tick_players(0.1)
	t.check(player.action.is_empty(), "walking away cancels the cast")
	t.eq(player.inventory.count("raw_fish"), before_cancel, "cancelled cast awards nothing")
