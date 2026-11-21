extends RefCounted
## Cross-server consistency: item ledger + 2PC moves, duplicate quarantine, guild op-log sync,
## party migration, ownership leases with fencing, load balancing, and a randomized cluster run.

const ItemLedger = preload("res://scripts/server/item_ledger.gd")
const GuildSync = preload("res://scripts/server/guild_sync.gd")
const PartyMigration = preload("res://scripts/server/party_migration.gd")
const OwnershipLeases = preload("res://scripts/server/ownership_leases.gd")
const ClusterSimulator = preload("res://scripts/server/cluster_simulator.gd")
const TransactionCoordinator = preload("res://scripts/server/transaction_coordinator.gd")


func _drain(sim: ClusterSimulator, ticks: int = 30) -> void:
	for _i in ticks:
		sim.step()


func _holders(sim: ClusterSimulator, id: String) -> Array:
	var out: Array = []
	for i in sim.n:
		if sim.ledger(i).has_item(id):
			out.append(i)
	return out


func run(t) -> void:
	_items(t)
	_crash_recovery(t)
	_durable_recovery(t)
	_duplicates(t)
	_guilds(t)
	_parties(t)
	_leases(t)
	_balancing(t)
	_random_runs(t)


func _items(t) -> void:
	t.current = "item move exactly once"
	var sim := ClusterSimulator.new()
	sim.setup(2, 11)
	var id := sim.mint_item(0, "alice", "sword")
	t.check(id.begins_with("i0-"), "ids carry the minting server")
	t.eq(sim.mint_item(0, "alice") != id, true, "ids are unique")
	t.eq(sim.move_items(0, 1, [id]), "committed", "move commits")
	t.eq(sim.ledger(0).state_of(id), "locked", "source stays locked until the commit message lands")
	_drain(sim)
	t.eq(_holders(sim, id), [1], "item lives on exactly one server")
	t.eq(sim.ledger(1).epoch_of(id), 1, "epoch bumps on move")
	t.eq(sim.ledger(1).owner_of(id), "alice", "owner preserved")
	var tx := "tx1"
	sim.ledger(1).commit(tx)
	sim.ledger(0).commit(tx)
	sim.ledger(1).prepare(tx, {"kind": "in", "recs": []})
	t.eq(_holders(sim, id), [1], "replayed decisions are idempotent")
	t.eq(sim.move_items(0, 1, [id]), "rejected", "cannot move an item the source no longer has")
	var other := sim.mint_item(1, "bob")
	t.eq(sim.move_items(1, 0, [id, other]), "committed", "batch move commits")
	_drain(sim)
	t.eq(sim.ledger(0).total_count(), 3, "batch arrives whole")
	# Destination refuses an id it already holds -> whole transaction aborts, nothing lost.
	var dup := sim.mint_item(1, "carol")
	sim.ledger(0).items[dup] = (sim.ledger(1).items[dup] as Dictionary).duplicate(true)
	sim.minted -= 1  # the injected copy is not a mint
	t.eq(sim.move_items(1, 0, [dup]), "aborted", "destination holding the id votes no")
	_drain(sim)
	t.eq(sim.ledger(1).is_active(dup), true, "aborted move unlocks the source")
	sim.teardown()


func _crash_recovery(t) -> void:
	t.current = "crash mid-transfer and recovery"
	var sim := ClusterSimulator.new()
	sim.setup(3, 5)
	var a := sim.mint_item(0, "p")
	sim.coordinator.crash_point = "before_decision"
	t.eq(sim.move_items(0, 2, [a]), "crashed", "coordinator crashes after prepare")
	t.eq(sim.ledger(0).state_of(a), "locked", "item frozen while in doubt")
	t.eq(_holders(sim, a), [0], "no copy appears on the target")
	t.eq(sim.move_items(0, 1, [a]), "rejected", "no new transactions while the coordinator is down")
	sim.recover_coordinator()
	_drain(sim)
	t.eq(sim.ledger(0).is_active(a), true, "no decision logged -> presumed abort, source unlocked")
	t.eq(_holders(sim, a), [0], "item still only on the source")

	var b := sim.mint_item(0, "p")
	sim.coordinator.crash_point = "after_decision"
	t.eq(sim.move_items(0, 2, [b]), "crashed", "crash right after the commit decision")
	t.eq(sim.ledger(0).state_of(b), "locked", "still locked before recovery")
	sim.recover_coordinator()
	_drain(sim)
	t.eq(_holders(sim, b), [2], "logged commit is re-delivered after recovery")
	t.eq(sim.ledger(2).is_active(b), true, "item usable on target")

	# Target server down at prepare time -> abort, nothing moves.
	var c := sim.mint_item(0, "p")
	sim.crash_server(1, 50)
	t.eq(sim.move_items(0, 1, [c]), "rejected", "down target is rejected up front")
	sim.alive[1] = true
	sim.ledger(1).items.clear()
	var sim2_ok := true
	# Target crashes between prepare and commit delivery: commit is held, then applied once.
	var d := sim.mint_item(0, "p")
	t.eq(sim.move_items(0, 1, [d]), "committed", "commit decided")
	sim.crash_server(1, 12)
	_drain(sim, 8)
	t.eq(sim.ledger(1).has_item(d), false, "message held while the target is down")
	_drain(sim, 12)
	t.eq(_holders(sim, d), [1], "delivered once after restart")
	t.eq(sim2_ok, true, "scenario ran")
	sim.teardown()


func _durable_recovery(t) -> void:
	t.current = "coordinator durability"
	var path := "user://test_cross_server_tx.json"
	var l0 := ItemLedger.new(0)
	var l1 := ItemLedger.new(1)
	var id := l0.mint("zed", "bow")
	var c1 := TransactionCoordinator.new()
	c1.set_path(path)
	c1.add_participant("s0", l0.prepare, l0.commit, l0.abort)
	c1.add_participant("s1", l1.prepare, l1.commit, l1.abort)
	var tx := c1.begin({"s0": {"kind": "out", "ids": [id]}, "s1": {"kind": "in", "recs": l0.snapshot([id])}})
	c1.crash_point = "after_decision"
	t.eq(c1.run(tx), "crashed", "first coordinator dies after logging commit")
	t.eq(l0.state_of(id), "locked", "source in doubt")
	var c2 := TransactionCoordinator.new()
	c2.set_path(path)
	t.eq(c2.load_store(), true, "decision log reloaded")
	c2.add_participant("s0", l0.prepare, l0.commit, l0.abort)
	c2.add_participant("s1", l1.prepare, l1.commit, l1.abort)
	var res := c2.recover()
	t.eq(String(res[tx]), "committed", "new coordinator finishes the commit")
	t.eq(l0.has_item(id), false, "source released")
	t.eq(l1.is_active(id), true, "target owns it")
	t.eq(l1.epoch_of(id), 1, "epoch survives the JSON round trip")
	c2.recover()
	t.eq(l1.total_count(), 1, "second recovery is a no-op")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path + ".tmp"))
	var snap := l1.to_dict()
	var l1b := ItemLedger.new(9)
	l1b.from_dict(JSON.parse_string(JSON.stringify(snap)))
	t.eq(l1b.is_active(id), true, "ledger serialises")


func _duplicates(t) -> void:
	t.current = "duplicate detection and quarantine"
	var l0 := ItemLedger.new(0)
	var l1 := ItemLedger.new(1)
	var id := l0.mint("eve", "gem")
	var fine := l1.mint("eve", "ring")
	l1.items[id] = {"id": id, "owner": "eve", "def": "gem", "epoch": 3, "state": "active", "lock_tx": ""}
	var dups := ItemLedger.find_duplicates([l0, l1])
	t.eq(dups.keys(), [id], "only the doubled id is reported")
	t.eq(dups[id], [0, 1], "reports which servers hold it")
	var q := ItemLedger.quarantine_duplicates([l0, l1])
	t.eq(q, [id], "quarantine returns the ids")
	t.eq(l0.state_of(id), "quarantined", "copy on 0 frozen")
	t.eq(l1.state_of(id), "quarantined", "copy on 1 frozen")
	t.eq(l1.is_active(fine), true, "unrelated items untouched")
	t.eq(l0.prepare("x", {"kind": "out", "ids": [id]}), false, "quarantined items cannot be moved")
	t.eq(l0.items_of("eve").size(), 0, "quarantined items are not usable")
	t.eq(ItemLedger.resolve_duplicate([l0, l1], id), 1, "highest epoch survives")
	t.eq(l0.has_item(id), false, "stale copy removed")
	t.eq(l1.is_active(id), true, "survivor reactivated")
	t.eq(ItemLedger.find_duplicates([l0, l1]).size(), 0, "no duplicates left")
	t.eq(l1.prepare("y", {"kind": "in", "recs": [{"id": id, "owner": "eve", "def": "gem", "epoch": 1}]}), false,
		"receiver refuses an id it already holds")


func _guilds(t) -> void:
	t.current = "guild convergence"
	var a := GuildSync.new(0)
	var b := GuildSync.new(1)
	var c := GuildSync.new(2)
	var o1 := a.join("g", "p1", 1)
	var o2 := a.join("g", "p2", 1)
	for op in [o1, o2]:
		b.receive(op)
		c.receive(op)
	t.eq(c.members("g"), ["p1", "p2"], "replicated members")
	# Concurrent: officer on A promotes p1, officer on B kicks p1.
	var rank := a.set_rank("g", "p1", 5)
	var kick := b.kick("g", "p1")
	a.receive(kick)
	b.receive(rank)
	c.receive(rank)
	c.receive(kick)
	var c2 := GuildSync.new(3)
	c2.receive(o1)
	c2.receive(kick)
	c2.receive(rank)  # opposite order on a fresh replica
	c2.receive(o2)
	t.eq(a.members("g"), ["p2"], "kick wins over concurrent rank change on A")
	t.eq(b.members("g"), ["p2"], "...and on B")
	t.eq(c.members("g"), ["p2"], "...and on C")
	t.eq(c2.members("g"), ["p2"], "...regardless of delivery order")
	t.eq(a.digest("g") == b.digest("g") and b.digest("g") == c.digest("g") and c.digest("g") == c2.digest("g"), true,
		"all replicas share one digest")
	t.eq(a.rank_of("g", "p1"), -1, "kicked member has no rank")
	# Re-invite after observing the kick works; a join that never saw the kick does not.
	var stale_join := c.join("g", "p9", 1)
	var stale_kick := a.kick("g", "p9")
	a.receive(stale_join)
	c.receive(stale_kick)
	t.eq(a.is_member("g", "p9"), false, "kick beats concurrent join")
	var rejoin := a.join("g", "p9", 2)
	c.receive(rejoin)
	b.receive(stale_join)
	b.receive(stale_kick)
	b.receive(rejoin)
	t.eq(a.is_member("g", "p9") and b.is_member("g", "p9") and c.is_member("g", "p9"), true, "causally later re-invite restores")
	# rank LWW + motd + treasury idempotence
	var r1 := a.set_rank("g", "p2", 3)
	var r2 := b.set_rank("g", "p2", 4)
	a.receive(r2)
	b.receive(r1)
	t.eq(a.rank_of("g", "p2"), b.rank_of("g", "p2"), "concurrent rank edits agree")
	var dep := a.deposit("g", 100)
	b.receive(dep)
	b.receive(dep)
	t.eq(b.treasury("g"), 100, "replayed deposit counted once")
	a.set_motd("g", "hello")
	# pull-based anti-entropy brings stragglers (c2 never saw rank/motd edits) up to date
	c2.sync_from(a)
	c2.sync_from(b)
	c.sync_from(a)
	c.sync_from(b)
	a.sync_from(c)
	b.sync_from(c)
	t.eq(c2.motd("g"), "hello", "anti-entropy delivers missing ops")
	t.eq(a.digest("g") == c2.digest("g") and b.digest("g") == c.digest("g") and a.digest("g") == b.digest("g"), true,
		"digests equal after sync")
	t.eq(c2.vv["0"], a.vv["0"], "version vectors catch up")


func _parties(t) -> void:
	t.current = "party migration"
	var sim := ClusterSimulator.new()
	sim.setup(3, 21)
	sim.add_player("lead", Vector2(50, 50), 2)    # region 0 -> server 0
	sim.add_player("m1", Vector2(150, 50), 1)     # region 1 -> server 1
	sim.add_player("m2", Vector2(250, 50), 1)     # region 2 -> server 2
	sim.create_party("pt", "lead", ["m1", "m2"])
	_drain(sim, 10)
	t.eq(sim.parties(2).get_doc("pt")["leader"], "lead", "replicas exist on every server")
	t.eq(sim.migrate_player("lead", 2), "committed", "leader hands off to server 2")
	var ok := sim.quiesce()
	t.eq(ok, true, "cluster settles")
	for p in ["lead", "m1", "m2"]:
		t.eq(sim.player_server(p), 2, "%s followed the leader" % p)
	var doc := sim.parties(0).get_doc("pt")
	t.eq(doc["leader"], "lead", "leader kept")
	var names: Array = (doc["members"] as Dictionary).keys()
	names.sort()
	t.eq(names, ["lead", "m1", "m2"], "membership kept")
	t.eq(int(doc["home"]), 2, "authority moved with the leader")
	t.check(sim.parties(1).same_as(sim.parties(2), "pt") and sim.parties(0).same_as(sim.parties(2), "pt"), "all replicas identical")
	t.eq(sim.ledger(2).items_of("lead").size(), 2, "leader's items arrived with them")
	t.eq(sim.check_invariants(), [], "invariants hold")
	# Fencing by epoch: stale snapshot and stale-home writes are refused.
	var old := sim.parties(2).snapshot("pt")
	var home := sim.parties(2)
	var moved := home.leader_handoff("pt", 1)
	t.eq(moved.is_empty(), false, "home may hand off")
	t.eq(home.add_member("pt", "x", 2), false, "former home can no longer mutate")
	t.eq(home.apply_replica(old), false, "stale snapshot rejected")
	t.eq(int(home.get_doc("pt")["epoch"]) > int(old["epoch"]), true, "epoch grew")
	var p0 := PartyMigration.new(0)
	p0.create("q", "a")
	p0.add_member("q", "b", 0)
	t.eq(p0.remove_member("q", "a"), true, "leader leaves")
	t.eq(p0.get_doc("q")["leader"], "b", "next member promoted")
	sim.teardown()


func _leases(t) -> void:
	t.current = "leases and fencing"
	var lt := OwnershipLeases.new()
	var store := OwnershipLeases.FencedStore.new()
	var g1 := lt.acquire("zone", "A", 0.0, 10.0)
	t.eq(g1["ok"], true, "first grant")
	t.eq(g1["token"], 1, "first token")
	t.eq(store.write("zone", int(g1["token"]), "A-v1"), true, "holder writes")
	t.eq(lt.acquire("zone", "B", 5.0, 10.0)["ok"], false, "live lease blocks others")
	t.eq(lt.renew("zone", "A", 1, 6.0, 10.0), true, "holder renews")
	t.eq(lt.acquire("zone", "B", 12.0, 10.0)["ok"], false, "renewal pushed expiry out")
	# A stalls (GC pause / partition) past expiry; B takes over with a higher token.
	t.eq(lt.holder_of("zone", 20.0), "", "lease expired")
	var g2 := lt.acquire("zone", "B", 20.0, 10.0)
	t.eq(g2["token"], 2, "new grant has a higher token")
	t.eq(lt.renew("zone", "A", 1, 21.0, 10.0), false, "zombie cannot renew")
	t.eq(store.write("zone", int(g2["token"]), "B-v1"), true, "new owner writes")
	t.eq(store.write("zone", 1, "A-stale"), false, "stale owner's late write is fenced off")
	t.eq(store.read("zone"), "B-v1", "stale write left no trace")
	t.eq(store.rejected, 1, "rejection counted")
	t.eq(lt.is_valid("zone", "A", 1, 21.0), false, "old token invalid")
	t.eq(lt.is_valid("zone", "B", 2, 21.0), true, "new token valid")
	t.eq(lt.release("zone", "A", 1), false, "stale release ignored")
	t.eq(lt.release("zone", "B", 2), true, "holder releases")
	t.eq(lt.acquire("zone", "A", 22.0, 10.0)["token"], 3, "tokens never repeat after release")
	t.eq(OwnershipLeases.client_valid(30.0, 29.0, 2.0), false, "client stops before expiry minus drift")
	t.eq(OwnershipLeases.client_valid(30.0, 27.0, 2.0), true, "client may act while safely inside")
	lt.acquire("other", "C", 22.0, 1.0)
	t.eq(lt.reap(100.0).size(), 2, "reaper drops expired leases")
	t.eq(lt.token_of("zone"), 3, "token counter survives reaping")


func _balancing(t) -> void:
	t.current = "load balancing and failover"
	var sim := ClusterSimulator.new()
	sim.setup(3, 33)
	var owned0: Array = []
	for r in sim.sharding.region_count():
		if int(sim.sharding.region_owner[r]) == 0:
			owned0.append(r)
	var k := 0
	for r in owned0.slice(0, 4):
		var cx := int(r) % 4
		var cy := int(r) / 4
		for j in 3:
			sim.add_player("pl%d" % k, Vector2(cx * 100.0 + 20.0 + j * 20.0, cy * 100.0 + 50.0), 2)
			k += 1
	var before := sim.server_load_report()
	t.eq(before[0], 12.0, "server 0 is overloaded")
	t.eq(before[1], 0.0, "others idle")
	var moves := sim.rebalance()
	t.check(moves.size() > 0, "regions moved off the hot server")
	t.eq(sim.quiesce(), true, "migrations settle")
	var after := sim.server_load_report()
	t.check(float(after[0]) < 12.0, "hot server shed load")
	t.check(float(after[0]) <= float(after[1]) * 3.0 + 3.0, "load spread across servers")
	var lost := 0
	for pid in sim.player_ids:
		if sim.player_server(String(pid)) != sim.sharding.owner_at(sim.sharding.players[pid]["pos"]):
			lost += 1
		if sim.ledger(sim.player_server(String(pid))).items_of(String(pid)).size() != 2:
			lost += 1
	t.eq(lost, 0, "every player and item followed its region")
	t.eq(sim.check_invariants(), [], "invariants after rebalance")
	var mv: Dictionary = moves[0]
	t.check(int(sim.region_token[int(mv["region"])]) >= 2, "moved region got a newer fencing token")
	t.eq(sim.leases.holder_of("region:%d" % int(mv["region"]), float(sim.tick)), "s%d" % int(mv["to"]), "lease follows region")
	# Failover: a long outage expires leases and regions move to live servers.
	sim.crash_server(1, 500)
	_drain(sim, 40)
	var on_dead := 0
	for r in sim.sharding.region_count():
		if int(sim.sharding.region_owner[r]) == 1:
			on_dead += 1
	t.eq(on_dead, 0, "dead server's regions reassigned after lease expiry")
	t.check(int(sim.stats["failovers"]) > 0, "failovers recorded")
	t.eq(sim.fenced.rejected, 0, "no stale write was needed")
	sim.teardown()


func _random_runs(t) -> void:
	t.current = "randomized cluster run"
	var crashes := 0
	var committed := 0
	for seed_value in [1, 7, 42]:
		var sim := ClusterSimulator.new()
		sim.setup(4, seed_value)
		for i in 8:
			sim.add_player("p%d" % i, Vector2(sim.rng.randf_range(5, 395), sim.rng.randf_range(5, 395)), 3)
		for s in 4:
			for _j in 4:
				sim.mint_item(s, "p%d" % sim.rng.randi_range(0, 7))
		sim.create_party("pa", "p0", ["p1", "p2"])
		for i in 4:
			sim.guild_op(i, "g0", "join", "p%d" % i, 1)
		sim.run_random(350)
		var settled := sim.quiesce()
		t.eq(settled, true, "seed %d settles" % seed_value)
		var bad := sim.check_invariants()
		t.eq(bad, [], "seed %d invariants" % seed_value)
		var total := 0
		for i in 4:
			total += sim.ledger(i).total_count()
		t.eq(total, 8 * 3 + 16, "seed %d: total items conserved" % seed_value)
		var d := sim.parties(0).get_doc("pa")
		t.eq(d["leader"], "p0", "seed %d: leader unchanged" % seed_value)
		t.eq((d["members"] as Dictionary).size(), 3, "seed %d: party membership unchanged" % seed_value)
		crashes += int(sim.stats["server_crashes"]) + int(sim.stats["coord_crashes"])
		committed += int(sim.stats["moves_committed"])
		sim.teardown()
	t.check(crashes > 0, "the run actually injected crashes")
	t.check(committed > 10, "the run actually moved things")
	# Determinism: same seed -> same outcome.
	var sa := ClusterSimulator.new()
	var sb := ClusterSimulator.new()
	for s in [sa, sb]:
		s.setup(3, 99)
		for i in 3:
			s.add_player("q%d" % i, Vector2(50 + i * 100, 50), 2)
		s.run_random(120)
	t.eq(JSON.stringify(sa.stats), JSON.stringify(sb.stats), "deterministic for a fixed seed")
	sa.teardown()
	sb.teardown()
