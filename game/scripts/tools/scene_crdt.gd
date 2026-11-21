extends RefCounted
## Scene document as an op-based CRDT for multi-user editing (UE Multi-User / Figma style).
##
## Concepts ported (ideas and published algorithms, no code copied):
##  - LWW-Register / LWW-Element-Map: Shapiro, Preguica, Baquero, Zawirski, "A comprehensive
##    study of Convergent and Commutative Replicated Data Types" (INRIA RR-7506, 2011).
##  - OR-Set / add-wins set with tombstones (same paper): a remove only kills the add-tags it
##    observed, so a concurrent add survives.
##  - RGA sequence: Roh, Jelasity, Kulkarni et al., "Replicated abstract data type: Building
##    blocks for collaborative applications" (JPDC 2011). Concepts also used by Automerge
##    (MIT) and Yjs (MIT); Lamport clocks: Lamport, CACM 1978.
##
## Model
##  - Every node has a stable string id. Properties are LWW registers keyed by
##    (lamport, replica id); the larger pair wins, so apply order does not matter.
##  - Node existence is an add-wins set: each add_node op creates a unique tag, remove_node
##    tombstones the tags it observed. A node is alive when some tag is not tombstoned.
##  - Parent/child order is an RGA per parent. Every placement (add or move) is a sequence
##    element "lamport@replica" inserted after a reference element. Siblings that share a
##    reference are ordered newest first. A node's current placement is its highest element
##    (LWW over moves); older elements stay as anchors (tombstones).
##  - Ops: add_node, remove_node, set_prop, move_node. apply() is idempotent and commutative.
##  - Sync: state_vector() + ops_since(vector). Presence is a separate ephemeral channel.
##
## Op shape (Dictionary): kind, r (replica), seq (per-replica counter), l (lamport) plus
##   add_node    id, parent, after, props, type     (new elem id = "l@r")
##   remove_node id, tags
##   set_prop    id, prop, value
##   move_node   id, parent, after                  (new elem id = "l@r")

signal op_generated(op: Dictionary)

var replica: String = ""
var clock: int = 0
var _seq: int = 0

var _log: Dictionary = {}          # "r:seq" -> op
var _log_order: Array = []         # ops in arrival order
var _seen: Dictionary = {}         # replica -> {seq: true}
var _contig: Dictionary = {}       # replica -> highest contiguous seq
var _tags: Dictionary = {}         # node id -> {tag: true}
var _tomb: Dictionary = {}         # tag -> true
var _props: Dictionary = {}        # node id -> {prop: [value, l, r]}
var _elems: Dictionary = {}        # elem id -> {node, parent, after, l, r}
var _by_parent: Dictionary = {}    # parent id -> {elem id: true}
var _best: Dictionary = {}         # node id -> winning elem id
var _presence: Dictionary = {}     # user -> {l, cursor, selection, t}
var _presence_l: int = 0


func _init(replica_id: String = "") -> void:
	replica = replica_id


# ---------------------------------------------------------------- helpers

static func _newer(l1: int, r1: String, l2: int, r2: String) -> bool:
	## True when (l1, r1) is strictly greater than (l2, r2).
	if l1 != l2:
		return l1 > l2
	return r1 > r2


static func _elem_id(l: int, r: String) -> String:
	return "%d@%s" % [l, r]


# ---------------------------------------------------------------- apply

## Applies a remote or local op. Returns true when it changed state, false for a duplicate.
func apply(op: Dictionary) -> bool:
	var r: String = op.get("r", "")
	var seq: int = op.get("seq", 0)
	var l: int = op.get("l", 0)
	var oid := "%s:%d" % [r, seq]
	if _log.has(oid):
		return false
	_log[oid] = op
	_log_order.append(op)
	if not _seen.has(r):
		_seen[r] = {}
		_contig[r] = 0
	var seen: Dictionary = _seen[r]
	seen[seq] = true
	var c: int = _contig[r]
	while seen.has(c + 1):
		c += 1
	_contig[r] = c
	clock = maxi(clock, l)
	var kind: String = op.get("kind", "")
	var nid: String = op.get("id", "")
	match kind:
		"add_node":
			var tag := _elem_id(l, r)
			if not _tags.has(nid):
				_tags[nid] = {}
			var tg: Dictionary = _tags[nid]
			tg[tag] = true
			_place(tag, nid, op.get("parent", ""), op.get("after", ""), l, r)
			var props: Dictionary = op.get("props", {})
			for p in props:
				_set_reg(nid, str(p), props[p], l, r)
			_set_reg(nid, "_type", op.get("type", "Node"), l, r)
		"remove_node":
			var rtags: Array = op.get("tags", [])
			for tag in rtags:
				_tomb[str(tag)] = true
		"set_prop":
			_set_reg(nid, op.get("prop", ""), op.get("value"), l, r)
		"move_node":
			_place(_elem_id(l, r), nid, op.get("parent", ""), op.get("after", ""), l, r)
	return true


func _set_reg(nid: String, prop: String, value: Variant, l: int, r: String) -> void:
	if not _props.has(nid):
		_props[nid] = {}
	var regs: Dictionary = _props[nid]
	if regs.has(prop):
		var cur: Array = regs[prop]
		if not _newer(l, r, int(cur[1]), str(cur[2])):
			return
	regs[prop] = [value, l, r]


func _place(eid: String, nid: String, parent: String, after: String, l: int, r: String) -> void:
	if _elems.has(eid):
		return
	_elems[eid] = {"node": nid, "parent": parent, "after": after, "l": l, "r": r}
	if not _by_parent.has(parent):
		_by_parent[parent] = {}
	var bp: Dictionary = _by_parent[parent]
	bp[eid] = true
	if _best.has(nid):
		var cur: Dictionary = _elems[_best[nid]]
		if not _newer(l, r, int(cur["l"]), str(cur["r"])):
			return
	_best[nid] = eid


# ---------------------------------------------------------------- local ops

func _next_op(kind: String) -> Dictionary:
	clock += 1
	_seq += 1
	return {"kind": kind, "r": replica, "seq": _seq, "l": clock}


## Builds, applies and returns a local op. kind is one of add_node, remove_node, set_prop,
## move_node. args: id; add_node: parent, index, type, props; set_prop: prop, value;
## move_node: parent, index. index < 0 or past the end appends.
func local_op(kind: String, args: Dictionary) -> Dictionary:
	var op := _next_op(kind)
	var nid: String = args.get("id", "")
	op["id"] = nid
	match kind:
		"add_node":
			var parent: String = args.get("parent", "")
			op["parent"] = parent
			op["after"] = _after_for(parent, int(args.get("index", -1)), "")
			op["type"] = args.get("type", "Node")
			op["props"] = args.get("props", {}).duplicate(true)
		"remove_node":
			var live: Array = []
			var tg: Dictionary = _tags.get(nid, {})
			for tag in tg:
				if not _tomb.has(tag):
					live.append(tag)
			op["tags"] = live
		"set_prop":
			op["prop"] = args.get("prop", "")
			op["value"] = args.get("value")
		"move_node":
			var np: String = args.get("parent", "")
			op["parent"] = np
			op["after"] = _after_for(np, int(args.get("index", -1)), nid)
	apply(op)
	op_generated.emit(op)
	return op


func _after_for(parent: String, index: int, skip_id: String) -> String:
	var kids: Array = []
	for k in children_of(parent):
		if k != skip_id:
			kids.append(k)
	if kids.is_empty() or index == 0:
		return ""
	var i: int = kids.size() if index < 0 or index > kids.size() else index
	return str(_best.get(kids[i - 1], ""))


# ---------------------------------------------------------------- queries

func has_node(nid: String) -> bool:
	var tg: Dictionary = _tags.get(nid, {})
	for tag in tg:
		if not _tomb.has(tag):
			return true
	return false


func get_prop(nid: String, prop: String, default: Variant = null) -> Variant:
	var regs: Dictionary = _props.get(nid, {})
	if not regs.has(prop):
		return default
	var reg: Array = regs[prop]
	return reg[0]


func parent_of(nid: String) -> String:
	if not _best.has(nid):
		return ""
	var e: Dictionary = _elems[_best[nid]]
	return str(e["parent"])


## Alive node ids in RGA order under `parent` ("" = top level).
func children_of(parent: String) -> Array:
	var out: Array = []
	var bp: Dictionary = _by_parent.get(parent, {})
	if bp.is_empty():
		return out
	var groups: Dictionary = {}
	for eid in bp:
		var e: Dictionary = _elems[eid]
		var ref: String = str(e["after"])
		if ref != "" and not bp.has(ref):
			ref = ""
		if not groups.has(ref):
			groups[ref] = []
		var g: Array = groups[ref]
		g.append(eid)
	for ref in groups:
		var g: Array = groups[ref]
		g.sort_custom(_elem_desc)
	var stack: Array = []
	var top: Array = groups.get("", [])
	for i in range(top.size() - 1, -1, -1):
		stack.append(top[i])
	var emitted: Dictionary = {}
	while not stack.is_empty():
		var eid: String = stack.pop_back()
		var e: Dictionary = _elems[eid]
		var nid: String = e["node"]
		if _best.get(nid, "") == eid and has_node(nid) and not emitted.has(nid):
			emitted[nid] = true
			out.append(nid)
		var sub: Array = groups.get(eid, [])
		for i in range(sub.size() - 1, -1, -1):
			stack.append(sub[i])
	return out


func _elem_desc(a: String, b: String) -> bool:
	var ea: Dictionary = _elems[a]
	var eb: Dictionary = _elems[b]
	return _newer(int(ea["l"]), str(ea["r"]), int(eb["l"]), str(eb["r"]))


## Alive node ids reachable from the top level (cycles from concurrent moves are dropped).
func all_node_ids() -> Array:
	var out: Array = []
	var visited: Dictionary = {}
	var stack: Array = children_of("")
	stack.reverse()
	while not stack.is_empty():
		var nid: String = stack.pop_back()
		if visited.has(nid):
			continue
		visited[nid] = true
		out.append(nid)
		var kids: Array = children_of(nid)
		kids.reverse()
		stack.append_array(kids)
	return out


# ---------------------------------------------------------------- sync

## Highest contiguous seq per replica.
func state_vector() -> Dictionary:
	return _contig.duplicate()


## Ops a peer with `vector` may be missing (duplicates are harmless).
func ops_since(vector: Dictionary) -> Array:
	var out: Array = []
	for op in _log_order:
		var o: Dictionary = op
		if int(o.get("seq", 0)) > int(vector.get(o.get("r", ""), 0)):
			out.append(o)
	return out


## Applies many ops, returns how many were new.
func merge_ops(ops: Array) -> int:
	var n := 0
	for op in ops:
		if apply(op):
			n += 1
	return n


# ---------------------------------------------------------------- scene dict

## Nested dictionary of the first top-level node: {id, type, name, props, children}.
## Returns {} for an empty document.
func to_scene_dict() -> Dictionary:
	var roots: Array = children_of("")
	if roots.is_empty():
		return {}
	return _node_dict(str(roots[0]), {})


func _node_dict(nid: String, visiting: Dictionary) -> Dictionary:
	visiting[nid] = true
	var props: Dictionary = {}
	var regs: Dictionary = _props.get(nid, {})
	for p in regs:
		if p == "_type" or p == "name":
			continue
		var reg: Array = regs[p]
		props[p] = reg[0]
	var kids: Array = []
	for k in children_of(nid):
		if not visiting.has(k):
			kids.append(_node_dict(str(k), visiting))
	return {
		"id": nid,
		"type": get_prop(nid, "_type", "Node"),
		"name": get_prop(nid, "name", nid),
		"props": props,
		"children": kids,
	}


## Fills this (empty) document from a nested scene dictionary as produced by
## to_scene_dict(): {id?, type, name, props, children}. Missing ids become "path/Name".
func load_scene_dict(d: Dictionary) -> void:
	_load_node(d, "", "")


func _load_node(d: Dictionary, parent: String, path: String) -> void:
	var nm: String = d.get("name", "Node")
	var nid: String = d.get("id", path + "/" + nm if path != "" else nm)
	var props: Dictionary = d.get("props", {}).duplicate(true)
	props["name"] = nm
	local_op("add_node", {"id": nid, "parent": parent, "type": d.get("type", "Node"), "props": props})
	var kids: Array = d.get("children", [])
	for k in kids:
		_load_node(k, nid, nid)


## Creates a document owned by `replica_id` from a simple node/prop dictionary.
static func from_packed_scene_dict(d: Dictionary, replica_id: String = "local") -> RefCounted:
	var doc: RefCounted = (load("res://scripts/tools/scene_crdt.gd") as GDScript).new(replica_id)
	doc.load_scene_dict(d)
	return doc


# ---------------------------------------------------------------- presence

## Ephemeral user state (cursor / selection). Not part of the op log. Returns the message to
## broadcast. t is a caller supplied timestamp in msec used by expire_presence().
func local_presence(cursor: Variant, selection: Array, t: int = 0) -> Dictionary:
	_presence_l += 1
	var msg := {"kind": "presence", "user": replica, "l": _presence_l, "cursor": cursor, "selection": selection.duplicate(), "t": t}
	apply_presence(msg)
	return msg


## Applies a presence message; stale (older l) messages from the same user are ignored.
func apply_presence(msg: Dictionary) -> bool:
	var user: String = msg.get("user", "")
	var l: int = msg.get("l", 0)
	if _presence.has(user):
		var cur: Dictionary = _presence[user]
		if int(cur["l"]) >= l:
			return false
	_presence[user] = {"l": l, "cursor": msg.get("cursor"), "selection": msg.get("selection", []), "t": msg.get("t", 0)}
	return true


func presence() -> Dictionary:
	return _presence.duplicate(true)


func remove_presence(user: String) -> void:
	_presence.erase(user)


## Drops users not heard from since now_msec - ttl_msec. Returns the removed user names.
func expire_presence(now_msec: int, ttl_msec: int) -> Array:
	var gone: Array = []
	for u in _presence.keys():
		var p: Dictionary = _presence[u]
		if now_msec - int(p["t"]) > ttl_msec:
			gone.append(u)
			_presence.erase(u)
	return gone
