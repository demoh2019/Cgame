extends RefCounted
## Cross-server party directory: the party follows its leader through zone handoffs and members
## hosted on different servers keep identical replicas.
##
## Original GDScript implementation. Concept references only (no code copied):
##   - Single-writer home + epoch (term) numbers so a stale former home cannot overwrite newer
##     state - the same fencing idea as Kleppmann, "How to do distributed locking" (2016) and
##     the term/epoch counters in Raft (Ongaro & Ousterhout, 2014).
##   - Versioned snapshot replication: higher (epoch, version) wins, replays are no-ops.
## License of this file: same as the project; no third-party code included.
##
## A party doc = {id, leader, home, epoch, version, members: {player -> server}}.
## Only the home server (the leader's server) may mutate; leader_handoff() moves the home and
## bumps the epoch. Everyone else just apply_replica()s snapshots.

var server_id: int = 0
var parties: Dictionary = {}   ## party id -> doc


func _init(p_server_id: int = 0) -> void:
	server_id = p_server_id


func has_party(id: String) -> bool:
	return parties.has(id)


func get_doc(id: String) -> Dictionary:
	if not parties.has(id):
		return {}
	return parties[id]


func snapshot(id: String) -> Dictionary:
	return get_doc(id).duplicate(true)


## Creates a party led by `leader`, who is hosted on this server (this server becomes home).
func create(id: String, leader: String) -> bool:
	if parties.has(id):
		return false
	parties[id] = {"id": id, "leader": leader, "home": server_id, "epoch": 1, "version": 1,
		"members": {leader: server_id}}
	return true


func _mutable(id: String) -> bool:
	return parties.has(id) and int((parties[id] as Dictionary)["home"]) == server_id


func _bump(doc: Dictionary) -> void:
	doc["version"] = int(doc["version"]) + 1


func add_member(id: String, pid: String, server: int) -> bool:
	if not _mutable(id):
		return false
	var doc: Dictionary = parties[id]
	var ms: Dictionary = doc["members"]
	if ms.has(pid):
		return false
	ms[pid] = server
	_bump(doc)
	return true


## Removing the leader promotes the lowest-sorted remaining member; an empty party disbands.
func remove_member(id: String, pid: String) -> bool:
	if not _mutable(id):
		return false
	var doc: Dictionary = parties[id]
	var ms: Dictionary = doc["members"]
	if not ms.has(pid):
		return false
	ms.erase(pid)
	if ms.is_empty():
		parties.erase(id)
		return true
	if String(doc["leader"]) == pid:
		var rest: Array = ms.keys()
		rest.sort()
		doc["leader"] = rest[0]
		doc["home"] = int(ms[rest[0]])
		doc["epoch"] = int(doc["epoch"]) + 1
	_bump(doc)
	return true


func set_member_server(id: String, pid: String, server: int) -> bool:
	if not _mutable(id):
		return false
	var doc: Dictionary = parties[id]
	var ms: Dictionary = doc["members"]
	if not ms.has(pid) or int(ms[pid]) == server:
		return false
	ms[pid] = server
	_bump(doc)
	return true


## The leader moved to `dest`: authority (home) follows, epoch is bumped. Must be called on the
## current home. Returns the snapshot to replicate (empty if refused).
func leader_handoff(id: String, dest: int) -> Dictionary:
	if not _mutable(id):
		return {}
	var doc: Dictionary = parties[id]
	var ms: Dictionary = doc["members"]
	ms[String(doc["leader"])] = dest
	doc["home"] = dest
	doc["epoch"] = int(doc["epoch"]) + 1
	_bump(doc)
	return doc.duplicate(true)


## Members that should follow the leader to `dest`. `nearby` (optional) restricts to members
## close enough to follow; empty means everyone.
func follow_plan(id: String, dest: int, nearby: Array = []) -> Array:
	var out: Array = []
	if not parties.has(id):
		return out
	var doc: Dictionary = parties[id]
	var ms: Dictionary = doc["members"]
	var ids: Array = ms.keys()
	ids.sort()
	for pid in ids:
		if pid == doc["leader"] or int(ms[pid]) == dest:
			continue
		if nearby.is_empty() or nearby.has(pid):
			out.append({"player": pid, "from": int(ms[pid]), "to": dest})
	return out


static func _newer(a: Dictionary, b: Dictionary) -> bool:
	if int(a["epoch"]) != int(b["epoch"]):
		return int(a["epoch"]) > int(b["epoch"])
	return int(a["version"]) > int(b["version"])


## Installs a snapshot if it is newer by (epoch, version). Returns true if it changed anything.
func apply_replica(doc: Dictionary) -> bool:
	var id := String(doc["id"])
	if parties.has(id) and not _newer(doc, parties[id]):
		return false
	parties[id] = doc.duplicate(true)
	return true


## Every server that hosts a member (plus the home), sorted.
func servers_of(id: String) -> Array:
	var seen := {}
	if parties.has(id):
		var doc: Dictionary = parties[id]
		seen[int(doc["home"])] = true
		for pid in (doc["members"] as Dictionary).keys():
			seen[int((doc["members"] as Dictionary)[pid])] = true
	var out: Array = seen.keys()
	out.sort()
	return out


func same_as(other: Object, id: String) -> bool:
	return JSON.stringify(get_doc(id)) == JSON.stringify(other.get_doc(id))
