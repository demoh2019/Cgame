extends RefCounted
## War declarations should be earned through carried supplies and actual
## territory capture, never awarded from client assertions or replayed RPCs.

const WorldGen = preload("res://scripts/shared/world_gen.gd")
const GameServer = preload("res://scripts/server/game_server.gd")
const Territory = preload("res://scripts/shared/territory_control.gd")
const SiegeContracts = preload("res://scripts/shared/siege_contracts.gd")
const Inventory = preload("res://scripts/shared/inventory.gd")


func _at(server, player, point: Vector2) -> void:
	player.position = Vector3(point.x, server.world.height_at(point.x, point.y), point.y)


func _advance(server, duration: float) -> Array:
	var output: Array = []
	for step in range(int(ceil(duration / 0.25))):
		server.time += 0.25
		var captures: Array = server.territory.tick(0.25, server.time, server.players, server.parties)
		output.append_array(captures)
		output.append_array(server.siege_contracts.tick(
			server.time, server.territory.sites, server.parties, captures))
	return output


func run(t) -> void:
	t.current = "war declaration requires two nearby group members and a hostile outpost"
	var server := GameServer.new(WorldGen.new(205), 205)
	t.check(not server.territory.sites.is_empty(), "seed 205 has at least one siege site")
	if server.territory.sites.is_empty():
		return
	var site: Dictionary = server.territory.sites[0]
	var site_id: int = int(site["id"])
	var center := Vector2(float(site["x"]), float(site["z"]))
	var d1 = server.add_player(101, "Defending leader")
	var d2 = server.add_player(102, "Defending guard")
	var a1 = server.add_player(201, "Attacking leader")
	var a2 = server.add_player(202, "Attacking ally")
	_at(server, d1, center)
	_at(server, d2, center + Vector2(1, 0))
	_at(server, a1, center + Vector2(18, 0))
	_at(server, a2, center + Vector2(19, 0))
	a1.inventory.add("cloth_2", 5)
	a1.inventory.add("silver", 100)
	t.check(server.cmd_party_invite(101, 102)["ok"], "defenders form party")
	t.check(server.cmd_party_accept(102)["ok"], "defender joins")
	_advance(server, Territory.CAPTURE_SECONDS + 1.0)
	var defender_id: int = server.parties.group_of(101)
	t.eq(int(site["owner"]), defender_id, "defenders own flag before war")
	t.eq(server.cmd_siege_declare(201, site_id, 1)["reason"], "leader_only",
		"ungrouped players cannot announce wars")
	t.check(server.cmd_party_invite(201, 202)["ok"], "attackers can form party")
	t.check(server.cmd_party_accept(202)["ok"], "attacking ally joins")
	var attacker_id: int = server.parties.group_of(201)
	t.check(attacker_id != defender_id, "attacker group is distinct from defender")
	t.eq(server.cmd_siege_declare(202, site_id, 1)["reason"], "leader_only",
		"normal party members cannot declare wars")
	t.eq(server.cmd_siege_declare(101, site_id, 1)["reason"], "not_enemy",
		"defenders cannot declare war on themselves")
	_at(server, a2, center + Vector2(40, 0))
	t.eq(server.cmd_siege_declare(201, site_id, 2)["reason"], "requires_party",
		"remote ally does not count toward minimum attackers")
	_at(server, a2, center + Vector2(19, 0))
	_at(server, a1, center + Vector2(30, 0))
	t.eq(server.cmd_siege_declare(201, site_id, 3)["reason"], "too_far",
		"war declarations must originate near the enemy outpost")
	_at(server, a1, center + Vector2(18, 0))
	t.eq(server.cmd_siege_declare(201, site_id + 1000, 4)["reason"], "unknown_outpost",
		"fake outpost IDs cannot charge currency")
	var before_cloth: int = a1.inventory.count("cloth_2")
	var before_silver: int = a1.inventory.count("silver")
	t.eq(server.cmd_siege_declare(201, site_id, 0)["reason"], "invalid_request_id",
		"zero request ID is refused")
	t.eq(server.cmd_siege_declare(201, site_id, GameServer.SIEGE_DECLARE_MAX_REQUEST_ID + 1)["reason"],
		"invalid_request_id", "too-large nonce is refused")

	t.current = "paid war contract and network retries are exactly-once"
	var declared: Dictionary = server.cmd_siege_declare(201, site_id, 5)
	t.check(declared.get("ok", false), "party leader declares challenge with real supplies")
	t.eq(a1.inventory.count("cloth_2"), before_cloth - 2, "two cloth consumed once")
	t.eq(a1.inventory.count("silver"), before_silver - 25, "25 silver consumed once")
	t.eq(server.cmd_siege_declare(201, site_id, 5), declared,
		"identical retry returns same server receipt")
	t.eq(a1.inventory.count("silver"), before_silver - 25, "retry cannot double charge")
	t.eq(server.cmd_siege_declare(201, site_id + 1, 5)["reason"], "request_conflict",
		"reused nonce with changed target is blocked")
	t.eq(server.cmd_siege_declare(201, site_id, 4)["reason"], "stale_request",
		"older nonce cannot create another challenge")
	t.eq(server.cmd_siege_declare(201, site_id, 6)["reason"], "already_declared",
		"only one active siege per outpost")
	t.check(a1.dirty_inventory and a1.dirty_character,
		"paid materials enter the character save snapshot")
	var public: Dictionary = server.snapshot_for(201)["outposts"][0]
	t.eq(public["siege_phase"], "preparing", "HUD sees preparation stage")
	t.eq(public["siege_attacker"], attacker_id, "correct group appears as challenger")
	t.eq(int(public["siege_starts_in"]), 20, "preparation lasts twenty seconds")
	t.check(not public.has("user_id"), "siege snapshot does not leak account IDs")

	t.current = "honor only for capture inside declared window"
	_advance(server, SiegeContracts.PREPARATION_SECONDS + 1.0)
	t.eq(server.snapshot_for(201)["outposts"][0]["siege_phase"], "active",
		"war becomes active after preparation")
	t.eq(server.siege_contracts.victories.get(attacker_id, 0), 0,
		"declaration alone never awards wins")
	_at(server, d1, center + Vector2(80, 0))
	_at(server, d2, center + Vector2(81, 0))
	_at(server, a1, center)
	_at(server, a2, center + Vector2(1, 0))
	var events: Array = _advance(server, Territory.CAPTURE_SECONDS + 2.0)
	t.eq(int(site["owner"]), attacker_id, "attackers actually capture the contested flag")
	t.eq(int(server.siege_contracts.victories.get(attacker_id, 0)), 1,
		"one legitimate war victory awarded")
	t.eq(events.filter(func(e): return e["type"] == "siege_contract_result" and e["result"] == "won").size(), 1,
		"exactly one war victory event")
	t.eq(server.snapshot_for(201)["you"]["siege_wins"], 1, "party member sees win count")
	t.eq(server.snapshot_for(202)["you"]["siege_wins"], 1, "ally sees same win count")
	t.check(server.siege_contracts.active.is_empty(), "completed war cannot be replayed")
	t.eq(server.siege_contracts.tick(server.time, server.territory.sites, server.parties, events).size(), 0,
		"repeated combat event cannot grant an extra victory")
	t.eq(server.cmd_siege_declare(201, site_id, 7)["reason"], "not_enemy",
		"new owner cannot start a new paid siege on itself")

	t.current = "expiration, early capture and supply rollback"
	var rule := SiegeContracts.new()
	var mock := {"id": 999, "x": 2.0, "z": 2.0,
		"owner": defender_id, "until": 2000.0}
	var bag := Inventory.new()
	bag.add("cloth_2", 8)
	bag.add("silver", 100)
	var early: Dictionary = rule.declare(mock, bag, Vector3(2, 0, 2),
		attacker_id, true, 2, 100.0)
	t.check(early["ok"], "pure contract service accepts valid funded challenge")
	var first_cost: int = bag.count("silver")
	t.eq(first_cost, 75, "pure service also charges exactly once")
	mock["owner"] = attacker_id
	var early_events: Array = rule.tick(110.0, [mock], server.parties,
		[{"type": "outpost_taken", "id": 999, "owner": attacker_id}])
	t.eq(early_events.size(), 1, "early capture finishes contract")
	t.eq(early_events[0]["result"], "lost", "premature capture is not a scored victory")
	t.eq(int(rule.victories.get(attacker_id, 0)), 0, "early captures score no honor")
	mock["owner"] = defender_id
	t.eq(rule.declare(mock, bag, Vector3(2, 0, 2), attacker_id, true, 2, 111.0)["reason"],
		"cooldown", "site cooldown stops immediate war farming")
	rule.cooldowns.clear()
	var later: Dictionary = rule.declare(mock, bag, Vector3(2, 0, 2), attacker_id, true, 2, 200.0)
	t.check(later["ok"], "later war can be funded")
	t.eq(rule.tick(401.0, [mock], server.parties, [])[0]["result"], "expired",
		"war ends without victory when attack window expires")
	t.eq(int(rule.victories.get(attacker_id, 0)), 0, "expiration awards no victory")
	t.eq(rule.tick(402.0, [mock], server.parties, []).size(), 0,
		"expired contracts cannot emit duplicate events")
	var poor := Inventory.new()
	poor.add("cloth_2", 2)
	t.eq(rule.declare(mock, poor, Vector3(2, 0, 2),
		attacker_id, true, 2, 800.0)["reason"], "missing_materials",
		"cannot declare without silver")
	t.eq(poor.count("cloth_2"), 2, "failure does not spend remaining cloth")
	t.eq(rule.declare(mock, poor, Vector3(NAN, 0, 2),
		attacker_id, true, 2, 800.0)["reason"], "invalid_position",
		"nonfinite client positions are rejected")
	t.check(not rule.public_state([{"id": 999}], 900.0)[0].has("user_id"),
		"empty public state exposes no character information")

	t.current = "disconnect clears nonce state"
	server.remove_player(201)
	t.check(not server.siege_declare_requests.has(201),
		"peer ID can be recycled without inheriting an old declaration nonce")
