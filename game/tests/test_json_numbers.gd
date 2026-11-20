extends RefCounted
## A character that went through JSON (Nakama storage) must load again: every validator is strict about integers, and
## JSON turns 3 into 3.0. The gateway restores whole numbers as integers; this pins the whole round trip.

const Defs = preload("res://scripts/shared/defs.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const GameServer = preload("res://scripts/server/game_server.gd")
const Gateway = preload("res://scripts/server/nakama_gateway.gd")


func run(t) -> void:
	t.current = "whole numbers after JSON"
	var sample: Dictionary = Gateway.whole_numbers_as_ints(JSON.parse_string(JSON.stringify({"a": 3, "b": 2.5, "c": [1, 2.0, {"d": 7.0}], "e": "9", "f": true})))
	t.eq(typeof(sample["a"]), TYPE_INT, "a whole number is an integer again")
	t.eq(typeof(sample["b"]), TYPE_FLOAT, "a fraction stays a float")
	t.eq(typeof(sample["c"][1]), TYPE_INT, "also inside arrays")
	t.eq(typeof(sample["c"][2]["d"]), TYPE_INT, "and nested dictionaries")
	t.eq(sample["e"], "9", "text is left alone")
	t.eq(sample["f"], true, "booleans are left alone")
	t.eq(typeof(Gateway.whole_numbers_as_ints(NAN)), TYPE_FLOAT, "NaN stays NaN")
	t.eq(typeof(Gateway.whole_numbers_as_ints(1e300)), TYPE_FLOAT, "huge floats are not turned into integers")

	t.current = "a full character survives storage"
	var server := GameServer.new(WorldGen.new(77), 1)
	var player = server.add_player(5, "Roundtrip", "uid-roundtrip")
	# Touch every kind of saved state so each validator has something to read.
	player.inventory.add("silver", 321)
	player.inventory.add("club_2", 1)
	player.inventory.equip("club_2")
	player.kills = 12
	player.deaths = 3
	player.arena_rating = 1337
	player.arena_wins = 4
	player.arena_losses = 2
	player.meal_tier = 2
	player.meal_seconds = 30.0
	player.skills.add_xp("melee", 900)
	player.survival.bleeding = 12.0
	player.survival.fracture = 8.0
	player.survival.infection = 15.0
	var document: Dictionary = server.character_data(player)
	t.check(server.valid_character_data(document), "the live character is valid")
	var stored: Variant = JSON.parse_string(JSON.stringify(document))
	t.check(not server.valid_character_data(stored), "straight out of JSON it is not (that is the trap)")
	var restored: Dictionary = Gateway.whole_numbers_as_ints(stored)
	t.check(server.valid_character_data(restored), "after the gateway restored the integers it is valid")
	var again = server.add_player(6, "Again", "uid-again", restored)
	t.eq(again.arena_rating, 1337, "arena rating survived")
	t.eq(again.meal_tier, 2, "meal tier survived")
	t.eq(again.kills, 12, "kills survived")
	t.check(again.inventory.count("silver") >= 321, "silver survived")
	t.check(again.skills.xp["melee"] > 0, "skills survived")
