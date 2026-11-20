extends RefCounted
## Durable guild ownership of outposts: an outpost captured by a guild party belongs to that guild for the hold, stays
## held when the party is gone, survives a server restart through the world checkpoint, and becomes neutral when the
## hold runs out.

const WorldGen = preload("res://scripts/shared/world_gen.gd")
const GameServer = preload("res://scripts/server/game_server.gd")
const Territory = preload("res://scripts/shared/territory_control.gd")
const WorldPersistence = preload("res://scripts/server/world_persistence.gd")

const RAVENS := "12345678-1234-1234-1234-123456789abc"


func run(t) -> void:
	var world := WorldGen.new(4242)
	var server := GameServer.new(world, 77)
	t.check(not server.territory.sites.is_empty(), "the seed has outposts")
	var site: Dictionary = server.territory.sites[0]

	t.current = "a held outpost with nobody of its guild around stays the guild's"
	site["owner"] = 0
	site["owner_guild"] = RAVENS
	site["owner_guild_name"] = "Ravens"
	site["guild_until"] = server.time + 120.0
	var events: Array = server.territory.tick(0.25, server.time, server.players, server.parties)
	t.eq(int(site["owner"]), 0, "no party is in command")
	t.eq(str(site["owner_guild"]), RAVENS, "the guild still holds it")
	t.eq(server.territory.public_state(server.time)[0]["guild"].get("id", ""), RAVENS, "its banner flies")
	t.check(float(server.territory.public_state(server.time)[0]["expires_in"]) > 100.0, "the hold's remaining time is shown")
	t.check(events.filter(func(e: Dictionary) -> bool: return e["type"] == "outpost_lost").is_empty(), "nothing is lost yet")

	t.current = "the hold survives a restart through the world checkpoint"
	var checkpoint: Dictionary = WorldPersistence.capture(server)
	t.eq(checkpoint["outposts"].size(), 1, "the checkpoint carries the hold")
	t.check(float(checkpoint["outposts"][0]["remaining"]) > 100.0, "with its remaining time")
	var restarted := GameServer.new(WorldGen.new(4242), 78)
	t.check(WorldPersistence.restore(restarted, JSON.parse_string(JSON.stringify(checkpoint))), "a fresh server restores it")
	var again: Dictionary = restarted.territory.sites[0]
	t.eq(str(again["owner_guild"]), RAVENS, "the restarted world knows the holding guild")
	t.eq(str(again["owner_guild_name"]), "Ravens", "and its name")
	t.check(float(again["guild_until"]) - restarted.time > 100.0, "for the time that was left")

	t.current = "a checkpoint without holds (older format) still loads"
	var old_format: Dictionary = checkpoint.duplicate(true)
	old_format.erase("outposts")
	t.check(WorldPersistence.restore(GameServer.new(WorldGen.new(4242), 79), old_format), "three-field checkpoints are accepted")

	t.current = "forged or broken holds are refused as a whole"
	for broken in [
			{"id": 999, "guild": RAVENS, "name": "Ravens", "remaining": 60.0},
			{"id": int(site["id"]), "guild": "", "name": "Ravens", "remaining": 60.0},
			{"id": int(site["id"]), "guild": RAVENS, "name": "Ravens", "remaining": Territory.HOLD_SECONDS + 1.0},
			{"id": int(site["id"]), "guild": RAVENS, "name": "Ravens", "remaining": 60.0, "owner": 7}]:
		var forged: Dictionary = checkpoint.duplicate(true)
		forged["outposts"] = [broken]
		t.check(WorldPersistence.validate(forged, GameServer.new(WorldGen.new(4242), 80)).is_empty(), "rejected: %s" % str(broken))
	var twice: Dictionary = checkpoint.duplicate(true)
	twice["outposts"] = [checkpoint["outposts"][0], checkpoint["outposts"][0]]
	t.check(WorldPersistence.validate(twice, GameServer.new(WorldGen.new(4242), 81)).is_empty(), "a site cannot be held twice")

	t.current = "when the hold runs out the outpost turns neutral and forgets its guild"
	site["guild_until"] = server.time + 0.1
	events = server.territory.tick(0.25, server.time + 0.5, server.players, server.parties)
	t.eq(str(site["owner_guild"]), "", "the guild hold is cleared")
	t.eq(server.territory.public_state(server.time + 0.5)[0]["guild"], {}, "no former owner is shown")
	t.check(not events.filter(func(e: Dictionary) -> bool: return e["type"] == "outpost_lost").is_empty(), "the loss is announced")
	t.eq(WorldPersistence.capture(server)["outposts"].size(), 0, "nothing more to save")
