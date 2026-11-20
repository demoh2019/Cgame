extends RefCounted
## Party map marks are authenticated, group-isolated and time-limited.
const Party = preload("res://scripts/shared/party.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const GameServer = preload("res://scripts/server/game_server.gd")


func _put(world, player, x: float, z: float) -> void:
	player.position = Vector3(x, world.height_at(x, z), z)


func run(t) -> void:
	t.current = "authenticated group ping limits and privacy"
	var group := Party.new()
	t.eq(group.mark_ping(1, Vector2(25, 25), 0.0).get("reason"),
		"not_in_party", "solo peers cannot ping")
	t.check(bool(group.invite(1, 2, 0.0).get("ok", false)), "invite starts group")
	t.eq(group.mark_ping(1, Vector2(25, 25), 0.0).get("reason"),
		"need_party", "pending invitation is not a squad")
	t.check(bool(group.accept(2, 0.1).get("ok", false)), "teammate joins")
	t.eq(group.mark_ping(3, Vector2(25, 25), 0.5).get("reason"),
		"not_in_party", "outsiders cannot ping")
	for bad in [Vector2(INF, 2.0), Vector2(NAN, 2.0),
			Vector2(WorldGen.WORLD_RADIUS + 1.0, 0.0)]:
		t.eq(group.mark_ping(2, bad, 1.0).get("reason"), "invalid_position",
			"bad coordinates rejected without consuming cooldown")
	t.check(bool(group.mark_ping(2, Vector2(225, -180), 1.0).get("ok", false)),
		"any verified member can mark the map")
	var point: Dictionary = group.state_for(1, 2.0)["ping"]
	t.near(float(point["x"]), 225.0, 0.001, "x matches map selection")
	t.near(float(point["z"]), -180.0, 0.001, "z matches map selection")
	t.eq(int(point["by"]), 2, "source identity is server-owned")
	t.near(float(point["remaining"]), Party.PING_SECONDS - 1.0, 0.001,
		"remaining seconds use server time")
	t.eq(group.state_for(3, 2.0)["ping"], {},
		"nonparty viewers receive no coordinates")
	t.eq(group.mark_ping(1, Vector2.ZERO, 2.0).get("reason"), "cooldown",
		"other squad members cannot bypass rate limit")
	t.eq(float(group.state_for(1, 2.0)["ping"]["x"]), 225.0,
		"blocked ping does not replace old mark")
	t.eq(group.state_for(1, 1.0 + Party.PING_SECONDS)["ping"], {},
		"marker expires without an explicit tick")
	t.check(bool(group.mark_ping(1, Vector2(5, 15),
		1.0 + Party.PING_SECONDS).get("ok", false)), "re-ping after cooldown")
	t.check(bool(group.leave(1).get("ok", false)), "creator leaves")
	t.eq(group.state_for(2, 45.0)["ping"], {},
		"disband clears teammate map data")

	t.current = "live server and owner-only snapshots"
	var world := WorldGen.new(91)
	var server := GameServer.new(world, 91)
	var leader = server.add_player(401, "Leader")
	var scout = server.add_player(402, "Scout")
	var stranger = server.add_player(403, "Stranger")
	_put(world, leader, 220, 220)
	_put(world, scout, 223, 220)
	_put(world, stranger, 224, 220)
	t.eq(server.cmd_party_ping(401, 20, 30).get("reason"),
		"not_in_party", "server refuses unsigned solo ping")
	t.check(bool(server.cmd_party_invite(401, 402).get("ok", false)),
		"real invitation accepted")
	t.check(bool(server.cmd_party_accept(402).get("ok", false)),
		"ally joins group")
	t.eq(server.cmd_party_ping(402, INF, 1.0).get("reason"),
		"invalid_position", "forged RPC infinity refused")
	t.eq(server.cmd_party_ping(402, WorldGen.WORLD_RADIUS + 1.0, 0.0).get("reason"),
		"invalid_position", "out of island ping refused")
	t.check(bool(server.cmd_party_ping(402, 280, 310).get("ok", false)),
		"scout can ping a remote map coordinate")
	var view: Dictionary = server.snapshot_for(401)["you"]["party"]["ping"]
	t.near(float(view["x"]), 280.0, 0.001, "leader receives pin")
	t.eq(int(view["by"]), 402, "authenticated identity exposed to party")
	t.eq(server.snapshot_for(403)["you"]["party"]["ping"], {},
		"nearby outsider learns no tactical point")
	t.eq(server.cmd_party_ping(401, 281, 311).get("reason"),
		"cooldown", "rate limit is per group")
	server.parties.clear_ping_by(401)
	t.check(not server.snapshot_for(401)["you"]["party"]["ping"].is_empty(),
		"nonauthor cannot revoke another member's ping")
	server.parties.clear_ping_by(402)
	t.eq(server.snapshot_for(401)["you"]["party"]["ping"], {},
		"dead/disconnected author clears point immediately")
	server.time += Party.PING_COOLDOWN + 0.01
	t.check(bool(server.cmd_party_ping(401, 250, 300).get("ok", false)),
		"server accepts next ping after cooldown")
	server.remove_player(401)
	t.eq(server.snapshot_for(402)["you"]["party"]["ping"], {},
		"disband after disconnect erases ping")
