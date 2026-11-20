extends RefCounted
## Consent-only hub sparring, nonlethal combat, no PvP economy exploits.
const Duel = preload("res://scripts/shared/training_duel.gd")
const WorldGen = preload("res://scripts/shared/world_gen.gd")
const Server = preload("res://scripts/server/game_server.gd")
const Net = preload("res://scripts/shared/net.gd")


func _move(world, player, x: float, z: float = 0.0) -> void:
	player.position = Vector3(x, world.height_at(x, z), z)


func run(t) -> void:
	t.current = "hub consent and target exclusivity"
	var world := WorldGen.new(57)
	var sim := Server.new(world, 57)
	var a = sim.add_player(201, "Sparrer A", "account-spar-a")
	var b = sim.add_player(202, "Sparrer B", "account-spar-b")
	_move(world, a, 10.0)
	_move(world, b, 11.5)
	t.eq(sim.cmd_duel_accept(b.id)["reason"], "no_invite", "no forged acceptance")
	t.check(sim._find_hit(a, Vector2(10, 0), Vector2.RIGHT, 3.0, false).is_empty(),
		"safe-hub player targeting forbidden by default")
	t.check(sim.cmd_duel_invite(a.id, b.id)["ok"], "genuine nearby challenge")
	t.eq(sim.cmd_duel_invite(a.id, b.id)["reason"], "cooldown", "invites are rate-limited")
	t.eq(sim.snapshot_for(b.id)["you"]["duel"]["invite_from"], a.id, "recipient sees pending invite")
	t.eq(sim.snapshot_for(a.id)["you"]["duel"], {}, "inviter sees no private target inbox")
	t.check(sim.cmd_duel_accept(b.id)["ok"], "mutual consent activates sparring")
	t.eq(sim.cmd_duel_accept(b.id)["reason"], "no_invite", "cannot replay invitation")
	t.eq(sim.cmd_duel_invite(b.id, a.id)["reason"], "already_dueling", "one opponent at a time")
	t.eq(sim.snapshot_for(a.id)["you"]["duel"]["opponent"], b.id, "duel snapshot has opponent")

	t.current = "sparring is nonlethal and awards no kill stats, loot or infamy"
	var hit: Dictionary = sim._find_hit(a, Vector2(10, 0), Vector2.RIGHT, 3.0, false)
	t.eq(int(hit.get("id", -1)), b.id, "the accepted opponent is now targetable")
	var before_a: Dictionary = a.inventory.to_dict()
	var before_b: Dictionary = b.inventory.to_dict()
	var hp_a: float = a.survival.health
	var hp_b: float = b.survival.health
	var bag_count: int = sim.bags.size()
	sim._damage_target(a, {"kind": "player", "id": b.id}, 15.0)
	t.check(b.survival.health < hp_b, "training damage affects health temporarily")
	sim._damage_target(a, {"kind": "player", "id": b.id}, 2000.0)
	t.check(b.survival.alive, "finishing blow leaves loser alive")
	t.check(sim.training_matches.is_empty(), "victory releases both match slots")
	t.eq(sim.bags.size(), bag_count, "training never drops full loot")
	t.eq(a.inventory.to_dict(), before_a, "winner keeps equipment")
	t.eq(b.inventory.to_dict(), before_b, "loser keeps equipment")
	t.near(b.survival.health, hp_b, 0.001, "training HP restored")
	t.near(a.survival.health, hp_a, 0.001, "opponent HP unaffected")
	t.eq(a.pvp_kills, 0, "no PvP kill stats")
	t.eq(a.pvp_honor, 0, "no honor farming")
	t.near(a.pvp_infamy, 0.0, 0.001, "no crime or outlaw")
	t.eq(a.combat_tag_until, 0.0, "no combat-logout penalty")
	t.eq(b.deaths, 0, "no real survivor death")
	t.check(sim._find_hit(a, Vector2(10, 0), Vector2.RIGHT, 3.0, false).is_empty(),
		"safe-zone combat immediately disabled after duel")

	t.current = "distance, time, disconnect and anti-peer-reuse safety"
	sim.time = 9.0
	t.check(sim.cmd_duel_invite(a.id, b.id)["ok"], "next invite after cooldown")
	t.check(sim.cmd_duel_accept(b.id)["ok"], "repeat match may start")
	_move(world, b, 70.0)
	sim._tick_training()
	t.check(sim.training_matches.is_empty(), "moving too far ends training")
	_move(world, b, 11.5)
	sim.time = 18.0
	t.check(sim.cmd_duel_invite(a.id, b.id)["ok"], "fresh invite after separation")
	t.check(sim.cmd_duel_accept(b.id)["ok"], "match after separation works")
	sim.time += Duel.MATCH_SECONDS + 1.0
	sim._tick_training()
	t.check(sim.training_matches.is_empty(), "timeout ends training")
	t.eq(sim.cmd_duel_cancel(a.id)["reason"], "no_duel", "idempotent cancellation")
	sim.time += 9.0
	t.check(sim.cmd_duel_invite(a.id, b.id)["ok"], "last invitation after cooldown")
	t.check(sim.cmd_duel_accept(b.id)["ok"], "active before disconnect")
	sim.remove_player(a.id)
	t.check(sim.training_matches.is_empty(), "disconnect cancels both participants")
	var replacement = sim.add_player(201, "New peer", "another-account")
	t.eq(sim.snapshot_for(replacement.id)["you"]["duel"], {}, "reused peer ID cannot inherit match")

	t.current = "account, existing combat and dangerous-zone protection"
	_move(world, replacement, 10.0)
	_move(world, b, 11.5)
	replacement.user_id = b.user_id
	t.eq(sim.cmd_duel_invite(replacement.id, b.id)["reason"], "same_account",
		"account alternate characters cannot train together")
	replacement.user_id = "another-account"
	replacement.combat_tag_until = sim.time + 10.0
	t.eq(sim.cmd_duel_invite(replacement.id, b.id)["reason"], "in_combat",
		"cannot wash an existing PvP combat tag")
	replacement.combat_tag_until = 0.0
	_move(world, b, 800.0)
	t.eq(sim.cmd_duel_invite(replacement.id, b.id)["reason"], "safe_hub_only",
		"hub duels cannot extend into full-loot zones")
	var net := Net.new()
	net.role = "server"
	net.sim = sim
	t.check(net._event_visible_to({"type": "duel", "peer": b.id}, b.id),
		"duel messages are private to participant")
	t.check(not net._event_visible_to({"type": "duel", "peer": b.id}, replacement.id),
		"strangers cannot spy on duel events")
	net.free()
