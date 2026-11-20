extends RefCounted
## Field refining/crafting: actual inventory transactions, verified guild allies,
## instant siege contest denial, expiry, distance and unowned stations.
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const GameServer = preload("res://scripts/server/game_server.gd")
const Territory = preload("res://scripts/shared/territory_control.gd")
const GuildTerritory = preload("res://scripts/shared/guild_territory.gd")

const CLAN_ID := "12345678-1234-1234-1234-123456789abc"


func _at(server, player, x: float, z: float) -> void:
	player.position = Vector3(x, server.world.height_at(x, z), z)


func run(t) -> void:
	t.current = "outpost workbench requires a captured living group"
	var server := GameServer.new(WorldGen.new(205), 205)
	t.check(server.territory.sites.size() >= 1, "seeded world has a frontier flag")
	if server.territory.sites.is_empty():
		return
	var site: Dictionary = server.territory.sites[0]
	var x: float = float(site["x"])
	var z: float = float(site["z"])
	var owner = server.add_player(101, "Field Smith", "field-user-101")
	var defender = server.add_player(102, "Field Defender", "field-user-102")
	var guildmate = server.add_player(103, "Field Guildmate", "field-user-103")
	var rival = server.add_player(104, "Enemy Smith")
	_at(server, owner, x + 3.0, z)
	_at(server, defender, x + 4.0, z)
	_at(server, guildmate, x + 80.0, z)
	_at(server, rival, x + 80.0, z)
	owner.inventory.add("wood_1", 12)
	guildmate.inventory.add("wood_1", 8)
	t.eq(server.cmd_craft(101, "plank_1").get("reason", ""), "no_station",
		"uncaptured flag never serves as a workbench")
	t.eq(owner.inventory.count("wood_1"), 12, "failed craft does not spend wood")
	t.check(server.cmd_party_invite(101, 102)["ok"], "real owner party forms")
	t.check(server.cmd_party_accept(102)["ok"], "real defender joins")
	var party_id: int = server.parties.group_of(101)
	t.check(party_id > 0, "server issues a party ID")
	site["owner"] = party_id
	site["until"] = server.time + Territory.HOLD_SECONDS
	t.check(server.territory.has_field_workbench(101, server.players, server.parties, server.time),
		"real owner beside captured flag can use field workbench")
	var crafted: Dictionary = server.cmd_craft(101, "plank_1")
	t.check(bool(crafted.get("ok", false)), "crafting works far from starter hub")
	t.eq(owner.inventory.count("plank_1"), 1, "actual refined plank deposited")
	t.eq(owner.inventory.count("wood_1"), 10, "two raw wood consumed")
	t.eq(server.cmd_craft(103, "plank_1").get("reason", ""), "no_station",
		"solo stranger cannot use another group's field bench")

	t.current = "fully verified same-guild allies can refine without sharing party"
	var trusted := {"ok": true, "guild_id": CLAN_ID, "guild_name": "Field Smiths", "rank": 2}
	for peer_id in [101, 102, 103]:
		t.check(server.set_verified_guild(peer_id, trusted), "backend confirms a real clan member")
	_at(server, guildmate, x + 3.0, z)
	t.eq(GuildTerritory.owner_banner(site, server.players, server.parties)["id"], CLAN_ID,
		"banner belongs to fully verified owning party")
	t.check(server.territory.has_field_workbench(103, server.players, server.parties, server.time),
		"confirmed cross-party guildmate can use field bench")
	t.check(bool(server.cmd_craft(103, "plank_1").get("ok", false)),
		"cross-party guild crafter can create real materials")
	t.eq(guildmate.inventory.count("plank_1"), 1, "guildmate receives crafted output")
	t.eq(guildmate.inventory.count("wood_1"), 6, "guildmate paid actual inputs")
	_at(server, guildmate, x + 80.0, z)
	t.check(not server.territory.has_field_workbench(103, server.players, server.parties, server.time),
		"guild privilege is local, not a remote crafting cheat")

	t.current = "enemy presence contests and disables forge instantly"
	_at(server, rival, x + 2.0, z)
	t.check(not server.territory.has_field_workbench(101, server.players, server.parties, server.time),
		"hostile occupancy disables the workbench without waiting for tick")
	var wood_before: int = owner.inventory.count("wood_1")
	t.eq(server.cmd_craft(101, "plank_1").get("reason", ""), "no_station",
		"contested bench refuses crafting even with materials")
	t.eq(owner.inventory.count("wood_1"), wood_before,
		"denied craft does not spend the owner's inventory")
	_at(server, rival, x + 80.0, z)
	t.check(server.territory.has_field_workbench(101, server.players, server.parties, server.time),
		"forge reopens after enemy retreats")

	t.current = "expired, unowned, disconnected and nonfinite locations are invalid"
	site["until"] = server.time
	t.eq(server.cmd_craft(101, "plank_1").get("reason", ""), "no_station",
		"expired territory never authorizes remote crafting")
	site["until"] = server.time + Territory.HOLD_SECONDS
	site["owner"] = 0
	t.eq(server.cmd_craft(101, "plank_1").get("reason", ""), "no_station",
		"neutral flag removes crafting rights")
	site["owner"] = party_id
	owner.position = Vector3.INF
	t.check(not server.territory.has_field_workbench(101, server.players, server.parties, server.time),
		"invalid position cannot authorize virtual station")
	_at(server, owner, x + 3.0, z)
	t.check(server.cmd_party_leave(102)["ok"], "party can disband")
	t.eq(server.cmd_craft(101, "plank_1").get("reason", ""), "no_station",
		"disbanded owning party cannot keep its bench")
