extends RefCounted
## In-process simulation of N game servers: message queues with random latency and reordering,
## server crashes (durable state, held messages) and coordinator crashes, driving item moves via
## TransactionCoordinator 2PC, guild op replication, party migration, region leases with fencing
## and load-based region reassignment with player migration.
##
## Original GDScript implementation; concept references are listed in the component files
## (item_ledger.gd, guild_sync.gd, party_migration.gd, ownership_leases.gd).
## License of this file: same as the project; no third-party code included.
##
## Model assumptions: each server's ledger/guild/party state is durable across a crash (a crash
## only stops processing; messages addressed to a down server are held and delivered after
## restart); 2PC prepare is a synchronous call that fails if the server is down; commit/abort
## decisions travel as queued messages and are idempotent at the receiver.

const ItemLedger = preload("res://scripts/server/item_ledger.gd")
const GuildSync = preload("res://scripts/server/guild_sync.gd")
const PartyMigration = preload("res://scripts/server/party_migration.gd")
const OwnershipLeases = preload("res://scripts/server/ownership_leases.gd")
const TransactionCoordinator = preload("res://scripts/server/transaction_coordinator.gd")
const WorldSharding = preload("res://scripts/server/world_sharding.gd")

var rng: RandomNumberGenerator = RandomNumberGenerator.new()
var n: int = 3
var tick: int = 0
var min_latency: int = 1
var max_latency: int = 4
var lease_ttl: float = 20.0
var gossip_every: int = 25

var alive: Array = []              ## bool per server
var ledgers: Array = []
var guild_replicas: Array = []
var party_dirs: Array = []
var coordinator: TransactionCoordinator = TransactionCoordinator.new()
var sharding: WorldSharding = WorldSharding.new()
var leases: OwnershipLeases = OwnershipLeases.new()
var fenced: OwnershipLeases.FencedStore = OwnershipLeases.FencedStore.new()

var queue: Array = []              ## {at, seq, to, kind, data}
var restart_at: Dictionary = {}    ## server -> tick
var coord_recover_at: int = -1
var tx_meta: Dictionary = {}       ## tx id -> {pid, tid}
var player_ids: Array = []
var party_ids: Array = []
var region_token: Dictionary = {}  ## region -> fencing token
var minted: int = 0
var stats: Dictionary = {"moves_committed": 0, "moves_aborted": 0, "moves_crashed": 0,
	"migrations": 0, "failovers": 0, "server_crashes": 0, "coord_crashes": 0, "region_moves": 0}
var _seq: int = 0


func setup(servers: int, seed_value: int, cols: int = 4, rows: int = 4, cell: float = 100.0) -> void:
	n = servers
	rng.seed = seed_value
	alive.clear()
	ledgers.clear()
	guild_replicas.clear()
	party_dirs.clear()
	for i in n:
		alive.append(true)
		ledgers.append(ItemLedger.new(i))
		guild_replicas.append(GuildSync.new(i))
		party_dirs.append(PartyMigration.new(i))
		coordinator.add_participant("s%d" % i, _prepare.bind(i), _commit.bind(i), _abort.bind(i))
	sharding.setup(cols, rows, cell, n)
	sharding.assign_initial([])
	for r in sharding.region_count():
		_claim_region(r, int(sharding.region_owner[r]))


## Breaks the callable->self reference cycle so the simulator can be freed.
func teardown() -> void:
	coordinator._participants.clear()


func ledger(i: int) -> ItemLedger:
	return ledgers[i]


func guilds(i: int) -> GuildSync:
	return guild_replicas[i]


func parties(i: int) -> PartyMigration:
	return party_dirs[i]


func is_alive(i: int) -> bool:
	return bool(alive[i])


# ------------------------------------------------------------------ messaging

func _send(to: int, kind: String, data: Variant) -> void:
	_seq += 1
	queue.append({"at": tick + rng.randi_range(min_latency, max_latency), "seq": _seq,
		"to": to, "kind": kind, "data": data})


func _prepare(tx_id: String, op: Variant, server: int) -> bool:
	if not is_alive(server):
		return false
	return ledger(server).prepare(tx_id, op)


func _commit(tx_id: String, server: int) -> void:
	_send(server, "commit", tx_id)


func _abort(tx_id: String, server: int) -> void:
	_send(server, "abort", tx_id)


func _deliver_due() -> void:
	queue.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["at"]) < int(b["at"]) or (int(a["at"]) == int(b["at"]) and int(a["seq"]) < int(b["seq"])))
	var keep: Array = []
	for m in queue:
		var msg: Dictionary = m
		var to := int(msg["to"])
		if int(msg["at"]) > tick or not is_alive(to):
			keep.append(msg)
			continue
		var kind := String(msg["kind"])
		if kind == "commit":
			ledger(to).commit(String(msg["data"]))
		elif kind == "abort":
			ledger(to).abort(String(msg["data"]))
		elif kind == "guild_op":
			guilds(to).receive(msg["data"])
		elif kind == "party_doc":
			parties(to).apply_replica(msg["data"])
	queue = keep


# ------------------------------------------------------------------ world setup

func mint_item(server: int, owner: String, def: String = "item") -> String:
	minted += 1
	return ledger(server).mint(owner, def)


func add_player(pid: String, pos: Vector2, items_count: int = 0) -> void:
	var srv := sharding.owner_at(pos)
	sharding.track_player(pid, pos, srv)
	player_ids.append(pid)
	for _i in items_count:
		mint_item(srv, pid)


func player_server(pid: String) -> int:
	return sharding.owner_of(pid)


func create_party(party_id: String, leader: String, members: Array = []) -> void:
	var home := player_server(leader)
	parties(home).create(party_id, leader)
	for m in members:
		parties(home).add_member(party_id, String(m), player_server(String(m)))
	party_ids.append(party_id)
	_broadcast_party(party_id, home)


func _broadcast_party(party_id: String, from: int) -> void:
	var snap := parties(from).snapshot(party_id)
	if snap.is_empty():
		return
	for i in n:
		if i != from:
			_send(i, "party_doc", snap.duplicate(true))


# ------------------------------------------------------------------ item moves (2PC)

## Moves items between servers atomically. Returns "committed" | "aborted" | "crashed" |
## "rejected" (precondition failed, nothing started).
func move_items(from: int, to: int, ids: Array, meta: Dictionary = {}) -> String:
	if from == to or coordinator.crashed or not is_alive(from) or not is_alive(to):
		return "rejected"
	for id in ids:
		if not ledger(from).is_active(String(id)):
			return "rejected"
	var ops := {"s%d" % from: {"kind": "out", "ids": ids.duplicate()},
		"s%d" % to: {"kind": "in", "recs": ledger(from).snapshot(ids)}}
	var tx := coordinator.begin(ops)
	if not meta.is_empty():
		tx_meta[tx] = meta
	var res := coordinator.run(tx)
	if res == "crashed":
		stats["moves_crashed"] = int(stats["moves_crashed"]) + 1
		coord_recover_at = tick + rng.randi_range(3, 10)
		return "crashed"
	_finish_tx(tx, res)
	return res


func _finish_tx(tx: String, result: String) -> void:
	if result == "committed":
		stats["moves_committed"] = int(stats["moves_committed"]) + 1
	else:
		stats["moves_aborted"] = int(stats["moves_aborted"]) + 1
	if not tx_meta.has(tx):
		return
	var meta: Dictionary = tx_meta[tx]
	tx_meta.erase(tx)
	var tid := String(meta["tid"])
	if result == "committed":
		sharding.ack_transfer(tid)
		sharding.release_transfer(tid)
		stats["migrations"] = int(stats["migrations"]) + 1
	else:
		sharding.abort_transfer(tid)


## Player handoff: freeze (sharding), move the player's items with a 2PC, then flip ownership.
func migrate_player(pid: String, dest: int) -> String:
	var from := player_server(pid)
	if from == dest or coordinator.crashed or not is_alive(from) or not is_alive(dest):
		return "rejected"
	_seq += 1
	var tid := "t%d" % _seq
	if sharding.begin_transfer(pid, dest, tid) == "":
		return "rejected"
	var ids := ledger(from).items_of(pid)
	sharding.send_state(tid, {"items": ids.size()})
	var ops := {"s%d" % from: {"kind": "out", "ids": ids},
		"s%d" % dest: {"kind": "in", "recs": ledger(from).snapshot(ids)}}
	var tx := coordinator.begin(ops)
	tx_meta[tx] = {"pid": pid, "tid": tid}
	var res := coordinator.run(tx)
	if res == "crashed":
		stats["moves_crashed"] = int(stats["moves_crashed"]) + 1
		coord_recover_at = tick + rng.randi_range(3, 10)
		return "crashed"
	_finish_tx(tx, res)
	return res


# ------------------------------------------------------------------ guilds

func guild_op(server: int, gid: String, type: String, pid: String = "", arg: int = 0, text: String = "") -> Dictionary:
	if not is_alive(server):
		return {}
	var g := guilds(server)
	var op: Dictionary
	if type == "join":
		op = g.join(gid, pid, arg)
	elif type == "rank":
		op = g.set_rank(gid, pid, arg)
	elif type == "kick":
		op = g.kick(gid, pid)
	elif type == "motd":
		op = g.set_motd(gid, text)
	else:
		op = g.deposit(gid, arg)
	for i in n:
		if i != server:
			_send(i, "guild_op", op)
	return op


func gossip_pair(a: int, b: int) -> void:
	if is_alive(a) and is_alive(b):
		guilds(a).sync_from(guilds(b))
		guilds(b).sync_from(guilds(a))


# ------------------------------------------------------------------ leases and regions

func _claim_region(r: int, server: int) -> bool:
	var key := "region:%d" % r
	var res := leases.acquire(key, "s%d" % server, float(tick), lease_ttl)
	if not bool(res["ok"]):
		return false
	region_token[r] = int(res["token"])
	fenced.write(key, int(res["token"]), "s%d" % server)
	return true


func _renew_leases() -> void:
	for r in sharding.region_count():
		var o := int(sharding.region_owner[r])
		if not is_alive(o):
			continue
		var key := "region:%d" % r
		if not leases.renew(key, "s%d" % o, int(region_token.get(r, 0)), float(tick), lease_ttl):
			_claim_region(r, o)


## Regions of dead servers whose lease expired move to the least-loaded live server.
func _failover() -> void:
	for r in sharding.region_count():
		var o := int(sharding.region_owner[r])
		if is_alive(o) or leases.holder_of("region:%d" % r, float(tick)) != "":
			continue
		var best := -1
		var best_count := 1 << 30
		for s in n:
			if not is_alive(s):
				continue
			var cnt := 0
			for rr in sharding.region_count():
				if int(sharding.region_owner[rr]) == s:
					cnt += 1
			if cnt < best_count:
				best_count = cnt
				best = s
		if best >= 0 and _claim_region(r, best):
			sharding.region_owner[r] = best
			stats["failovers"] = int(stats["failovers"]) + 1


func region_loads() -> Array:
	var loads: Array = []
	loads.resize(sharding.region_count())
	loads.fill(0.0)
	for pid in player_ids:
		var p: Dictionary = sharding.players[pid]
		var r := sharding.region_of(p["pos"])
		loads[r] = float(loads[r]) + 1.0
	return loads


func server_load_report() -> Array:
	return sharding.server_loads(region_loads())


## Servers report load; hot regions are reassigned (lease handed over with a fresh fencing token)
## and the players standing in them migrate to the new owner. Returns the region moves.
func rebalance() -> Array:
	var moves := sharding.rebalance(region_loads())
	for m in moves:
		var mv: Dictionary = m
		var r := int(mv["region"])
		var key := "region:%d" % r
		leases.release(key, "s%d" % int(mv["from"]), int(region_token.get(r, 0)))
		_claim_region(r, int(mv["to"]))
		stats["region_moves"] = int(stats["region_moves"]) + 1
	migrate_misplaced_players()
	return moves


## Players whose region is owned by another server move there.
func migrate_misplaced_players() -> int:
	var count := 0
	for pid in player_ids:
		var p: Dictionary = sharding.players[pid]
		var want := sharding.owner_at(p["pos"])
		if want != player_server(String(pid)) and migrate_player(String(pid), want) == "committed":
			count += 1
	return count


# ------------------------------------------------------------------ parties

## Newest replica of a party across all directories (by epoch, then version).
func _newest_doc(pp: String) -> Dictionary:
	var best := {}
	for i in n:
		var d := parties(i).get_doc(pp)
		if d.is_empty():
			continue
		if best.is_empty() or int(d["epoch"]) * 1000000 + int(d["version"]) > int(best["epoch"]) * 1000000 + int(best["version"]):
			best = d
	return best


## The home server reconciles the party doc with where its members really are.
func _sync_party(pp: String) -> void:
	var newest := _newest_doc(pp)
	if newest.is_empty():
		return
	var home := int(newest["home"])
	if not is_alive(home):
		return
	var doc := parties(home).get_doc(pp)
	if doc.is_empty() or int(doc["epoch"]) < int(newest["epoch"]) or int(doc["version"]) < int(newest["version"]):
		return  # the snapshot has not reached the new home yet
	var ls := player_server(String(doc["leader"]))
	if ls != home:
		if is_alive(ls) and not parties(home).leader_handoff(pp, ls).is_empty():
			_broadcast_party(pp, home)
		return
	var changed := false
	var ms: Dictionary = doc["members"]
	for m in ms.keys():
		if parties(home).set_member_server(pp, String(m), player_server(String(m))):
			changed = true
	if changed:
		_broadcast_party(pp, home)


func _party_followers() -> void:
	for pp in party_ids:
		var doc := _newest_doc(String(pp))
		if doc.is_empty():
			continue
		var ls := player_server(String(doc["leader"]))
		for step_item in parties(int(doc["home"])).follow_plan(String(pp), ls):
			var s: Dictionary = step_item
			migrate_player(String(s["player"]), int(s["to"]))


func parties_settled() -> bool:
	for pp in party_ids:
		var doc := _newest_doc(String(pp))
		if doc.is_empty():
			continue
		var ls := player_server(String(doc["leader"]))
		var ms: Dictionary = doc["members"]
		for m in ms.keys():
			if player_server(String(m)) != ls or int(ms[m]) != ls:
				return false
		if int(doc["home"]) != ls:
			return false
	return true


# ------------------------------------------------------------------ faults

func crash_server(i: int, down_for: int) -> void:
	if not is_alive(i):
		return
	alive[i] = false
	restart_at[i] = tick + down_for
	stats["server_crashes"] = int(stats["server_crashes"]) + 1


func restart_server(i: int) -> void:
	alive[i] = true
	restart_at.erase(i)


func live_count() -> int:
	var c := 0
	for i in n:
		if is_alive(i):
			c += 1
	return c


func recover_coordinator() -> void:
	var res := coordinator.recover()
	coord_recover_at = -1
	for tx in res.keys():
		_finish_tx(String(tx), String(res[tx]))


# ------------------------------------------------------------------ time

func step() -> void:
	tick += 1
	for i in restart_at.keys():
		if tick >= int(restart_at[i]):
			restart_server(int(i))
	if coordinator.crashed and coord_recover_at >= 0 and tick >= coord_recover_at:
		recover_coordinator()
	_deliver_due()
	if tick % 5 == 0:
		_renew_leases()
	_failover()
	if tick % 3 == 0:
		for pidp in party_ids:
			_sync_party(String(pidp))
		_party_followers()
	if gossip_every > 0 and tick % gossip_every == 0 and n >= 2:
		gossip_pair(rng.randi_range(0, n - 1), rng.randi_range(0, n - 1))


## Random workload with faults. Deterministic for a given seed.
func run_random(ticks: int) -> void:
	for _t in ticks:
		var roll := rng.randf()
		if roll < 0.30:
			var a := rng.randi_range(0, n - 1)
			var b := rng.randi_range(0, n - 1)
			var ids := ledger(a).ids_sorted()
			if not ids.is_empty():
				var take: Array = [ids[rng.randi_range(0, ids.size() - 1)]]
				if rng.randf() < 0.4 and ids.size() > 1:
					take.append(ids[rng.randi_range(0, ids.size() - 1)])
				var uniq: Array = []
				for id in take:
					if not uniq.has(id):
						uniq.append(id)
				move_items(a, b, uniq)
		elif roll < 0.42:
			var s := rng.randi_range(0, n - 1)
			var kinds := ["join", "rank", "kick", "motd", "deposit"]
			var k: String = kinds[rng.randi_range(0, kinds.size() - 1)]
			guild_op(s, "g%d" % rng.randi_range(0, 1), k, "p%d" % rng.randi_range(0, 5),
				rng.randi_range(0, 5), "m%d" % rng.randi_range(0, 99))
		elif roll < 0.47 and live_count() > 1:
			crash_server(rng.randi_range(0, n - 1), rng.randi_range(4, 15))
		elif roll < 0.51 and not coordinator.crashed:
			coordinator.crash_point = "before_decision" if rng.randf() < 0.5 else "after_decision"
			stats["coord_crashes"] = int(stats["coord_crashes"]) + 1
		elif roll < 0.62 and not player_ids.is_empty():
			migrate_player(String(player_ids[rng.randi_range(0, player_ids.size() - 1)]), rng.randi_range(0, n - 1))
		elif roll < 0.65 and not party_ids.is_empty():
			var pp := String(party_ids[rng.randi_range(0, party_ids.size() - 1)])
			for i in n:
				if parties(i).has_party(pp):
					migrate_player(String(parties(i).get_doc(pp)["leader"]), rng.randi_range(0, n - 1))
					break
		elif roll < 0.68 and live_count() == n:
			rebalance()
		step()


func idle() -> bool:
	if not queue.is_empty() or coordinator.crashed:
		return false
	for i in n:
		if not (ledger(i).pending as Dictionary).is_empty():
			return false
	return true


## Heals everything: restarts servers, recovers the coordinator, drains queues, runs anti-entropy
## and lets parties re-converge. Returns false if it did not settle.
func quiesce(max_ticks: int = 600) -> bool:
	coordinator.crash_point = ""
	for i in n:
		restart_server(i)
	for _t in max_ticks:
		if coordinator.crashed:
			recover_coordinator()
		step()
		if idle() and parties_settled():
			break
	for _i in 6:
		step()  # a few quiet ticks so lease renewals catch up
	for a in n:
		for b in n:
			gossip_pair(a, b)
	for a in n:
		for b in n:
			gossip_pair(a, b)
	return idle() and parties_settled()


# ------------------------------------------------------------------ invariants

## Returns human-readable violations (empty = all good). Call after quiesce().
func check_invariants() -> Array:
	var bad: Array = []
	var total := 0
	for i in n:
		total += ledger(i).total_count()
		if ledger(i).active_count() != ledger(i).total_count():
			bad.append("server %d holds non-active items" % i)
	if total != minted:
		bad.append("items not conserved: %d present, %d minted" % [total, minted])
	var dups := ItemLedger.find_duplicates(ledgers)
	if not dups.is_empty():
		bad.append("duplicate item ids: %s" % str(dups.keys()))
	for tx in coordinator.txs.keys():
		var rec: Dictionary = coordinator.txs[tx]
		if String(rec["state"]) != "done":
			bad.append("tx %s not finished" % tx)
	for pid in player_ids:
		var p: Dictionary = sharding.players[pid]
		if String(p["state"]) != "stable":
			bad.append("player %s not stable" % pid)
	for gid in ["g0", "g1"]:
		for i in range(1, n):
			if guilds(i).digest(gid) != guilds(0).digest(gid):
				bad.append("guild %s diverged on server %d" % [gid, i])
	for pidp in party_ids:
		for i in range(1, n):
			if not parties(i).same_as(parties(0), String(pidp)):
				bad.append("party %s diverged on server %d" % [pidp, i])
	for r in sharding.region_count():
		var o := int(sharding.region_owner[r])
		if leases.holder_of("region:%d" % r, float(tick)) != "s%d" % o:
			bad.append("region %d lease/owner mismatch" % r)
	return bad
