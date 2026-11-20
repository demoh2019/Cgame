extends RefCounted
## Server-owned raid readiness: consent, isolation, timeouts and party churn.

const Party = preload("res://scripts/shared/party.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const GameServer = preload("res://scripts/server/game_server.gd")
const Net = preload("res://scripts/shared/net.gd")


func run(t) -> void:
	t.current = "leader-owned party ready checks"
	var parties := Party.new()
	t.check(parties.invite(1, 2, 0.0)["ok"], "leader may create a group")
	t.check(parties.accept(2, 0.1)["ok"], "second member joins")
	t.eq(parties.start_ready_check(2, 1.0)["reason"], "leader_only",
		"regular party member cannot start a check")
	t.eq(parties.start_ready_check(99, 1.0)["reason"], "not_in_party",
		"outsider cannot start a check")
	t.eq(parties.start_ready_check(1, INF)["reason"], "invalid_time",
		"non-finite timestamps are rejected")
	t.check(parties.start_ready_check(1, 1.0)["ok"], "leader starts check")
	t.eq(parties.start_ready_check(1, 1.1)["reason"], "in_progress",
		"active check cannot be overwritten")
	var view: Dictionary = parties.state_for(2, 1.0)["ready_check"]
	t.eq(view["result"], "pending", "all members initially pending")
	t.eq(view["votes"].size(), 2, "both members must make their own decision")
	t.eq(parties.state_for(99, 1.0)["ready_check"], {},
		"unrelated players cannot inspect consent state")
	t.eq(parties.answer_ready_check(99, true, 1.5)["reason"], "not_in_party",
		"outsider cannot spoof a readiness vote")
	t.eq(parties.answer_ready_check(2, true, INF)["reason"], "invalid_time",
		"non-finite vote time is rejected")
	t.eq(parties.answer_ready_check(2, true, 1.5)["result"], "pending",
		"one yes vote cannot mark all members ready")
	t.eq(parties.answer_ready_check(2, false, 1.6)["reason"], "already_responded",
		"one member cannot vote twice")
	t.eq(parties.answer_ready_check(1, true, 2.0)["result"], "all_ready",
		"all actual members must explicitly confirm")
	t.eq(parties.state_for(1, 2.0)["ready_check"]["result"], "all_ready",
		"result is visible to its own group")
	t.eq(parties.answer_ready_check(2, false, 2.1)["reason"], "finished",
		"completed check cannot be manipulated")
	t.eq(parties.start_ready_check(1, 3.0)["reason"], "cooldown",
		"leaders cannot immediately spam a second check")

	t.current = "declines, membership changes and expiry"
	t.check(parties.start_ready_check(1, 10.0)["ok"], "cooldown eventually passes")
	t.eq(parties.answer_ready_check(2, false, 10.5)["result"], "not_ready",
		"one no vote immediately prevents false all-ready status")
	t.eq(parties.answer_ready_check(1, true, 10.6)["reason"], "finished",
		"late yes cannot reverse a decline")
	t.eq(parties.state_for(1, 20.6)["ready_check"], {},
		"finished outcome is retained only briefly")
	t.check(parties.start_ready_check(1, 20.6)["ok"], "leader may recheck later")
	t.check(parties.invite(1, 3, 21.0)["ok"], "new member can be invited")
	t.check(parties.accept(3, 21.1)["ok"], "new member joins")
	t.eq(parties.state_for(1, 21.1)["ready_check"], {},
		"joining a party invalidates prior unanimous consent")
	t.check(parties.start_ready_check(1, 29.0)["ok"], "new roster can be checked")
	t.check(parties.kick(1, 3)["ok"], "leader removes member")
	t.eq(parties.state_for(2, 29.1)["ready_check"], {},
		"removing a member invalidates prior votes")
	t.check(parties.start_ready_check(1, 38.0)["ok"], "check restarts")
	parties.expire(69.0)
	t.eq(parties.state_for(1, 69.0)["ready_check"], {},
		"unanswered check expires on the server")
	t.eq(parties.answer_ready_check(2, true, 69.0)["reason"], "no_check",
		"expired check cannot accept late votes")
	t.check(parties.start_ready_check(1, 70.0)["ok"], "leader can retry after timeout")
	parties.cancel_ready_check_for(2)
	t.eq(parties.state_for(1, 70.0)["ready_check"], {},
		"server cancels readiness if a party member dies")
	t.check(parties.leave(2)["ok"], "last teammate can leave")
	t.eq(parties.state_for(1, 70.0)["ready_check"], {},
		"disbanded party cannot leak ready status")

	t.current = "network-facing authority and privacy"
	var world := WorldGen.new(919)
	var server := GameServer.new(world, 919)
	var leader = server.add_player(11, "Scout")
	var ally = server.add_player(12, "Medic")
	var stranger = server.add_player(13, "Stranger")
	leader.position = Vector3(2.0, world.height_at(2.0, 0.0), 0.0)
	ally.position = Vector3(3.0, world.height_at(3.0, 0.0), 0.0)
	stranger.position = Vector3(400.0, world.height_at(400.0, 0.0), 0.0)
	t.check(server.cmd_party_invite(11, 12)["ok"], "real server checks invitation")
	t.check(server.cmd_party_accept(12)["ok"], "ally joins authoritative roster")
	t.eq(server.cmd_party_ready_start(12)["reason"], "leader_only",
		"forged member cannot start another player's check")
	t.check(server.cmd_party_ready_start(11)["ok"], "leader starts through server command")
	t.eq(server.cmd_party_ready_start(11)["reason"], "in_progress",
		"repeated RPC cannot reset deadline")
	t.eq(server.snapshot_for(12)["you"]["party"]["ready_check"]["votes"].size(), 2,
		"member receives the private check in ordinary snapshot")
	t.eq(server.snapshot_for(13)["you"]["party"]["ready_check"], {},
		"unrelated client snapshot is scrubbed")
	t.eq(server.cmd_party_ready_answer(13, true)["reason"], "not_in_party",
		"stranger vote cannot change party outcome")
	t.eq(server.cmd_party_ready_answer(12, true)["result"], "pending",
		"first server-authenticated response is not unanimous")
	t.eq(server.cmd_party_ready_answer(11, true)["result"], "all_ready",
		"server confirms all authenticated participants")
	ally.survival.hurt(999.0)
	server._on_player_death(ally, -1)
	t.eq(server.snapshot_for(11)["you"]["party"]["ready_check"], {},
		"dead teammate invalidates raid votes")
	server.time = Party.READY_COOLDOWN + 1.0
	t.eq(server.cmd_party_ready_start(11)["reason"], "member_unavailable",
		"leader cannot declare a party ready with an unconscious teammate")
	leader.survival.hurt(999.0)
	t.eq(server.cmd_party_ready_start(11)["reason"], "dead",
		"dead leader cannot launch checks")
	t.eq(server.cmd_party_ready_answer(11, true)["reason"], "dead",
		"dead players cannot vote")
	var net := Net.new()
	t.check(net.has_method("c_party_ready_start") and net.has_method("c_party_ready_answer"),
		"network exposes sender-bound RPCs")
	net.free()
