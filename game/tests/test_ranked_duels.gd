extends RefCounted
## Optional Elo ranked hub duels (consent, authenticated identities, no loot).
const Arena = preload("res://scripts/shared/arena_rating.gd")
const World = preload("res://scripts/shared/world_gen.gd")
const Server = preload("res://scripts/server/game_server.gd")


func _place(world, survivor, x: float) -> void:
	survivor.position = Vector3(x, world.height_at(x, 0.0), 0.0)


func run(t) -> void:
	t.current = "deterministic Elo and authentic pair anti-farming"
	t.eq(Arena.tier(1200), "Silver", "new participants enter the silver tier")
	t.eq(Arena.tier(1900), "Diamond", "higher rating grants diamond")
	var world := World.new(101)
	var sim := Server.new(world, 101)
	var a = sim.add_player(111, "Alpha", "arena-account-a")
	var b = sim.add_player(112, "Beta", "arena-account-b")
	_place(world, a, 10.0)
	_place(world, b, 11.0)
	t.check(sim.cmd_duel_invite(a.id, b.id)["ok"], "casual invite retains old behavior")
	t.check(sim.cmd_duel_accept(b.id)["ok"], "casual duel starts")
	sim._damage_target(a, {"kind": "player", "id": b.id}, 500.0)
	t.eq(a.arena_rating, Arena.START_RATING, "casual win awards no ranked points")
	t.eq(b.arena_losses, 0, "casual loss is not a ranked defeat")
	sim.time = 9.0
	t.check(sim.cmd_duel_invite(a.id, b.id, true)["ok"], "authenticated player can issue ranked challenge")
	t.check(sim.snapshot_for(b.id)["you"]["duel"]["ranked"], "invitation identifies ranked stakes")
	t.check(sim.cmd_duel_accept(b.id)["ranked"], "recipient consents to ranked mode")
	t.check(sim.snapshot_for(a.id)["you"]["duel"]["ranked"], "both participants see rated match")
	sim._damage_target(a, {"kind": "player", "id": b.id}, 500.0)
	t.eq(a.arena_rating, 1216, "equal Elo knockout wins 16 points")
	t.eq(b.arena_rating, 1184, "loser loses 16 Elo points")
	t.eq(a.arena_wins, 1, "winner statistics increment once")
	t.eq(b.arena_losses, 1, "loser statistics increment once")
	t.eq(a.pvp_honor, 0, "ranked training cannot mint open-world PvP honor")
	t.eq(a.kills, 0, "rated win does not count as real player kill")
	t.eq(b.deaths, 0, "ranked loser is alive and keeps equipment")
	t.eq(sim.cmd_duel_invite(b.id, a.id, true)["reason"], "ranked_rematch_cooldown",
		"same accounts cannot trade rating in rapid rematches")
	t.eq(Arena.eligibility(a, b, sim.time + 10.0, sim.arena_recent_pairs), "ranked_rematch_cooldown",
		"connection direction cannot bypass cooldown")
	t.check(sim.cmd_duel_invite(b.id, a.id)["ok"], "casual matches stay available during ranked cooldown")
	t.check(sim.cmd_duel_accept(a.id)["ok"], "casual retry allowed")
	sim.cmd_duel_cancel(a.id)
	t.eq(a.arena_rating, 1216, "casual surrender does not affect rating")

	t.current = "ranked surrender and connection loss count as forfeits"
	sim.time += Arena.REMATCH_SECONDS + 10.0
	t.check(sim.cmd_duel_invite(b.id, a.id, true)["ok"], "new ranked fight after cooldown")
	t.check(sim.cmd_duel_accept(a.id)["ok"], "ranked rematch is voluntary")
	sim.cmd_duel_cancel(a.id)
	t.eq(a.arena_losses, 1, "ranked surrender counts as one loss")
	t.eq(b.arena_wins, 1, "other contestant wins surrendered game")
	t.check(a.arena_rating < 1216, "surrender reduces rating")
	sim.time += Arena.REMATCH_SECONDS + 9.0
	t.check(sim.cmd_duel_invite(a.id, b.id, true)["ok"], "ranked again after pair lock")
	t.check(sim.cmd_duel_accept(b.id)["ok"], "third rated encounter starts")
	var score_before: int = a.arena_wins
	sim._abort_training(b.id, "disconnected")
	t.eq(a.arena_wins, score_before + 1, "disconnecting forfeits rated game")
	t.check(sim.training_matches.is_empty(), "forfeit clears both slots")
	var result_count: int = a.arena_wins
	sim.remove_player(b.id)
	t.eq(a.arena_wins, result_count, "remove-player cannot replay rating changes")

	t.current = "guest abuse and strict old/new character saves"
	var guest = sim.add_player(113, "Guest")
	_place(world, guest, 11.0)
	t.eq(sim.cmd_duel_invite(a.id, guest.id, true)["reason"], "account_required",
		"guests cannot create disposable ranked accounts")
	var alt = sim.add_player(114, "Alt", a.user_id)
	_place(world, alt, 11.0)
	t.eq(sim.cmd_duel_invite(a.id, alt.id, true)["reason"], "same_account",
		"same-account alts cannot gain rating")
	var saved: Dictionary = sim.character_data(a)
	t.eq(int(saved["arena_wins"]), a.arena_wins, "rated victories persist")
	var returned = sim.add_player(115, "Return", "return-account", saved)
	t.eq(returned.arena_rating, a.arena_rating, "Elo survives account reload")
	for invalid in [NAN, INF, -2, 2500, 1200.5, "1200"]:
		var broken: Dictionary = saved.duplicate(true)
		broken["arena_rating"] = invalid
		t.check(not sim.apply_character(returned, broken), "invalid Elo save rejected")
		t.eq(returned.arena_rating, a.arena_rating, "failed load does not partially mutate score")
	var legacy: Dictionary = saved.duplicate(true)
	legacy.erase("arena_rating")
	legacy.erase("arena_wins")
	legacy.erase("arena_losses")
	t.check(sim.apply_character(returned, legacy), "legacy version-one saves load")
	t.eq(returned.arena_rating, Arena.START_RATING, "legacy player starts at 1200")
	t.eq(returned.arena_losses, 0, "legacy player has no arena defeats")
	for corrupt in [-1, Arena.MAX_RECORD + 1, 1.5, "3"]:
		var bad: Dictionary = saved.duplicate(true)
		bad["arena_wins"] = corrupt
		t.check(not sim.apply_character(returned, bad), "invalid ranked win counter rejected")
