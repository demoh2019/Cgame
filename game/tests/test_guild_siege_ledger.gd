extends RefCounted
## Pure server-origin validation for the durable Nakama siege honor ledger.
## Integration tests exercise the real CAS receipt RPC independently.
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const GameServer = preload("res://scripts/server/game_server.gd")
const Territory = preload("res://scripts/shared/territory_control.gd")
const GuildSiegeLedger = preload("res://scripts/shared/guild_siege_ledger.gd")

const RAVENS := "12345678-1234-1234-1234-123456789abc"
const WOLVES := "abcdefab-1234-1234-1234-abcdefabcdef"


func _guild(id: String, name: String) -> Dictionary:
	return {"ok": true, "guild_id": id, "guild_name": name, "rank": 2}


func run(t) -> void:
	t.current = "only validated server siege victories can become guild ledger records"
	var sim := GameServer.new(WorldGen.new(205), 205)
	t.check(not sim.territory.sites.is_empty(), "test world provides at least one outpost")
	if sim.territory.sites.is_empty():
		return
	var site: Dictionary = sim.territory.sites[0]
	var x: float = float(site["x"])
	var z: float = float(site["z"])
	var captain = sim.add_player(101, "Captain", "account-101")
	var soldier = sim.add_player(102, "Soldier", "account-102")
	captain.position = Vector3(x, sim.world.height_at(x, z), z)
	soldier.position = Vector3(x + 1.0, sim.world.height_at(x + 1.0, z), z)
	t.check(sim.set_verified_guild(101, _guild(RAVENS, "Ravens")), "captain's Nakama membership is accepted")
	t.check(sim.set_verified_guild(102, _guild(RAVENS, "Ravens")), "soldier's Nakama membership is accepted")
	t.check(sim.cmd_party_invite(101, 102)["ok"], "authenticated members form party")
	t.check(sim.cmd_party_accept(102)["ok"], "second member joins")
	for step in range(int(Territory.CAPTURE_SECONDS / 0.25) + 4):
		sim.time += 0.25
		sim.territory.tick(0.25, sim.time, sim.players, sim.parties)
	var group_id: int = sim.parties.group_of(101)
	t.eq(int(site["owner"]), group_id, "party actually controls the outpost")
	var event: Dictionary = {
		"type": "siege_contract_result", "result": "won",
		"site": int(site["id"]), "attacker": group_id,
	}
	var record: Dictionary = GuildSiegeLedger.eligible_victory(event, sim)
	t.eq(record.get("guild_id", ""), RAVENS, "only same verified guild earns durable honor")
	t.eq(record.get("guild_name", ""), "Ravens", "guild name is server-verified")
	t.eq(record.get("site", -1), int(site["id"]), "site ID stays authoritative")
	t.eq(record.get("world_seed", -1), 205, "world seed is included in the ledger record")
	t.eq(GuildSiegeLedger.eligible_victory({"type": "siege_contract_declared", "result": "won"}, sim), {},
		"a paid siege declaration is not a victory")
	t.eq(GuildSiegeLedger.eligible_victory({
		"type": "siege_contract_result", "result": "lost",
		"site": int(site["id"]), "attacker": group_id,
	}, sim), {}, "losing a siege earns nothing")
	t.eq(GuildSiegeLedger.eligible_victory(event.merged({"attacker": group_id + 99}), sim), {},
		"false attacker cannot collect another party's victory")
	t.eq(GuildSiegeLedger.eligible_victory(event.merged({"site": 999}), sim), {},
		"unknown site cannot be stored")
	t.eq(GuildSiegeLedger.eligible_victory(event.merged({"site": "1"}), sim), {},
		"client-shaped string ID cannot be silently coerced")
	sim.guild_siege_wins[RAVENS] = 13
	t.eq(sim.snapshot_for(101)["you"]["guild_siege_wins"], 13,
		"verified player sees the historical Nakama guild score")
	t.eq(sim.snapshot_for(102)["you"]["guild_siege_wins"], 13,
		"another member sees the same guild score")

	t.current = "membership and owner changes immediately remove ledger eligibility"
	t.check(sim.set_verified_guild(102, _guild(WOLVES, "Wolves")), "member can change verified guild")
	t.eq(GuildSiegeLedger.eligible_victory(event, sim), {},
		"a mixed party is never credited to a single guild")
	t.check(sim.set_verified_guild(102, _guild(RAVENS, "Ravens")), "server may reverify guild membership")
	t.eq(GuildSiegeLedger.eligible_victory(event, sim).get("guild_id", ""), RAVENS,
		"eligibility returns with a homogeneous verified party")
	site["owner"] = 0
	t.eq(GuildSiegeLedger.eligible_victory(event, sim), {},
		"historical event cannot score after the party loses the flag")
