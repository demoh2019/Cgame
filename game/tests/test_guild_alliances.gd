extends RefCounted
## Albion-style guild alliances: leader invites, acceptance, no friendly fire, leaving, persistence.

const GuildAlliances = preload("res://scripts/shared/guild_alliances.gd")
const Inventory = preload("res://scripts/shared/inventory.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const GameServer = preload("res://scripts/server/game_server.gd")
const WorldPersistence = preload("res://scripts/server/world_persistence.gd")

const G1 := "11111111-1111-1111-1111-111111111111"
const G2 := "22222222-2222-2222-2222-222222222222"


func run(t) -> void:
	t.current = "friendliness rules"
	t.check(GuildAlliances.friendly("a", "a", {}), "same guild is friendly")
	t.check(not GuildAlliances.friendly("a", "b", {}), "different guilds are not")
	t.check(GuildAlliances.friendly("a", "b", {"a": 7, "b": 7}), "allied guilds are friendly")
	t.check(not GuildAlliances.friendly("", "", {}), "guildless players are never friendly")

	var world = WorldGen.new(6611)
	var server := GameServer.new(world, 51)
	var hub := Vector3(9.0, world.height_at(9.0, 0.0), 0.0)
	var lead1 = server.add_player(1501, "LeadOne", "acct-l1")
	var lead2 = server.add_player(1502, "LeadTwo", "acct-l2")
	var grunt = server.add_player(1503, "Grunt", "acct-g2")
	for p in [lead1, lead2, grunt]:
		p.inventory = Inventory.new()
		p.position = hub
	server.set_verified_guild(1501, {"ok": true, "guild_id": G1, "guild_name": "Iron", "rank": 0})
	server.set_verified_guild(1502, {"ok": true, "guild_id": G2, "guild_name": "Ash", "rank": 0})
	server.set_verified_guild(1503, {"ok": true, "guild_id": G2, "guild_name": "Ash", "rank": 2})

	t.current = "invite and accept"
	t.eq(server.cmd_alliance(1503, "invite", 1501).get("reason"), "leaders_only", "members cannot invite")
	t.eq(server.cmd_alliance(1501, "invite", 1503).get("reason"), "target_not_leader", "invite goes to a leader")
	t.check(bool(server.cmd_alliance(1501, "invite", 1502).get("ok", false)), "leader invites leader")
	var accepted: Dictionary = server.cmd_alliance(1502, "accept")
	t.check(bool(accepted.get("ok", false)), "invited leader accepts")
	t.eq((accepted["allied_guilds"] as Array).size(), 2, "two guilds in the alliance")
	t.check(server._guild_friendly(lead1, grunt), "allied members are friendly")

	t.current = "persistence and leaving"
	var saved: Dictionary = WorldPersistence.capture(server)
	t.eq((saved["alliances"] as Array).size(), 1, "alliance saved with the world")
	t.check(bool(server.cmd_alliance(1502, "leave").get("ok", false)), "leader leaves")
	t.check(not server._guild_friendly(lead1, grunt), "former allies are enemies again")
	t.eq(server.guild_alliances.size(), 0, "a lone guild is not an alliance")
