extends RefCounted
## Cross-server guild state: per-server replicas of versioned guild documents, an op log that is
## replicated (push + anti-entropy) and a deterministic, order-independent conflict resolution.
##
## Original GDScript implementation. Concept references only (no code copied):
##   - Lamport, "Time, Clocks, and the Ordering of Events in a Distributed System" (1978):
##     logical timestamps, ties broken by origin id.
##   - Shapiro et al., "Conflict-free Replicated Data Types" (2011): LWW-register, grow-only/PN
##     counter and add/remove-wins sets; ops are commutative and idempotent so replicas converge
##     regardless of delivery order or duplication.
##   - Version-vector anti-entropy (Parker et al. 1983 / Dynamo-style gossip).
## License of this file: same as the project; no third-party code included.
##
## Conflict policy (documented because it is a game rule, not an accident):
##   - rank / motd: last-writer-wins by (lamport, origin).
##   - kick vs concurrent rank change or concurrent join: the kick wins (remove-wins). A member
##     can only come back through a join that has *observed* the kick (join carries the kick
##     timestamp it saw), i.e. a causally later re-invite.
##   - treasury deposits: summed per unique op id, so a replayed op never double-counts.

var server_id: int = 0
var clock: int = 0                  ## Lamport counter
var guilds: Dictionary = {}         ## gid -> doc {id, members, motd, treasury, version}
var log: Dictionary = {}            ## op id ("origin:seq") -> op
var vv: Dictionary = {}             ## origin -> highest contiguous seq applied
var _seq: int = 0


func _init(p_server_id: int = 0) -> void:
	server_id = p_server_id


func _ts() -> int:
	return (clock << 10) | server_id


static func _ts_clock(ts: int) -> int:
	return ts >> 10


func _doc(gid: String) -> Dictionary:
	if not guilds.has(gid):
		guilds[gid] = {"id": gid, "members": {}, "motd": {"text": "", "ts": 0}, "treasury": {}, "version": 0}
	return guilds[gid]


# ------------------------------------------------------------------ local edits

func _local(gid: String, type: String, args: Dictionary) -> Dictionary:
	clock += 1
	_seq += 1
	var op := {"id": "%d:%d" % [server_id, _seq], "origin": server_id, "seq": _seq, "gid": gid,
		"type": type, "args": args, "ts": _ts()}
	_apply(op)
	return op


func join(gid: String, pid: String, rank: int) -> Dictionary:
	var kick := 0
	var d := _doc(gid)
	var members: Dictionary = d["members"]
	if members.has(pid):
		var m: Dictionary = members[pid]
		kick = int(m["kick_ts"])
	return _local(gid, "join", {"pid": pid, "rank": rank, "seen_kick": kick})


func set_rank(gid: String, pid: String, rank: int) -> Dictionary:
	return _local(gid, "rank", {"pid": pid, "rank": rank})


func kick(gid: String, pid: String) -> Dictionary:
	return _local(gid, "kick", {"pid": pid})


func set_motd(gid: String, text: String) -> Dictionary:
	return _local(gid, "motd", {"text": text})


func deposit(gid: String, amount: int) -> Dictionary:
	return _local(gid, "deposit", {"amount": amount})


# ------------------------------------------------------------------ replication

## Applies a remote op. Returns true if it was new. Safe to call repeatedly and out of order.
func receive(op: Dictionary) -> bool:
	var id := String(op["id"])
	if log.has(id):
		return false
	clock = maxi(clock, _ts_clock(int(op["ts"])))
	_apply(op)
	return true


func ops_after(remote_vv: Dictionary) -> Array:
	var out: Array = []
	for id in log.keys():
		var op: Dictionary = log[id]
		if int(op["seq"]) > int(remote_vv.get(str(op["origin"]), 0)):
			out.append(op)
	return out


## Pull-based anti-entropy from another replica. Returns number of new ops applied.
func sync_from(other: Object) -> int:
	var n := 0
	var ops: Array = other.ops_after(_vv_strkeys())
	ops.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["ts"]) < int(b["ts"]))
	for op in ops:
		if receive(op):
			n += 1
	return n


func _vv_strkeys() -> Dictionary:
	var out := {}
	for k in vv.keys():
		out[str(k)] = vv[k]
	return out


func _apply(op: Dictionary) -> void:
	var id := String(op["id"])
	log[id] = op
	var origin := int(op["origin"])
	var key := str(origin)
	var top := int(vv.get(key, 0))
	while log.has("%d:%d" % [origin, top + 1]):
		top += 1
	vv[key] = top
	var gid := String(op["gid"])
	var d := _doc(gid)
	d["version"] = int(d["version"]) + 1
	var ts := int(op["ts"])
	var args: Dictionary = op["args"]
	var type := String(op["type"])
	if type == "motd":
		var motd: Dictionary = d["motd"]
		if ts > int(motd["ts"]):
			motd["ts"] = ts
			motd["text"] = String(args["text"])
	elif type == "deposit":
		var tre: Dictionary = d["treasury"]
		tre[id] = int(args["amount"])
	else:
		var m := _member(d, String(args["pid"]))
		if type == "join":
			if ts > int(m["join_ts"]):
				m["join_ts"] = ts
				m["join_seen"] = int(args["seen_kick"])
			_set_rank(m, int(args["rank"]), ts)
		elif type == "rank":
			_set_rank(m, int(args["rank"]), ts)
		elif type == "kick":
			m["kick_ts"] = maxi(int(m["kick_ts"]), ts)


func _member(d: Dictionary, pid: String) -> Dictionary:
	var members: Dictionary = d["members"]
	if not members.has(pid):
		members[pid] = {"rank": 0, "rank_ts": 0, "join_ts": 0, "join_seen": 0, "kick_ts": 0}
	return members[pid]


func _set_rank(m: Dictionary, rank: int, ts: int) -> void:
	if ts > int(m["rank_ts"]):
		m["rank_ts"] = ts
		m["rank"] = rank


# ------------------------------------------------------------------ queries

func _present(m: Dictionary) -> bool:
	if int(m["join_ts"]) == 0:
		return false
	return int(m["kick_ts"]) == 0 or int(m["join_seen"]) >= int(m["kick_ts"])


func is_member(gid: String, pid: String) -> bool:
	if not guilds.has(gid):
		return false
	var members: Dictionary = (guilds[gid] as Dictionary)["members"]
	return members.has(pid) and _present(members[pid])


func rank_of(gid: String, pid: String) -> int:
	if not is_member(gid, pid):
		return -1
	var m: Dictionary = ((guilds[gid] as Dictionary)["members"] as Dictionary)[pid]
	return int(m["rank"])


func members(gid: String) -> Array:
	var out: Array = []
	if guilds.has(gid):
		var ms: Dictionary = (guilds[gid] as Dictionary)["members"]
		for pid in ms.keys():
			if _present(ms[pid]):
				out.append(pid)
	out.sort()
	return out


func motd(gid: String) -> String:
	if not guilds.has(gid):
		return ""
	var m: Dictionary = (guilds[gid] as Dictionary)["motd"]
	return String(m["text"])


func treasury(gid: String) -> int:
	var sum := 0
	if guilds.has(gid):
		var tre: Dictionary = (guilds[gid] as Dictionary)["treasury"]
		for id in tre.keys():
			sum += int(tre[id])
	return sum


func version(gid: String) -> int:
	if not guilds.has(gid):
		return 0
	return int((guilds[gid] as Dictionary)["version"])


## Canonical string of the player-visible state; equal digests mean converged replicas.
func digest(gid: String) -> String:
	var parts: Array = []
	for pid in members(gid):
		parts.append("%s=%d" % [pid, rank_of(gid, String(pid))])
	return "m[%s]|motd=%s|gold=%d" % [",".join(PackedStringArray(parts)), motd(gid), treasury(gid)]
