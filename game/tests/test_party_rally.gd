extends RefCounted
## Rally requests take the group leader's server position only and
## never broadcast coordinates to strangers or offline characters.

const Party = preload("res://scripts/shared/party.gd")
const GameServer = preload("res://scripts/server/game_server.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")


func _put(world, player, x: float, z: float) -> void:
	player.position = Vector3(x, world.height_at(x, z), z)


func run(t) -> void:
	t.current = "group rally permissions and time bounds"
	var groups := Party.new()
	t.eq(groups.mark_rally(1, Vector3.ZERO, 0.0).get("reason"), "not_in_party",
		"no marker outside a formed party")
	t.check(groups.invite(1, 2, 0.0).get("ok", false), "leader opens a party")
	t.check(groups.accept(2, 0.1).get("ok", false), "ally joins")
	t.eq(groups.mark_rally(2, Vector3(4, 0, 5), 0.2).get("reason"), "leader_only",
		"only the leader can set rally")
	t.eq(groups.mark_rally(1, Vector3.INF, 0.2).get("reason"), "invalid_position",
		"nonfinite markers are rejected")
	t.check(groups.mark_rally(1, Vector3(4, 1, 5), 1.0).get("ok", false),
		"leader creates short-lived marker")
	t.eq(groups.state_for(1, 1.0)["rally"], groups.state_for(2, 1.0)["rally"],
		"each member receives identical rally coordinates")
	t.eq(groups.state_for(3, 1.0)["rally"], {},
		"outsiders have no marker or party membership")
	t.eq(groups.mark_rally(1, Vector3(9, 0, 9), 2.0).get("reason"), "cooldown",
		"repeated beacons cannot spam clients")
	t.eq(groups.state_for(2, 1.0)["rally"]["x"], 4.0,
		"rejected repeat cannot replace the leader marker")
	t.eq(groups.state_for(1, 1.0 + Party.RALLY_SECONDS)["rally"], {},
		"expired rally disappears without a timer tick")
	t.check(groups.mark_rally(1, Vector3(10, 0, 12), 1.0 + Party.RALLY_SECONDS).get("ok", false),
		"leader may place another rally after cooldown")
	t.check(groups.leave(2).get("ok", false), "ally leaves")
	t.eq(groups.state_for(1, 100.0)["rally"], {},
		"last member leaving disbands group and erases rally")

	t.current = "authoritative network snapshots"
	var world := WorldGen.new(43)
	var server := GameServer.new(world, 15)
	var leader = server.add_player(401, "Leader")
	var ally = server.add_player(402, "Ally")
	var stranger = server.add_player(403, "Stranger")
	_put(world, leader, 250, 250)
	_put(world, ally, 253, 250)
	_put(world, stranger, 255, 250)
	t.eq(server.cmd_party_rally(401).get("reason"), "not_in_party",
		"no party means no server rally")
	t.check(server.cmd_party_invite(401, 402).get("ok", false), "nearby invite")
	t.check(server.cmd_party_accept(402).get("ok", false), "join")
	t.eq(server.cmd_party_rally(402).get("reason"), "leader_only",
		"forged member RPC cannot set marker")
	var mark: Dictionary = server.cmd_party_rally(401)
	t.check(mark.get("ok", false), "leader can place rally")
	var in_group: Dictionary = server.snapshot_for(402)["you"]["party"]["rally"]
	t.near(float(in_group["x"]), 250.0, 0.001, "marker uses server owner position")
	t.near(float(in_group["z"]), 250.0, 0.001, "server z coordinate used")
	t.eq(server.snapshot_for(403)["you"]["party"]["rally"], {},
		"nearby nonparty player cannot access marker")
	t.eq(server.cmd_party_rally(401).get("reason"), "cooldown",
		"repeat command respects cooldown")
	server.time += Party.RALLY_SECONDS + 0.01
	t.eq(server.snapshot_for(402)["you"]["party"]["rally"], {},
		"expired marker is not present in server snapshots")
	t.check(server.cmd_party_rally(401).get("ok", false),
		"leader may renew marker after expiry")
	server.remove_player(401)
	t.eq(server.snapshot_for(402)["you"]["party"]["rally"], {},
		"disbanded group marker cannot leak after disconnect")
