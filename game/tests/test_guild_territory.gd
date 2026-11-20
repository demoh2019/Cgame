extends RefCounted
## Server-owned clan banners atop temporary party outposts.
## Guild identity comes from verified Nakama membership, never client claims.

const WorldGen = preload("res://scripts/shared/world_gen.gd")
const GameServer = preload("res://scripts/server/game_server.gd")
const Territory = preload("res://scripts/shared/territory_control.gd")
const GuildTerritory = preload("res://scripts/shared/guild_territory.gd")

const RAVENS := "12345678-1234-1234-1234-123456789abc"
const WOLVES := "abcdefab-1234-1234-1234-abcdefabcdef"


func _guild(id: String, name: String = "Ravens") -> Dictionary:
	return {"ok": true, "guild_id": id, "guild_name": name, "rank": 2}


func _at(server, player, place: Vector2) -> void:
	player.position = Vector3(place.x, server.world.height_at(place.x, place.y), place.y)


func _advance(server, seconds: float) -> void:
	for step in range(int(ceil(seconds / 0.25))):
		server.time += 0.25
		server.territory.tick(0.25, server.time, server.players, server.parties)


func run(t) -> void:
	t.current = "verified homogeneous party earns a live guild banner"
	var world := WorldGen.new(205)
	var server := GameServer.new(world, 205)
	t.check(server.territory.sites.size() >= 1, "a siege outpost exists in the seeded world")
	if server.territory.sites.is_empty():
		return
	var site: Dictionary = server.territory.sites[0]
	var id: int = int(site["id"])
	var center := Vector2(float(site["x"]), float(site["z"]))
	var lead = server.add_player(101, "Raven leader", "guild-user-101")
	var ally = server.add_player(102, "Raven ally", "guild-user-102")
	var wing = server.add_player(103, "Raven outsider", "guild-user-103")
	var wing_ally = server.add_player(104, "Raven wingman", "guild-user-104")
	var guest = server.add_player(105, "Guest")
	_at(server, lead, center)
	_at(server, ally, center + Vector2(1.0, 0.0))
	_at(server, wing, center + Vector2(60.0, 0.0))
	_at(server, wing_ally, center + Vector2(61.0, 0.0))
	_at(server, guest, center + Vector2(62.0, 0.0))
	for peer_id in [101, 102, 103, 104]:
		t.check(server.set_verified_guild(peer_id, _guild(RAVENS)), "accepted Nakama guild member joins the session")
	t.check(not server.set_verified_guild(105, _guild(RAVENS)), "guest cannot forge a Raven guild tag")
	t.check(server.cmd_party_invite(101, 102)["ok"], "defenders form a normal party")
	t.check(server.cmd_party_accept(102)["ok"], "second defender joins")
	t.check(server.cmd_party_invite(103, 104)["ok"], "other guildmates form an independent party")
	t.check(server.cmd_party_accept(104)["ok"], "independent guild party is real")
	var owner_party: int = server.parties.group_of(101)
	var wing_party: int = server.parties.group_of(103)
	t.check(owner_party > 0 and wing_party > 0 and owner_party != wing_party,
		"guild allies need not share a party ID")
	_advance(server, Territory.CAPTURE_SECONDS + 1.0)
	t.eq(int(site["owner"]), owner_party, "defenders have actually captured the point")
	var banner: Dictionary = GuildTerritory.owner_banner(site, server.players, server.parties)
	t.eq(banner, {"id": RAVENS, "name": "Ravens"}, "capture has verified clan identity")
	t.eq(server.snapshot_for(101)["outposts"][0]["guild"], banner,
		"public network snapshot shows clan banner")
	t.eq(server.snapshot_for(103)["outposts"][0]["guild"], banner,
		"other parties see the same public clan tag")
	t.check(not server.snapshot_for(103)["outposts"][0].has("user_id"),
		"no character account identifier is exposed in banner")

	t.current = "same-guild side does not contest or attack owner's defenses"
	_at(server, wing, center + Vector2(2.0, 0.0))
	_at(server, wing_ally, center + Vector2(3.0, 0.0))
	_advance(server, 0.25)
	var occupants: Dictionary = server.territory._occupied_groups(site, server.players, server.parties)
	t.eq(occupants.size(), 1, "two different parties of one verified guild form one defensive side")
	t.eq(occupants.get(owner_party, 0), 4, "all verified guild allies contribute to defense")
	t.check(not bool(site["contested"]), "guildmates do not contest their own flag")
	t.check(server.territory.has_rally_bonus(103, wing.position, server.parties, server.time, server.players),
		"outside-party guildmate receives local rally stamina")
	t.check(not server.territory.has_rally_bonus(103, wing.position + Vector3(80, 0, 0),
		server.parties, server.time, server.players), "guild rally bonus is not global")
	var guest_original: Vector3 = guest.position
	_at(server, guest, center + Vector2(4.0, 0.0))
	t.check(not server.territory.has_rally_bonus(105, guest.position, server.parties,
		server.time, server.players), "unauthenticated guest standing at flag cannot receive clan rally")
	guest.position = guest_original
	wing.inventory.add("cloth_2", 3)
	wing.inventory.add("silver", 40)
	wing.inventory.add("plank_2", 3)
	wing.inventory.add("bar_2", 3)
	var saved_cloth: int = wing.inventory.count("cloth_2")
	var saved_bars: int = wing.inventory.count("bar_2")
	t.eq(server.cmd_siege_declare(103, id, 1)["reason"], "guild_ally",
		"guildmates cannot pay to declare a false war against their own banner")
	t.eq(server.cmd_outpost_breach(103, id, 1)["reason"], "guild_ally",
		"guildmates cannot use a breach command against their own clan")
	t.eq(wing.inventory.count("cloth_2"), saved_cloth, "failed guild war does not spend cloth")
	t.eq(wing.inventory.count("bar_2"), saved_bars, "failed guild breach does not spend bars")
	t.check(not server.siege_contracts.active.has(id), "allied siege creates no war contract")

	t.current = "revocation or mixed guilds remove privileges immediately"
	t.check(server.set_verified_guild(102, {
		"ok": true, "guild_id": "", "guild_name": "", "rank": -1
	}), "server can revoke confirmed membership")
	t.eq(server.snapshot_for(101)["outposts"][0]["guild"], {},
		"a formerly homogeneous party loses its banner when member leaves Nakama guild")
	_advance(server, 0.25)
	t.check(bool(site["contested"]), "wing party becomes a separate contesting side")
	t.check(not server.territory.has_rally_bonus(103, wing.position,
		server.parties, server.time, server.players),
		"outside-party rally benefit is revoked with banner")
	t.check(server.set_verified_guild(102, _guild(RAVENS)), "backend revalidation can restore affiliation")
	t.eq(server.snapshot_for(101)["outposts"][0]["guild"]["id"], RAVENS,
		"revalidated ownership has its banner again")
	_advance(server, 0.25)
	t.check(not bool(site["contested"]), "new trusted identity restores the common defensive side")
	t.check(server.set_verified_guild(102, _guild(WOLVES, "Wolves")),
		"a genuinely different guild can join the same temporary party")
	t.eq(GuildTerritory.owner_banner(site, server.players, server.parties), {},
		"mixed-guild party never impersonates a single clan")
	t.check(server.set_verified_guild(102, _guild(RAVENS)), "restore defender affiliation")
	# Clearing the actual party invalidates the banner even before the next tick.
	t.check(server.cmd_party_leave(102)["ok"], "defender's temporary party disbands")
	t.eq(GuildTerritory.owner_banner(site, server.players, server.parties), {},
		"disbanding the owner party immediately removes clan status")
	_advance(server, 0.25)
	t.eq(site["owner"], 0, "unowned flag is neutral after party disband")
	t.eq(server.snapshot_for(101)["outposts"][0]["guild"], {},
		"neutral outpost leaks no former owner guild information")

	t.current = "guild banner remains session-only, never a stored character field"
	t.check(not server.character_data(lead).has("guild"),
		"character saves cannot inject persistent client-controlled guild identity")
	t.eq(GuildTerritory.party_banner(999999, server.players, server.parties), {},
		"unknown party cannot fabricate a guild banner")
	t.eq(server.territory.public_state(server.time)[0]["guild"], {},
		"offline snapshot without trusted player roster never claims guild ownership")
