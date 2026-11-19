extends RefCounted
## Server-verified Nakama guildmates cannot be hurt by friendly PvP attacks.
## Guilds are account-scoped and are NOT trusted from ENet or character saves.

const GuildIdentity = preload("res://scripts/shared/guild_identity.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const GameServer = preload("res://scripts/server/game_server.gd")

const RAVENS := "12345678-1234-1234-1234-123456789abc"
const WOLVES := "abcdefab-1234-1234-1234-abcdefabcdef"


func _guild(id: String, name: String = "Ravens", rank: int = 2) -> Dictionary:
	return {"ok": true, "guild_id": id, "guild_name": name, "rank": rank}


func run(t) -> void:
	t.current = "guild affiliation only accepts trusted Nakama-shaped results"
	t.eq(GuildIdentity.normalize({"ok": false, "guild_id": RAVENS}), {},
		"failed Nakama lookup never grants membership")
	t.eq(GuildIdentity.normalize({"guild_id": RAVENS}), {},
		"unverified response cannot assign guild ID")
	t.eq(GuildIdentity.normalize(_guild("anything")), {},
		"non-UUID guild IDs cannot become privileges")
	t.eq(GuildIdentity.normalize(_guild(RAVENS, "Ravens", 3)), {},
		"pending membership does not grant ally protection")
	t.eq(GuildIdentity.normalize(_guild(RAVENS, "Ravens", -1)), {},
		"invalid role cannot grant guild access")
	t.eq(GuildIdentity.normalize(_guild(RAVENS, "GuildNameOverMaximumCharactersAllowed")), {},
		"unbounded guild names are rejected")
	t.eq(GuildIdentity.normalize(_guild(RAVENS, "  Ravens  ")), {},
		"noncanonical guild names are rejected")
	t.eq(GuildIdentity.normalize({"ok": true, "guild_id": "", "guild_name": "", "rank": -1}),
		{"guild_id": "", "guild_name": "", "rank": -1},
		"valid guildless membership clears previous role")
	t.eq(GuildIdentity.normalize(_guild(RAVENS, "Ravens", 0))["rank"], 0,
		"guild founders have verified leader role")
	t.eq(GuildIdentity.normalize(_guild(RAVENS, "Ravens", 2))["guild_id"], RAVENS,
		"normal accepted members are recognized")

	t.current = "authenticated guildmates protected outside their party"
	var world := WorldGen.new(410)
	var server := GameServer.new(world, 410)
	var attacker = server.add_player(111, "Guild Vanguard", "account-111")
	var ally = server.add_player(112, "Guild Medic", "account-112")
	var rival = server.add_player(113, "Enemy", "account-113")
	var guest = server.add_player(114, "Guest")
	var origin := Vector2(700, 200)
	attacker.position = Vector3(origin.x, world.height_at(origin.x, origin.y), origin.y)
	ally.position = Vector3(origin.x + 1, world.height_at(origin.x + 1, origin.y), origin.y)
	rival.position = Vector3(origin.x + 2, world.height_at(origin.x + 2, origin.y), origin.y)
	guest.position = Vector3(origin.x + 3, world.height_at(origin.x + 3, origin.y), origin.y)
	t.check(world.zone_at(origin.x, origin.y) >= 2, "guild PvP checked in red/black PvP zone")
	t.check(not server.set_verified_guild(114, _guild(RAVENS)), "guests cannot claim guild membership")
	t.check(server.set_verified_guild(111, _guild(RAVENS, "Ravens", 0)), "server assigns leader from verified data")
	t.check(server.set_verified_guild(112, _guild(RAVENS)), "server assigns verified member")
	t.check(server.set_verified_guild(113, _guild(WOLVES, "Wolves", 2)), "enemy belongs to another guild")
	t.eq(server.parties.group_of(111), 0, "guild alliance requires no temporary party")
	t.check(GuildIdentity.same_guild(attacker, ally), "same verified guild is allied")
	t.check(not GuildIdentity.same_guild(attacker, rival), "different guild is hostile")
	t.check(not GuildIdentity.same_guild(guest, ally), "unauthenticated guest cannot join guild by name")

	var aim: Dictionary = server._find_hit(attacker, origin, Vector2.RIGHT, 4.0, false)
	t.eq(aim["kind"], "player", "server finds a real hostile PvP player")
	t.eq(int(aim["id"]), 113, "guildmate in front never intercepts attack on rival")
	var friendly_health: float = ally.survival.health
	server._damage_target(attacker, {"kind": "player", "id": 112}, 28.0)
	t.near(ally.survival.health, friendly_health, 0.001,
		"direct server damage respects guild protection")
	var enemy_health: float = rival.survival.health
	server._damage_target(attacker, {"kind": "player", "id": 113}, 28.0)
	t.check(rival.survival.health < enemy_health, "hostile guild survivor can still take PvP damage")

	t.current = "only public guild tags are visible and refresh revokes protection"
	var state: Dictionary = server.snapshot_for(111)
	t.eq(state["you"]["guild"]["name"], "Ravens", "owner sees real guild tag")
	t.eq(state["you"]["guild"]["rank"], 0, "owner alone sees its guild rank")
	var nearby: Dictionary = {}
	for entity in state["players"]:
		nearby[int(entity["id"])] = entity
	t.eq(nearby[112]["guild"]["name"], "Ravens", "other clients see verified guild name")
	t.check(not nearby[112].has("user_id"), "Nakama account ID stays server private")
	t.check(not nearby[112]["guild"].has("rank"), "other clients cannot see private guild rank")
	t.check(not state["you"]["guild"].has("user_id"), "self snapshot has no account UUID")
	t.check(not server.set_verified_guild(112, _guild(RAVENS, "Ravens", 3)),
		"pending membership cannot overwrite existing verified affiliation")
	t.eq(ally.guild_id, RAVENS, "malformed lookup cannot change current identity")
	t.check(server.set_verified_guild(112, {
		"ok": true, "guild_id": "", "guild_name": "", "rank": -1,
	}), "verified guild leave clears membership")
	t.check(not GuildIdentity.same_guild(attacker, ally), "former guildmate no longer has immunity")
	server._damage_target(attacker, {"kind": "player", "id": 112}, 10.0)
	t.check(ally.survival.health < friendly_health, "PvP damage resumes after verified guild leave")
	t.eq(server.snapshot_for(112)["you"]["guild"]["id"], "", "guildless player has no guild tag")
	server.remove_player(112)
	var replacement = server.add_player(112, "New account", "new-account")
	t.eq(replacement.guild_id, "", "reused peer ID cannot inherit old guild identity")
	t.eq(replacement.guild_rank, -1, "reused peer has no inherited guild permissions")
