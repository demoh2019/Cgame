extends RefCounted
## A full world checkpoint (market bids, farm plots, guild banks, alliances) must load
## on a fresh server. Guards against validators falling behind new saved sections.

const Persist = preload("res://scripts/server/world_persistence.gd")
const Inventory = preload("res://scripts/shared/inventory.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const GameServer = preload("res://scripts/server/game_server.gd")

const PATH := "user://albion_after_world_roundtrip_test.json"
const G1 := "11111111-1111-1111-1111-111111111111"
const G2 := "22222222-2222-2222-2222-222222222222"


func run(t) -> void:
	t.current = "full checkpoint round trip"
	var server := GameServer.new(WorldGen.new(214), 314)
	server.farm_plots[server.new_id()] = {"account": "acct-f", "owner_name": "F", "crop": "wheat",
		"x": 30.0, "z": 5.0, "planted": server.time - 100.0, "grow": 1500.0}
	server.guild_banks[G1] = {"plank_2": 7}
	server.guild_alliances[server.new_id()] = {"guilds": {G1: "Iron", G2: "Ash"}}
	server._rebuild_alliance_index()
	server.market_bids[server.new_id()] = {"account": "acct-b", "buyer_name": "B", "item": "wood_1",
		"remaining": 5, "price": 3, "expires": server.time + 1000.0}
	t.check(Persist.save(server, PATH), "checkpoint written")
	var fresh := GameServer.new(WorldGen.new(214), 315)
	t.check(Persist.load(fresh, PATH), "checkpoint with every section loads on a fresh server")
	t.eq(fresh.farm_plots.size(), 1, "farm plot restored")
	t.eq(int(fresh.guild_banks.get(G1, {}).get("plank_2", 0)), 7, "guild bank restored")
	t.check(fresh._guild_friendly_ids(G1, G2) if fresh.has_method("_guild_friendly_ids") else int(fresh.guild_to_alliance.get(G1, -1)) == int(fresh.guild_to_alliance.get(G2, -2)), "alliance restored")
	t.eq(fresh.market_bids.size(), 1, "buy order restored")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))
