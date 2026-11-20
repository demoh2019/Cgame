extends RefCounted
## Consent-based rated matchmaking: identities, proximity, Elo and cleanup.
const Matcher = preload("res://scripts/shared/arena_matchmaking.gd")
const Arena = preload("res://scripts/shared/arena_rating.gd")
const World = preload("res://scripts/shared/world_gen.gd")
const Server = preload("res://scripts/server/game_server.gd")
const Net = preload("res://scripts/shared/net.gd")


func _place(world, player, x: float, z: float = 0.0) -> void:
	player.position = Vector3(x, world.height_at(x, z), z)


func run(t) -> void:
	t.current = "ranked queue rejects unsafe or ineligible entrants"
	var world := World.new(411)
	var sim := Server.new(world, 411)
	var alpha = sim.add_player(401, "Alpha", "arena-match-alpha")
	var beta = sim.add_player(402, "Beta", "arena-match-beta")
	var guest = sim.add_player(403, "Guest")
	_place(world, alpha, 10.0)
	_place(world, beta, 12.0)
	_place(world, guest, 13.0)
	t.eq(sim.cmd_arena_queue_join(guest.id)["reason"], "account_required",
		"guests cannot enter a ranked match queue")
	t.check(sim.cmd_arena_queue_join(alpha.id)["ok"], "verified survivor enters queue")
	t.check(sim.cmd_arena_queue_join(beta.id)["ok"], "verified opponent enters queue")
	t.eq(sim.cmd_arena_queue_join(alpha.id)["status"], "queued", "repeated join is idempotent")
	t.eq(sim.arena_queue.size(), 2, "idempotent join cannot duplicate membership")
	t.check(sim.snapshot_for(alpha.id)["you"]["arena_queue"]["queued"],
		"only owner sees private arena-queue state")
	t.eq(sim.snapshot_for(guest.id)["you"]["arena_queue"]["queued"], false,
		"third player does not see somebody else's queue")
	var conn := Net.new()
	conn.role = "server"
	conn.sim = sim
	t.check(conn._event_visible_to({"type": "arena_queue", "peer": alpha.id}, alpha.id),
		"queue updates delivered to owner")
	t.check(not conn._event_visible_to({"type": "arena_queue", "peer": alpha.id}, beta.id),
		"queue status events cannot spy on other players")
	conn.free()

	t.current = "matching uses ordinary nonlethal ranked duel flow"
	sim._tick_arena_queue()
	t.check(sim.training_matches.has(alpha.id), "two consenting queued players are matched")
	t.check(sim.training_matches.has(beta.id), "both player slots become one duel")
	t.check(bool(sim.training_matches[alpha.id].get("ranked", false)),
		"matched duel is rated")
	t.eq(sim.arena_queue.size(), 0, "matched players leave queue automatically")
	sim._damage_target(alpha, {"kind": "player", "id": beta.id}, 500.0)
	t.eq(alpha.arena_rating, Arena.START_RATING + 16,
		"server-reported knockout earns standard Elo")
	t.eq(beta.arena_losses, 1, "matched opponent receives ranked loss")
	t.eq(alpha.pvp_honor, 0, "matched safe duel never grants open-world PvP honor")
	t.eq(beta.deaths, 0, "ranked training has no death or full-loot penalty")

	t.current = "anti-rematch ledger prevents rating trading"
	t.check(sim.cmd_arena_queue_join(alpha.id)["ok"], "winner can search again")
	t.check(sim.cmd_arena_queue_join(beta.id)["ok"], "loser can search again")
	sim._tick_arena_queue()
	t.check(sim.training_matches.is_empty(), "same account pair cannot rematch immediately")
	t.eq(sim.arena_queue.size(), 2, "both players remain queued for another opponent")
	sim.time += Arena.REMATCH_SECONDS + 2.0
	sim._tick_arena_queue()
	t.check(sim.training_matches.has(alpha.id),
		"after cooldown two consenting accounts may rematch")
	sim.cmd_duel_cancel(alpha.id)
	t.eq(sim.arena_queue.size(), 0, "surrender does not leave a stale queue entry")

	t.current = "ranking gap, distance, cancellation and reconnected peers"
	var gamma = sim.add_player(404, "Gamma", "arena-match-gamma")
	_place(world, gamma, 12.0)
	gamma.arena_rating = 1600
	t.check(sim.cmd_arena_queue_join(gamma.id)["ok"], "high Elo player can queue")
	t.check(sim.cmd_arena_queue_join(alpha.id)["ok"], "lower Elo player can queue")
	sim._tick_arena_queue()
	t.check(sim.training_matches.is_empty(), "very different Elo does not match immediately")
	t.eq(Matcher.gap_after(0.0), Matcher.BASE_ELO_GAP, "initial rating search is narrow")
	t.eq(Matcher.gap_after(1000.0), Matcher.MAX_ELO_GAP, "waiting expands tolerance but stays bounded")
	t.check(sim.cmd_arena_queue_leave(alpha.id)["ok"], "player can explicitly leave queue")
	t.eq(sim.cmd_arena_queue_leave(alpha.id)["reason"], "not_queued", "duplicate leave is harmless")
	var old_peer: int = gamma.id
	sim.remove_player(old_peer)
	var new_peer = sim.add_player(old_peer, "Unrelated", "arena-new-account")
	_place(world, new_peer, 12.0)
	t.check(not sim.arena_queue.has(old_peer), "reconnected peer never inherits queue entry")
	var remote = sim.add_player(405, "Remote", "arena-remote-account")
	_place(world, remote, 800.0)
	t.eq(sim.cmd_arena_queue_join(remote.id)["reason"], "safe_hub_only",
		"dangerous-zone PvP players cannot queue")
	_place(world, remote, 40.0)
	t.check(sim.cmd_arena_queue_join(remote.id)["ok"], "hub players can queue even if far apart")
	sim._tick_arena_queue()
	t.check(sim.training_matches.is_empty(), "opponents beyond challenge range do not match")
	remote.combat_tag_until = sim.time + 20.0
	sim._tick_arena_queue()
	t.check(not sim.arena_queue.has(remote.id), "combat-tagged players are automatically removed")
	var stale = sim.add_player(406, "Stale", "arena-stale-account")
	_place(world, stale, 11.0)
	t.check(sim.cmd_arena_queue_join(stale.id)["ok"], "eligible last survivor joins")
	stale.position = Vector3.INF
	sim._tick_arena_queue()
	t.check(not sim.arena_queue.has(stale.id), "invalid coordinates cannot linger in queue")
