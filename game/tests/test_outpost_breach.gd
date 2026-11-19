extends RefCounted
## Replays, costs and authority checks for an attacker-side siege mechanic.

const WorldGen = preload("res://scripts/shared/world_gen.gd")
const GameServer = preload("res://scripts/server/game_server.gd")
const Territory = preload("res://scripts/shared/territory_control.gd")
const OutpostBreach = preload("res://scripts/shared/outpost_breach.gd")


func _at(server, player, center: Vector2) -> void:
	player.position = Vector3(center.x, server.world.height_at(center.x, center.y), center.y)


func _advance(server, seconds: float) -> void:
	for i in range(int(ceil(seconds / 0.25))):
		server.time += 0.25
		server.territory.tick(0.25, server.time, server.players, server.parties)


func run(t) -> void:
	t.current = "siege breach needs enemy-owned fortified point"
	var server := GameServer.new(WorldGen.new(205), 205)
	t.check(not server.territory.sites.is_empty(), "siege test world has a dangerous objective")
	if server.territory.sites.is_empty():
		return
	var site: Dictionary = server.territory.sites[0]
	var site_id: int = int(site["id"])
	var point := Vector2(float(site["x"]), float(site["z"]))
	var owner = server.add_player(101, "Guardian")
	var owner_ally = server.add_player(102, "Builder")
	var attacker = server.add_player(201, "Breacher")
	var attacker_ally = server.add_player(202, "Vanguard")
	_at(server, owner, point)
	_at(server, owner_ally, point + Vector2(1.0, 0.0))
	_at(server, attacker, point + Vector2(80.0, 0.0))
	_at(server, attacker_ally, point + Vector2(81.0, 0.0))
	owner.inventory.add("wood_1", 30)
	owner.inventory.add("stone_1", 30)
	attacker.inventory.add("plank_2", 10)
	attacker.inventory.add("bar_2", 10)
	t.check(server.cmd_party_invite(101, 102)["ok"], "defenders can group")
	t.check(server.cmd_party_accept(102)["ok"], "defenders join")
	_advance(server, Territory.CAPTURE_SECONDS + 1.0)
	var owner_group: int = server.parties.group_of(101)
	t.eq(site["owner"], owner_group, "defenders have captured the flag")
	t.check(server.cmd_outpost_fortify(101, site_id, 1)["ok"], "tier one built")
	t.check(server.cmd_outpost_fortify(101, site_id, 2)["ok"], "tier two built")
	t.eq(site["fortification"], 2, "outpost has two defensive tiers")
	var duration_before: float = server.territory.capture_target(site)
	_at(server, attacker, point)
	t.eq(server.cmd_outpost_breach(201, site_id, 1)["reason"], "not_enemy",
		"unaffiliated attackers cannot breach an enemy fort")
	t.eq(server.cmd_outpost_breach(201, site_id + 500, 2)["reason"], "unknown_outpost",
		"fake outpost IDs are refused")
	_at(server, attacker, point + Vector2(80.0, 0.0))
	t.check(server.cmd_party_invite(201, 202)["ok"], "attackers can form a real party")
	t.check(server.cmd_party_accept(202)["ok"], "second attacker joins")
	_at(server, attacker, point)
	t.eq(server.cmd_outpost_breach(201, site_id, 3)["reason"], "requires_party",
		"two living nearby attacking party members are required")
	_at(server, attacker_ally, point + Vector2(1.0, 0.0))
	t.eq(server.cmd_outpost_breach(201, site_id, 0)["reason"], "invalid_request_id",
		"zero RPC request IDs are refused")
	t.eq(server.cmd_outpost_breach(201, site_id, -10)["reason"], "invalid_request_id",
		"negative RPC request IDs are refused")
	t.eq(server.cmd_outpost_breach(201, site_id, GameServer.BREACH_MAX_REQUEST_ID + 1)["reason"],
		"invalid_request_id", "oversized request IDs are refused")
	var wood_before: int = owner.inventory.count("wood_1")
	var planks_before: int = attacker.inventory.count("plank_2")
	var bars_before: int = attacker.inventory.count("bar_2")
	t.current = "one breach consumes exactly one recipe and lowers one fortification tier"
	var first: Dictionary = server.cmd_outpost_breach(201, site_id, 4)
	t.check(bool(first.get("ok", false)), "prepared enemy party can breach a defended flag")
	t.eq(first["level"], 1, "one fortification tier removed")
	t.eq(attacker.inventory.count("plank_2"), planks_before - 2, "exact plank cost consumed")
	t.eq(attacker.inventory.count("bar_2"), bars_before - 2, "exact bar cost consumed")
	t.eq(owner.inventory.count("wood_1"), wood_before, "enemy action does not touch defender inventory")
	t.eq(server.territory.capture_target(site), duration_before - 10.0,
		"capture requirement is reduced by one tier")
	t.eq(server.territory.public_state(server.time)[0]["breach_cooldown"], OutpostBreach.BREACH_COOLDOWN,
		"public siege state includes remaining counterattack cooldown")
	t.check(attacker.dirty_inventory and attacker.dirty_character,
		"resource spending marks the character for saving")
	t.eq(server.cmd_outpost_breach(201, site_id, 4), first,
		"repeated RPC returns original receipt and never spends again")
	t.eq(attacker.inventory.count("plank_2"), planks_before - 2,
		"replayed command does not duplicate resource debits")
	t.eq(server.cmd_outpost_breach(201, site_id + 1, 4)["reason"], "request_conflict",
		"reused nonce cannot change target")
	t.eq(server.cmd_outpost_breach(201, site_id, 2)["reason"], "stale_request",
		"older commands cannot repeat previously executed siege action")
	var cooling: Dictionary = server.cmd_outpost_breach(201, site_id, 5)
	t.eq(cooling["reason"], "cooldown", "new request blocked during breach cooldown")
	t.eq(attacker.inventory.count("bar_2"), bars_before - 2, "cooldown spends no bars")
	t.eq(server.cmd_outpost_breach(201, site_id, 5), cooling,
		"failed request also remains idempotent")
	t.current = "owner, range, living party and material validation"
	t.eq(server.cmd_outpost_breach(101, site_id, 1)["reason"], "not_enemy",
		"owners cannot sabotage their own fort")
	_at(server, attacker, point + Vector2(6.0, 0.0))
	t.eq(server.cmd_outpost_breach(201, site_id, 6)["reason"], "too_far",
		"breach cannot originate outside four metres")
	_at(server, attacker, point)
	attacker_ally.survival.hurt(10000.0)
	t.eq(server.cmd_outpost_breach(201, site_id, 7)["reason"], "requires_party",
		"dead teammate cannot authorize a two-player siege")
	attacker_ally.survival.reset()
	server.time += OutpostBreach.BREACH_COOLDOWN + 1.0
	var second: Dictionary = server.cmd_outpost_breach(201, site_id, 8)
	t.check(bool(second.get("ok", false)), "second breach succeeds after cooldown")
	t.eq(site["fortification"], 0, "two breaches destroy two defense tiers")
	t.eq(server.territory.capture_target(site), Territory.CAPTURE_SECONDS,
		"fully broken fort uses base capture duration")
	t.eq(server.cmd_outpost_breach(201, site_id, 9)["reason"], "unfortified",
		"cannot spend resources to breach an already broken wall")
	var spent_total: int = planks_before - attacker.inventory.count("plank_2")
	t.eq(spent_total, 4, "two tier reductions consume exactly four planks")
	t.current = "unaffordable breach and session lifecycle"
	_at(server, owner, point)
	_at(server, attacker, point + Vector2(70.0, 0.0))
	_at(server, attacker_ally, point + Vector2(71.0, 0.0))
	t.check(server.cmd_outpost_fortify(101, site_id, 3)["ok"],
		"owner may rebuild defenses after enemies leave")
	_at(server, attacker, point)
	_at(server, attacker_ally, point + Vector2(1.0, 0.0))
	attacker.inventory.remove("bar_2", attacker.inventory.count("bar_2"))
	server.time += OutpostBreach.BREACH_COOLDOWN + 1.0
	t.eq(server.cmd_outpost_breach(201, site_id, 10)["reason"], "missing_materials",
		"breach fails when attacker has insufficient refined metal")
	t.eq(site["fortification"], 1, "failed purchase does not change wall")
	t.eq(attacker.inventory.count("plank_2"), planks_before - 4,
		"failed purchase does not consume additional planks")
	server.remove_player(201)
	t.check(not server.outpost_breach_requests.has(201),
		"disconnect clears replay state before peer ID can be recycled")
