extends RefCounted
## Albion-style guild bank: verified members deposit, officers withdraw, vaults persist.

const GuildBank = preload("res://scripts/shared/guild_bank.gd")
const Inventory = preload("res://scripts/shared/inventory.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const GameServer = preload("res://scripts/server/game_server.gd")
const WorldPersistence = preload("res://scripts/server/world_persistence.gd")


func run(t) -> void:
	t.current = "rules"
	t.check(GuildBank.can_withdraw(0) and GuildBank.can_withdraw(1), "leader and officers withdraw")
	t.check(not GuildBank.can_withdraw(2) and not GuildBank.can_withdraw(-1), "members and outsiders cannot")
	t.eq(GuildBank.deposit_refusal({}, "nope", 1), "invalid_item", "only real items")

	var world = WorldGen.new(5577)
	var server := GameServer.new(world, 41)
	var hub := Vector3(9.0, world.height_at(9.0, 0.0), 0.0)
	var member = server.add_player(1401, "Member", "acct-m")
	var officer = server.add_player(1402, "Officer", "acct-o")
	var outsider = server.add_player(1403, "Outsider", "acct-x")
	for p in [member, officer, outsider]:
		p.inventory = Inventory.new()
		p.position = hub
	t.check(server.set_verified_guild(1401, {"ok": true, "guild_id": "11111111-1111-1111-1111-111111111111", "guild_name": "Iron", "rank": 2}), "member verified")
	t.check(server.set_verified_guild(1402, {"ok": true, "guild_id": "11111111-1111-1111-1111-111111111111", "guild_name": "Iron", "rank": 1}), "officer verified")
	member.inventory.add("plank_2", 20)

	t.current = "deposit and withdraw"
	t.eq(server.cmd_guild_bank(1403, "list").get("reason"), "no_guild", "outsiders have no vault")
	var put: Dictionary = server.cmd_guild_bank(1401, "deposit", "plank_2", 15)
	t.check(bool(put.get("ok", false)), "member deposits")
	t.eq(member.inventory.count("plank_2"), 5, "items leave the member")
	t.eq(server.cmd_guild_bank(1401, "withdraw", "plank_2", 5).get("reason"), "officers_only", "members cannot withdraw")
	var take: Dictionary = server.cmd_guild_bank(1402, "withdraw", "plank_2", 10)
	t.check(bool(take.get("ok", false)), "officer withdraws")
	t.eq(officer.inventory.count("plank_2"), 10, "officer receives the planks")
	t.eq(int((take["vault"] as Dictionary).get("plank_2", 0)), 5, "vault keeps the rest")
	t.eq((take["ledger"] as Array).size(), 2, "ledger records both moves")
	t.eq(server.cmd_guild_bank(1402, "withdraw", "plank_2", 99).get("reason"), "not_in_vault", "cannot overdraw")

	t.current = "persistence"
	var saved: Dictionary = WorldPersistence.capture(server)
	t.eq(int(saved["guild_banks"]["11111111-1111-1111-1111-111111111111"]["plank_2"]), 5, "vault saved with the world")
	member.position = Vector3(500, world.height_at(500, 500), 500)
	t.eq(server.cmd_guild_bank(1401, "list").get("reason"), "no_station", "only at the hub")
