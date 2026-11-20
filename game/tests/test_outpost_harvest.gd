extends RefCounted
## Captured outposts should fuel the real crafting economy without free rewards.
const Defs = preload("res://scripts/shared/defs.gd")
const GameServer = preload("res://scripts/server/game_server.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const Territory = preload("res://scripts/shared/territory_control.gd")

const GUILD := "12345678-1234-1234-1234-123456789abc"


func _place(server, player, x: float, z: float) -> void:
	player.position = Vector3(x, server.world.height_at(x, z), z)


func run(t) -> void:
	t.current = "outpost harvest ownership and proximity"
	var server := GameServer.new(WorldGen.new(205), 205)
	t.check(not server.territory.sites.is_empty(), "world has an outpost")
	if server.territory.sites.is_empty():
		return
	var site: Dictionary = server.territory.sites[0]
	var x: float = float(site["x"])
	var z: float = float(site["z"])
	var lead = server.add_player(101, "Harvest Lead", "harvest-user-101")
	var ally = server.add_player(102, "Harvest Ally", "harvest-user-102")
	var wing = server.add_player(103, "Harvest Wing", "harvest-user-103")
	var rival = server.add_player(104, "Harvest Rival")
	_place(server, lead, x + 5.0, z)
	_place(server, ally, x + 3.0, z)
	_place(server, wing, x + 6.0, z)
	_place(server, rival, x + 180.0, z)
	var node: Dictionary = {"id": 999991, "kind": "tree", "tier": 3,
		"x": x + 5.0, "z": z}
	t.eq(server.territory.harvest_bonus(101, node, server.players,
		server.parties, server.time, server.world), 0,
		"neutral outpost provides no economic bonus")
	t.check(server.cmd_party_invite(101, 102)["ok"], "leader invites a real party")
	t.check(server.cmd_party_accept(102)["ok"], "second survivor joins party")
	var owner: int = server.parties.group_of(101)
	t.check(owner > 0, "a server group ID exists")
	site["owner"] = owner
	site["until"] = server.time + 900.0
	t.eq(server.territory.harvest_bonus(101, node, server.players,
		server.parties, server.time, server.world), 1,
		"capturing party harvests one extra resource near its outpost")
	t.eq(server.territory.harvest_bonus(103, node, server.players,
		server.parties, server.time, server.world), 0,
		"outsiders have no owner privileges")

	t.current = "only validated guild membership enables cross-party bonuses"
	var membership := {"ok": true, "guild_id": GUILD,
		"guild_name": "Harvesters", "rank": 2}
	for member in [101, 102, 103]:
		t.check(server.set_verified_guild(member, membership),
			"server accepts verified Nakama guild identity")
	_place(server, wing, x + 5.0, z)
	t.eq(server.territory.harvest_bonus(103, node, server.players,
		server.parties, server.time, server.world), 1,
		"verified guildmate can gather without sharing the capture party")
	t.eq(server.territory.harvest_bonus(104, node, server.players,
		server.parties, server.time, server.world), 0,
		"non-member cannot inherit a verified clan banner")

	t.current = "contesting interrupts the bonus immediately"
	_place(server, rival, x + 2.0, z)
	t.eq(server.territory.harvest_bonus(101, node, server.players,
		server.parties, server.time, server.world), 0,
		"hostile at flag shuts down bonus without waiting for the territory tick")
	t.eq(server.territory.harvest_bonus(103, node, server.players,
		server.parties, server.time, server.world), 0,
		"even outside-party guildmates lose their bonus during a contest")
	_place(server, rival, x + 180.0, z)
	t.eq(server.territory.harvest_bonus(101, node, server.players,
		server.parties, server.time, server.world), 1, "clearing the contest restores benefit")

	t.current = "only dangerous-zone raw material nodes receive the benefit"
	var berry: Dictionary = node.duplicate()
	berry["kind"] = "berry"
	t.eq(server.territory.harvest_bonus(101, berry, server.players,
		server.parties, server.time, server.world), 0, "berries are never multiplied")
	var far: Dictionary = node.duplicate()
	far["x"] = x + Territory.HARVEST_RADIUS + 12.0
	_place(server, lead, float(far["x"]), float(far["z"]))
	t.eq(server.territory.harvest_bonus(101, far, server.players,
		server.parties, server.time, server.world), 0, "bonus does not extend beyond outpost region")
	_place(server, lead, x + 5.0, z)
	var wrong_position: Dictionary = node.duplicate()
	wrong_position["x"] = x + 40.0
	t.eq(server.territory.harvest_bonus(101, wrong_position, server.players,
		server.parties, server.time, server.world), 0,
		"player must physically be at harvested node")

	t.current = "real inventory gain and bounded payout"
	var item: String = "wood_3"
	var base_count: int = lead.inventory.count(item)
	server.rng.seed = 123456
	server._finish_gather(lead, node)
	var boosted: int = lead.inventory.count(item) - base_count
	var boosted_events: Array = server.drain_events()
	var bonus_paid := -1
	for event in boosted_events:
		if event.get("type", "") == "gathered":
			bonus_paid = int(event.get("outpost_bonus", -1))
	t.eq(bonus_paid, 1, "server event reports exactly one earned outpost bonus")
	t.check(boosted >= int(Defs.node_info("tree")["amount"]) + 1,
		"gather completion actually deposits the extra material")
	site["owner"] = 0
	server.rng.seed = 123456
	server._finish_gather(lead, node)
	var unboosted: int = lead.inventory.count(item) - base_count - boosted
	t.eq(boosted - unboosted, 1,
		"same RNG, node and player yield exactly one additional item when flag owned")
	t.eq(server.territory.harvest_bonus(101, node, server.players,
		server.parties, server.time, server.world), 0, "lost flag instantly removes bonus")

	t.current = "expired ownership and revocation remove benefits"
	site["owner"] = owner
	site["until"] = server.time
	t.eq(server.territory.harvest_bonus(101, node, server.players,
		server.parties, server.time, server.world), 0, "expired capture grants nothing")
	site["until"] = server.time + 900.0
	t.check(server.set_verified_guild(102, {"ok": true, "guild_id": "",
		"guild_name": "", "rank": -1}), "server revokes guild affiliation")
	t.eq(server.territory.harvest_bonus(103, node, server.players,
		server.parties, server.time, server.world), 0,
		"mixed or revoked owner party immediately loses guild-wide benefits")
	t.check(server.cmd_party_leave(102)["ok"], "capture party disbands")
	t.eq(server.territory.harvest_bonus(101, node, server.players,
		server.parties, server.time, server.world), 0, "disbanded owner party grants nothing")
