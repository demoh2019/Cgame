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


	t.current = "Equal threat ties are deterministic and preserve current aggro"
	var tie_players: Dictionary = _info(Vector3(6, 0, 0), Vector3(7, 0, 0))
	var a_first := {1: 10.0, 2: 10.0}
	var b_first := {2: 10.0, 1: 10.0}
	t.eq(Threat.pick(a_first, tie_players, Vector2.ZERO, 30.0), 1,
		"equal hate chooses smaller peer ID regardless of insertion order")
	t.eq(Threat.pick(b_first, tie_players, Vector2.ZERO, 30.0), 1,
		"reversed insertion order gives the same server target")
	t.eq(Threat.pick(a_first, tie_players, Vector2.ZERO, 30.0, 2), 2,
		"equal hate does not cause an active target to flap")
	var reverse_full: Dictionary = {5: 10.0, 4: 10.0, 3: 10.0, 2: 10.0, 1: 10.0}
	t.check(Threat.record(reverse_full, 9, 11.0),
		"a stronger new attacker displaces the weakest stored hate")
	t.check(not reverse_full.has(1) and reverse_full.has(2),
		"equal weakest scores always evict lowest peer ID")

	t.current = "Native engine threat arithmetic retains the game API"
	var native_threat_available: bool = ClassDB.class_exists("AIThreatTable2D")
	t.eq(Threat.has_native(), native_threat_available,
		"native threat capability is negotiated without requiring Cgame")
	var expired: Dictionary = {1: 0.2, 2: 1.5}
	Threat.decay(expired, 1.0)
	t.check(not expired.has(1), "decay removes exhausted threat")
	t.near(float(expired.get(2, 0.0)), 0.75, 0.00001,
		"both engine and stock Godot age threat by the same amount")
	var broken: Dictionary = {1: 4.0, 2: NAN}
	Threat.decay(broken, 0.1)
	t.check(not broken.has(2), "malformed recorded threat cannot poison the table")
	t.check(broken.has(1), "malformed peer entries do not erase valid attackers")

	t.current = "native/fallback per-target threat attenuation"
	var retained: Dictionary = {1: 80.0, 2: 10.0}
	t.check(Threat.scale(retained, 1, 0.35), "existing threat can be reduced")
	t.near(float(retained[1]), 28.0, 0.00001, "medic cover retains exactly 35 percent")
	t.eq(float(retained[2]), 10.0, "other attacker is unchanged")
	t.check(not Threat.scale(retained, 3, 0.5), "missing peer cannot gain aggro")
	for bad_factor in [NAN, INF, -0.1, 1.1]:
		t.check(not Threat.scale(retained, 1, bad_factor),
			"invalid retention must be rejected")
	t.near(float(retained[1]), 28.0, 0.00001,
		"invalid retention never modifies threat")
	t.check(Threat.scale(retained, 1, 1.0), "identity retention is supported")
	t.check(Threat.scale(retained, 1, 0.0), "zero retention clears this target")
	t.check(not retained.has(1), "zero retention does not leave a ghost target")
	t.eq(float(retained[2]), 10.0, "other combatants still own their threat")
	var malformed_retention: Dictionary = {1: NAN, 2: 10.0}
	t.check(not Threat.scale(malformed_retention, 1, 0.5),
		"malformed stored threat is rejected")
	t.check(not malformed_retention.has(1) and malformed_retention.has(2),
		"only the malformed peer is removed")
	if native_threat_available:
		var native_tracker: Object = ClassDB.instantiate("AIThreatTable2D")
		var raw_native: Dictionary = {1: 80.0, 2: 10.0}
		t.check(native_tracker.scale(raw_native, 1, 0.35),
			"new engine method is script-callable")
		t.near(float(raw_native[1]), 28.0, 0.00001,
			"native engine matches the fallback's retention")

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
