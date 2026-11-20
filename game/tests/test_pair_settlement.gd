extends RefCounted
## Atomic two-account settlement of player deals (GameServer.pair_commits, drained by Net into Nakama's
## character_pair_save). Here: which deals queue a settlement, the lock that keeps both players out of new deals
## until it is confirmed, and that without a persistent backend nothing changes.

const WorldGen = preload("res://scripts/shared/world_gen.gd")
const GameServer = preload("res://scripts/server/game_server.gd")


func _move(world, player, x: float, z: float) -> void:
	player.position = Vector3(x, world.height_at(x, z), z)


## Alice gives Bob 4 wood for 7 silver through the full invite/offer/accept flow; returns the final accept result.
func _barter(server) -> Dictionary:
	var invite: Dictionary = server.cmd_trade_invite(101, 102)
	if not invite.get("ok", false):
		return invite
	var id: int = int(invite["trade_id"])
	server.cmd_trade_offer(101, id, "wood_1", 4)
	var counter: Dictionary = server.cmd_trade_offer(102, id, "silver", 7)
	var revision: int = int(counter["revision"])
	server.cmd_trade_accept(102, id, revision)
	return server.cmd_trade_accept(101, id, revision)


func _setup(persistent: bool) -> Array:
	var world := WorldGen.new(42)
	var server := GameServer.new(world, 1234)
	server.pair_persistence = persistent
	var alice = server.add_player(101, "Alice")
	var bob = server.add_player(102, "Bob")
	_move(world, alice, 3.0, 1.0)
	_move(world, bob, 4.0, 1.0)
	alice.inventory.add("wood_1", 20)
	bob.inventory.add("silver", 60)
	return [server, alice, bob]


func run(t) -> void:
	t.current = "offline servers settle deals exactly as before"
	var offline: Array = _setup(false)
	t.check(_barter(offline[0]).get("completed", false), "barter completes without a backend")
	t.eq(offline[0].pair_commits.size(), 0, "no settlement is queued without a backend")
	t.eq(offline[0].pair_locks.size(), 0, "nobody is locked without a backend")
	t.check(_barter(offline[0]).get("completed", false), "a second barter follows at once")

	t.current = "a completed barter queues one atomic settlement and locks both players"
	var setup: Array = _setup(true)
	var server = setup[0]
	var done: Dictionary = _barter(server)
	t.check(done.get("completed", false), "barter completes in memory immediately")
	t.eq(setup[1].inventory.count("silver"), 7, "items moved before the backend confirms")
	t.eq(server.pair_commits.size(), 1, "exactly one settlement queued")
	var commit: Dictionary = server.pair_commits[0]
	t.check((int(commit["a"]) == 101 and int(commit["b"]) == 102) or (int(commit["a"]) == 102 and int(commit["b"]) == 101),
		"the settlement covers both traders")
	t.check(str(commit["tx"]).begins_with("trade-") and str(commit["tx"]).length() >= 8, "a usable transaction ID")
	t.eq(str(server.pair_locks.get(101, "")), str(commit["tx"]), "Alice waits for this transaction")
	t.eq(str(server.pair_locks.get(102, "")), str(commit["tx"]), "Bob waits for this transaction")
	t.eq(server.cmd_trade_invite(101, 102).get("reason", ""), "saving_previous_deal", "no new barter before confirmation")
	t.eq(server.cmd_trade_invite(102, 101).get("reason", ""), "saving_previous_deal", "either side is locked")
	t.eq(server.cmd_market_create(101, "wood_1", 1, 5).get("reason", ""), "saving_previous_deal",
		"no market listing before confirmation")

	t.current = "a confirmation releases both players, and only that transaction"
	server.release_pair_commit("some-other-transaction")
	t.check(server.pair_locks.has(101) and server.pair_locks.has(102), "an unrelated confirmation releases nobody")
	server.release_pair_commit(str(commit["tx"]))
	t.eq(server.pair_locks.size(), 0, "the matching confirmation releases both")
	server.pair_commits.clear()
	t.check(_barter(server).get("completed", false), "they can trade again")
	t.eq(server.pair_commits.size(), 1, "the new deal queues its own settlement")
	t.check(str(server.pair_commits[0]["tx"]) != str(commit["tx"]), "every deal has a fresh transaction ID")
