extends RefCounted
## Authoritative outpost reinforcement and economy conservation in contested PvP.
## Runs in the game headless suite without Nakama or live sockets.

const WorldGen = preload("res://scripts/shared/world_gen.gd")
const GameServer = preload("res://scripts/server/game_server.gd")
const Territory = preload("res://scripts/shared/territory_control.gd")
const Fortification = preload("res://scripts/shared/outpost_fortification.gd")
const ZoneRisk = preload("res://scripts/shared/zone_risk.gd")
const Net = preload("res://scripts/shared/net.gd")


func _move(server, player, position: Vector2) -> void:
	player.position = Vector3(position.x, server.world.height_at(position.x, position.y), position.y)


func _advance(server, seconds: float) -> void:
	for i in range(int(ceil(seconds / 0.25))):
		server.time += 0.25
		server.territory.tick(0.25, server.time, server.players, server.parties)


func run(t) -> void:
	t.current = "outpost upgrades require real party ownership and proximity"
	var server := GameServer.new(WorldGen.new(205), 205)
	t.check(not server.territory.sites.is_empty(), "test world has at least one dangerous outpost")
	if server.territory.sites.is_empty():
		return
	var site: Dictionary = server.territory.sites[0]
	var id: int = int(site["id"])
	var position := Vector2(float(site["x"]), float(site["z"]))
	t.check(ZoneRisk.full_loot(server.world.zone_at(position.x, position.y)),
		"upgrades take place in the risky loot-drop territory")
	var leader = server.add_player(1001, "Architect")
	var ally = server.add_player(1002, "Guard")
	var enemy = server.add_player(1003, "Enemy")
	_move(server, leader, position)
	_move(server, ally, position + Vector2(1.0, 0.0))
	_move(server, enemy, position + Vector2(80.0, 0.0))
	leader.inventory.add("wood_1", 50)
	leader.inventory.add("stone_1", 50)
	var original_wood: int = leader.inventory.count("wood_1")
	var original_stone: int = leader.inventory.count("stone_1")
	t.eq(server.cmd_outpost_fortify(1001, id, 1)["reason"], "not_owner",
		"resources cannot be spent to upgrade an unclaimed flag")
	t.eq(leader.inventory.count("wood_1"), original_wood, "failed upgrade keeps wood")
	t.eq(leader.inventory.count("stone_1"), original_stone, "failed upgrade keeps stone")
	t.check(server.parties.invite(1001, 1002, server.time)["ok"], "creates party")
	t.check(server.parties.accept(1002, server.time)["ok"], "real group joins")
	_advance(server, Territory.CAPTURE_SECONDS + 0.5)
	var group_id: int = server.parties.group_of(1001)
	t.eq(site["owner"], group_id, "group captures flag normally")
	t.eq(site["fortification"], 0, "new owner starts without fortifications")

	t.current = "server-atomic material expenditure and same-request replay"
	var first: Dictionary = server.cmd_outpost_fortify(1001, id, 2)
	t.check(first["ok"], "nearby member may fortify the owned outpost")
	t.eq(int(first["level"]), 1, "first resource donation buys tier one")
	var cost1: Dictionary = Fortification.cost_for_level(1)
	t.eq(leader.inventory.count("wood_1"), original_wood - int(cost1["wood_1"]), "wood debit is exact")
	t.eq(leader.inventory.count("stone_1"), original_stone - int(cost1["stone_1"]), "stone debit is exact")
	t.eq(server.cmd_outpost_fortify(1001, id, 2), first,
		"retry reuses the receipt and spends no more materials")
	t.eq(leader.inventory.count("wood_1"), original_wood - int(cost1["wood_1"]),
		"replay does not spend additional wood")
	t.eq(server.cmd_outpost_fortify(1001, id + 100, 2)["reason"], "request_conflict",
		"same nonce cannot change its target outpost")
	t.eq(server.cmd_outpost_fortify(1001, id, 1)["reason"], "stale_request",
		"old request cannot be executed again")
	t.eq(server.cmd_outpost_fortify(1001, id, 0)["reason"], "invalid_request_id",
		"zero request ID refused")
	t.eq(server.cmd_outpost_fortify(1001, id, -4)["reason"], "invalid_request_id",
		"negative request ID refused")
	t.eq(server.cmd_outpost_fortify(1001, id, GameServer.FORTIFY_MAX_REQUEST_ID + 1)["reason"],
		"invalid_request_id", "oversized request ID refused")
	t.check(leader.dirty_inventory and leader.dirty_character, "resource spending marks character dirty")
	t.eq(server.territory.capture_target(site),
		Territory.CAPTURE_SECONDS + Fortification.EXTRA_CAPTURE_SECONDS_PER_LEVEL,
		"tier one adds 10 seconds to enemy capture duration")
	t.eq(server.snapshot_for(1001)["outposts"][0]["fortification"], 1,
		"tier appears in public authoritative snapshot")
	t.eq(server.snapshot_for(1001)["outposts"][0]["capture_target"],
		server.territory.capture_target(site), "capture target appears in public snapshot")
	var net := Net.new()
	net.role = "server"
	net.sim = server
	t.check(net._event_visible_to({"type": "outpost_fortified", "x": position.x,
		"z": position.y}, 1002), "nearby members receive siege event")
	_move(server, enemy, position + Vector2(120.0, 0.0))
	t.check(not net._event_visible_to({"type": "outpost_fortified", "x": position.x,
		"z": position.y}, 1003), "distant players do not receive an outpost event")
	net.free()

	t.current = "contest blocks upgrades without spending resources"
	_move(server, enemy, position + Vector2(2.0, 0.0))
	var before_wood: int = leader.inventory.count("wood_1")
	var before_stone: int = leader.inventory.count("stone_1")
	t.eq(server.cmd_outpost_fortify(1001, id, 3)["reason"], "contested",
		"enemy nearby blocks fortification even before the next server tick")
	t.eq(leader.inventory.count("wood_1"), before_wood, "no wood spent while contested")
	t.eq(leader.inventory.count("stone_1"), before_stone, "no stone spent while contested")
	_move(server, enemy, position + Vector2(80.0, 0.0))
	_advance(server, 0.25)
	_move(server, leader, position + Vector2(5.0, 0.0))
	t.eq(server.cmd_outpost_fortify(1001, id, 4)["reason"], "too_far",
		"out-of-range owners cannot upgrade remotely")
	_move(server, leader, position)
	var depleted = Fortification.cost_for_level(2)
	leader.inventory.remove("stone_1", leader.inventory.count("stone_1"))
	t.eq(server.cmd_outpost_fortify(1001, id, 5)["reason"], "missing_items",
		"insufficient stone blocks upgrade")
	t.eq(site["fortification"], 1, "insufficient supplies do not change tier")
	leader.inventory.add("stone_1", 40)

	t.current = "bounded upgrade tiers and repeated tier cap"
	var tier2: Dictionary = server.cmd_outpost_fortify(1001, id, 6)
	var tier3: Dictionary = server.cmd_outpost_fortify(1001, id, 7)
	t.check(tier2["ok"] and tier3["ok"], "two further donations build tier three")
	t.eq(site["fortification"], Fortification.MAX_LEVEL, "tier cannot exceed hard cap")
	t.eq(server.cmd_outpost_fortify(1001, id, 8)["reason"], "max_level",
		"no further consumption after max tier")
	t.eq(server.territory.capture_target(site),
		Territory.CAPTURE_SECONDS + 3.0 * Fortification.EXTRA_CAPTURE_SECONDS_PER_LEVEL,
		"maximum tier adds exactly thirty seconds of attacker capture time")
	t.eq(server.cmd_outpost_fortify(1003, id, 1)["reason"], "too_far",
		"distant enemy cannot upgrade someone else's flag")
	_move(server, enemy, position)
	t.eq(server.cmd_outpost_fortify(1003, id, 2)["reason"], "not_owner",
		"enemy within four metres still lacks party ownership")

	t.current = "fortifications delay attackers and are destroyed on conquest"
	var attacker2 = server.add_player(1004, "Raider")
	_move(server, attacker2, position + Vector2(1.0, 0.0))
	t.check(server.parties.invite(1003, 1004, server.time)["ok"], "attackers form group")
	t.check(server.parties.accept(1004, server.time)["ok"], "attackers ready")
	_move(server, leader, position + Vector2(80.0, 0.0))
	_move(server, ally, position + Vector2(80.0, 0.0))
	_advance(server, Territory.CAPTURE_SECONDS + 1.0)
	t.eq(site["owner"], group_id, "tier three holds against base 30-second attack")
	_advance(server, 3.0 * Fortification.EXTRA_CAPTURE_SECONDS_PER_LEVEL)
	t.eq(site["owner"], server.parties.group_of(1003), "attackers take the fortified flag after extra time")
	t.eq(site["fortification"], 0, "fortifications are destroyed on conquest")
	t.eq(server.territory.capture_target(site), Territory.CAPTURE_SECONDS,
		"new owner begins at ordinary capture duration")
	t.eq(server.cmd_outpost_fortify(1001, id, 9)["reason"], "too_far",
		"former owner cannot use abandoned fortifications remotely")
	t.eq(Fortification.cost_for_level(0), {}, "invalid tier has no cost")
	t.eq(Fortification.cost_for_level(4), {}, "costs above tier three do not exist")
	var snapshot_cost := Fortification.cost_for_level(1)
	snapshot_cost["wood_1"] = 999
	t.eq(Fortification.cost_for_level(1)["wood_1"], 4,
		"external callers cannot mutate the server's fixed tier costs")
