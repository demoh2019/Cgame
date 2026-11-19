extends RefCounted
## MMORPG-inspired PvE threat/hate without client-trusted aggro values.
const Threat = preload("res://scripts/shared/threat.gd")
const Zombie = preload("res://scripts/shared/zombie.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const GameServer = preload("res://scripts/server/game_server.gd")


func _info(a: Vector3, b: Vector3) -> Dictionary:
	return {
		1: {"position": a, "alive": true, "safe": false, "noise": 0.0},
		2: {"position": b, "alive": true, "safe": false, "noise": 0.0}
	}


func run(t) -> void:
	t.current = "bounded and validated server threat"
	var table: Dictionary = {}
	t.check(not Threat.record(table, -1, 100.0), "invalid peer cannot gain threat")
	t.check(not Threat.record(table, 1, NAN), "NaN damage rejected")
	t.check(not Threat.record(table, 1, INF), "infinite damage rejected")
	t.check(not Threat.record(table, 1, -5.0), "negative damage rejected")
	t.eq(table.size(), 0, "forged damage cannot grow threat table")
	for peer in range(1, Threat.MAX_TARGETS + 1):
		t.check(Threat.record(table, peer, float(peer)), "valid actor can earn threat")
	t.eq(table.size(), Threat.MAX_TARGETS, "threat memory is bounded")
	t.check(not Threat.record(table, 77, 0.5), "weak new target cannot evict a stronger attacker")
	t.check(Threat.record(table, 77, 30.0), "real high threat replaces weakest entry")
	t.eq(table.size(), Threat.MAX_TARGETS, "replacement never increases memory")
	t.check(not table.has(1), "lowest threat evicted first")
	Threat.decay(table, NAN)
	t.eq(table.size(), Threat.MAX_TARGETS, "invalid delta never changes table")
	Threat.decay(table, 60.0)
	t.eq(table.size(), 0, "stale threat decays without permanent aggro")

	t.current = "priority, aggro stability and safety"
	var origin := Vector2.ZERO
	var players := _info(Vector3(3, 0, 0), Vector3(9, 0, 0))
	table = {1: 10.0, 2: 20.0}
	t.eq(Threat.pick(table, players, origin, 30.0), 2, "distant damaging player outranks nearby by threat")
	table = {1: 10.0, 2: 12.0}
	t.eq(Threat.pick(table, players, origin, 30.0, 1), 1, "modest damage does not constantly switch aggro")
	table[2] = 15.0
	t.eq(Threat.pick(table, players, origin, 30.0, 1), 2, "significant damage pulls aggro away")
	players[2]["safe"] = true
	t.eq(Threat.pick(table, players, origin, 30.0), 1, "protected survivors cannot retain hate")
	t.check(not table.has(2), "safe-zone entrant removed from hate list")
	players[1]["position"] = Vector3(500, 0, 0)
	t.eq(Threat.pick(table, players, origin, 30.0), -1, "leash prevents cross-map target tracking")
	t.eq(table.size(), 0, "distant target removed from memory")

	t.current = "real damage creates zombie aggro"
	var world := WorldGen.new(39)
	var server := GameServer.new(world, 39)
	var front = server.add_player(101, "Shield")
	var back = server.add_player(102, "Archer")
	front.position = Vector3(301, world.height_at(301, 0), 0)
	back.position = Vector3(307, world.height_at(307, 0), 0)
	var infected := Zombie.new(server.new_id(), "brute",
		Vector3(300, world.height_at(300, 0), 0))
	server.zombies[infected.id] = infected
	server._tick_zombies(0.1)
	t.eq(infected.target_id, 101, "nearest survivor attracts an unaware infected")
	server._damage_target(back, {"kind": "zombie", "id": infected.id}, 30.0)
	t.check(infected.threat.has(102), "only confirmed server damage records attacker ID")
	infected.think_timer = 0.0
	server._tick_zombies(0.1)
	t.eq(infected.target_id, 102, "ranged damage pulls aggro from the frontliner")
	server._damage_target(front, {"kind": "zombie", "id": infected.id}, 45.0)
	infected.think_timer = 0.0
	server._tick_zombies(0.1)
	t.eq(infected.target_id, 101, "frontliner can retake aggro with stronger hits")
	front.position = Vector3(1.0, world.height_at(1, 0), 0)
	infected.think_timer = 0.0
	server._tick_zombies(0.1)
	t.eq(infected.target_id, 102, "safe hub cannot be chased even with high threat")
	t.check(not infected.threat.has(101), "safe player threat is forgotten")
	server._damage_target(back, {"kind": "zombie", "id": infected.id}, 999.0)
	t.check(not infected.is_alive(), "lethal server hit still kills normally")
	t.eq(infected.threat.size(), 0, "zombie death frees all threat memory")
	var before: int = back.kills
	server._damage_target(back, {"kind": "zombie", "id": infected.id}, 999.0)
	t.eq(back.kills, before, "repeated damage cannot farm extra kills")
