extends RefCounted
## Player-vs-player honor is separate from red-zone criminal infamy.
const Honor = preload("res://scripts/shared/pvp_honor.gd")
const GameServer = preload("res://scripts/server/game_server.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const Net = preload("res://scripts/shared/net.gd")
const Zombie = preload("res://scripts/shared/zombie.gd")


func _move(world, player, x: float) -> void:
	player.position = Vector3(x, world.height_at(x, 0.0), 0.0)


func run(t) -> void:
	t.current = "PvP rank and unique victim anti-farming"
	t.eq(Honor.rank(0), "Wanderer", "fresh survivors start neutral")
	t.eq(Honor.rank(10), "Contender", "fighters earn a public rank")
	t.eq(Honor.rank(30), "Veteran", "veteran honor rank")
	t.eq(Honor.rank(100), "Champion", "champion honor rank")
	var world := WorldGen.new(47)
	var server := GameServer.new(world, 47)
	var fighter = server.add_player(11, "Killer", "honor-account-a")
	var victim = server.add_player(12, "Victim", "honor-account-b")
	var history: Dictionary = {}
	t.eq(Honor.record(fighter, victim, 0, 0.0, history)["reason"], "invalid_kill",
		"protected zones never award honor")
	t.eq(Honor.record(fighter, fighter, 2, 0.0, history)["reason"], "invalid_kill",
		"self kills never award honor")
	t.eq(Honor.record(fighter, victim, 2, NAN, history)["reason"], "invalid_kill",
		"invalid server clocks rejected")
	t.eq(Honor.record(fighter, victim, 2, 10.0, history)["awarded"], 4,
		"first red-zone PvP kill grants four honor")
	t.eq(Honor.record(fighter, victim, 2, 11.0, history)["awarded"], 0,
		"repeat account grants no honor")
	t.eq(fighter.pvp_kills, 2, "legitimate repeat deaths still count as PvP kills")
	server.remove_player(12)
	var new_user = server.add_player(12, "Unrelated", "honor-account-c")
	t.eq(Honor.record(fighter, new_user, 3, 12.0, history)["awarded"], 10,
		"recycled peer ID with new account remains eligible")
	var reconnect = server.add_player(13, "Rejoined", "honor-account-b")
	t.eq(Honor.record(fighter, reconnect, 3, 12.0, history)["awarded"], 0,
		"victim reconnect does not reset anti-farm")
	var same_account = server.add_player(14, "Alt", "honor-account-a")
	t.eq(Honor.record(fighter, same_account, 3, 12.0, history)["reason"], "same_account",
		"two characters on same account cannot award honor")
	t.eq(Honor.record(fighter, reconnect, 3, 311.0, history)["awarded"], 10,
		"victim can award honor after 300 seconds")
	t.eq(fighter.pvp_honor, 24, "red and black award independent honor totals")

	t.current = "actual server PvP kills and save validation"
	var attacker = server.add_player(101, "Red Killer")
	var target = server.add_player(102, "Red Target")
	_move(world, attacker, 800.0)
	_move(world, target, 801.0)
	server._damage_target(attacker, {"kind": "player", "id": target.id}, 1000.0)
	t.eq(attacker.pvp_kills, 1, "real lethal damage increments PvP-only kills")
	t.eq(attacker.pvp_honor, 4, "real red-zone PvP awards honor")
	t.eq(attacker.pvp_infamy, 25.0, "existing criminal infamy remains unchanged")
	t.eq(server.snapshot_for(attacker.id)["you"]["pvp_rank"], "Wanderer",
		"owner receives rank from authoritative state")
	t.eq(server.snapshot_for(target.id)["players"][0]["pvp_rank"], "Wanderer",
		"nearby players receive only honor rank")
	var honor_before: int = attacker.pvp_honor
	var infected := Zombie.new(server.new_id(), "brute",
		Vector3(799.0, world.height_at(799.0, 0.0), 0.0))
	server.zombies[infected.id] = infected
	server._damage_target(attacker, {"kind": "zombie", "id": infected.id}, 1000.0)
	t.eq(attacker.pvp_honor, honor_before, "PvE kill never awards PvP honor")
	var save: Dictionary = server.character_data(attacker)
	var stored = server.add_player(401, "Return", "", save)
	t.eq(stored.pvp_kills, 1, "PvP kill counter survives save")
	t.eq(stored.pvp_honor, 4, "honor survives save")
	for value in [-1, NAN, INF, 100001, "4", 1.5]:
		var invalid: Dictionary = save.duplicate(true)
		invalid["pvp_honor"] = value
		t.check(not server.apply_character(stored, invalid), "corrupt honor is rejected")
		t.eq(stored.pvp_honor, 4, "failed load cannot modify honor")
	var legacy: Dictionary = save.duplicate(true)
	legacy.erase("pvp_honor")
	legacy.erase("pvp_kills")
	t.check(server.apply_character(stored, legacy), "older version-1 saves remain valid")
	t.eq(stored.pvp_honor, 0, "legacy survivor starts with no PvP honor")
	var net := Net.new()
	net.role = "server"
	net.sim = server
	t.check(net._event_visible_to({"type": "pvp_honor", "peer": attacker.id}, attacker.id),
		"owner receives PvP honor notification")
	t.check(not net._event_visible_to({"type": "pvp_honor", "peer": attacker.id}, stored.id),
		"third parties cannot inspect private score events")
	net.free()
