extends RefCounted
## Replication graph: spatial-grid relevancy, always-relevant and owner-only nodes, dormancy,
## per-class priority and update frequency, per-connection bandwidth budget with starvation
## protection (priority accumulates while an entity is due but skipped).
##
## Concepts (not code) from Unreal Engine's ReplicationGraph/Iris node model and Valve/Quake
## relevancy+rate throttling; no engine source copied. Original implementation for Cgame.

var cell_size: float = 64.0:
	set(value):
		if not is_finite(value) or value <= 0.0 or cell_size == value:
			return
		cell_size = value
		_cells.clear()
		for id in entities:
			_cell_add(id, entities[id]["position"])
var clock: float = 0.0
var entities: Dictionary = {}  # id -> entity dict
var class_cfg: Dictionary = {}  # class -> {priority, interval, bytes}
var _cells: Dictionary = {}  # Vector2i -> {id: true}
var _special: Dictionary = {} # Always-relevant and owner-only entity IDs.
var _conn: Dictionary = {}  # connection id -> {last_sent, starve, wake_seen}
var _wake_counter: int = 0


func set_class_config(cls: String, priority: float, interval: float, bytes: int) -> void:
	class_cfg[cls] = {"priority": priority, "interval": interval, "bytes": bytes}


func advance(dt: float) -> void:
	clock += dt


func _cell_of(p: Vector3) -> Vector2i:
	return Vector2i(floori(p.x / cell_size), floori(p.z / cell_size))


## entity: {class, position, owner (-1 none), always_relevant, owner_only, dormant}
func add_entity(id: int, cls: String, position: Vector3, owner_id: int = -1, always_relevant: bool = false, owner_only: bool = false) -> void:
	if entities.has(id):
		remove_entity(id)
	entities[id] = {"id": id, "class": cls, "position": position, "owner": owner_id, "always_relevant": always_relevant, "owner_only": owner_only, "dormant": false, "wake": 0}
	_cell_add(id, position)
	if always_relevant or owner_only:
		_special[id] = true


func remove_entity(id: int) -> void:
	if not entities.has(id):
		return
	var e: Dictionary = entities[id]
	_cell_remove(id, e["position"])
	entities.erase(id)
	_special.erase(id)
	# Match the native backend: a reused entity ID represents a new lifetime,
	# not an old send timestamp, starvation score or consumed wake event.
	for state in _conn.values():
		state["last_sent"].erase(id)
		state["starve"].erase(id)
		state["wake_seen"].erase(id)


func set_position(id: int, position: Vector3) -> void:
	if not entities.has(id):
		return
	var e: Dictionary = entities[id]
	var old: Vector3 = e["position"]
	if _cell_of(old) != _cell_of(position):
		_cell_remove(id, old)
		_cell_add(id, position)
	e["position"] = position


func set_dormant(id: int, dormant: bool) -> void:
	if entities.has(id):
		var e: Dictionary = entities[id]
		e["dormant"] = dormant


## Wakes a dormant entity and forces one replication to every connection.
func wake(id: int) -> void:
	if entities.has(id):
		var e: Dictionary = entities[id]
		e["dormant"] = false
		_wake_counter += 1
		e["wake"] = _wake_counter


func _cell_add(id: int, p: Vector3) -> void:
	var key: Vector2i = _cell_of(p)
	if not _cells.has(key):
		_cells[key] = {}
	var b: Dictionary = _cells[key]
	b[id] = true


func _cell_remove(id: int, p: Vector3) -> void:
	var key: Vector2i = _cell_of(p)
	if _cells.has(key):
		var b: Dictionary = _cells[key]
		b.erase(id)
		if b.is_empty():
			_cells.erase(key)


func _state(conn_id: int) -> Dictionary:
	if not _conn.has(conn_id):
		_conn[conn_id] = {"last_sent": {}, "starve": {}, "wake_seen": {}}
	return _conn[conn_id]


func remove_connection(conn_id: int) -> void:
	_conn.erase(conn_id)


func _candidates(connection: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	var cid: int = int(connection["id"])
	var pos: Vector3 = connection["position"]
	var radius: float = float(connection.get("view_radius", 100.0))
	for k in _special:
		var e: Dictionary = entities[k]
		# Owner-only takes precedence even if both flags were set.
		if bool(e["owner_only"]):
			if int(e["owner"]) == cid:
				out[k] = true
		elif bool(e["always_relevant"]):
			out[k] = true
	var lo: Vector2i = _cell_of(pos - Vector3(radius, 0.0, radius))
	var hi: Vector2i = _cell_of(pos + Vector3(radius, 0.0, radius))
	var columns: int = int(hi.x) - int(lo.x) + 1
	var rows: int = int(hi.y) - int(lo.y) + 1
	# Wide sparse views visit occupied cells instead of a huge empty rectangle.
	var buckets: Array[Dictionary] = []
	if columns > _cells.size() or rows > _cells.size() or columns * rows > _cells.size():
		for key in _cells:
			if key.x >= lo.x and key.x <= hi.x and key.y >= lo.y and key.y <= hi.y:
				buckets.append(_cells[key])
	else:
		for cx in range(lo.x, hi.x + 1):
			for cz in range(lo.y, hi.y + 1):
				var key := Vector2i(cx, cz)
				if _cells.has(key):
					buckets.append(_cells[key])
	for b in buckets:
		for id in b:
			var e2: Dictionary = entities[id]
			if bool(e2["owner_only"]) and int(e2["owner"]) != cid:
				continue
			var p: Vector3 = e2["position"]
			if p.distance_to(pos) <= radius:
				out[id] = true
	return out


## Returns prioritized Array of {id, class, priority, bytes} to replicate now and records the
## sends. Due-but-skipped entities accumulate starvation priority.
func gather_for(connection: Dictionary) -> Array:
	var cid: int = int(connection["id"])
	var pos: Vector3 = connection["position"]
	var radius: float = maxf(float(connection.get("view_radius", 100.0)), 0.001)
	var budget: int = int(connection.get("bandwidth_bytes", 1 << 30))
	var st: Dictionary = _state(cid)
	var last_sent: Dictionary = st["last_sent"]
	var starve: Dictionary = st["starve"]
	var wake_seen: Dictionary = st["wake_seen"]
	var due: Array = []
	for id in _candidates(connection):
		var e: Dictionary = entities[id]
		var woken: bool = int(e["wake"]) > int(wake_seen.get(id, 0))
		if bool(e["dormant"]) and not woken:
			continue
		var cfg: Dictionary = class_cfg.get(e["class"], {"priority": 1.0, "interval": 0.0, "bytes": 32})
		if not woken and last_sent.has(id) and clock - float(last_sent[id]) < float(cfg["interval"]):
			continue
		var p: Vector3 = e["position"]
		var near: float = 1.0
		if not bool(e["always_relevant"]):
			near = maxf(1.0 - p.distance_to(pos) / radius, 0.1)
		var score: float = float(cfg["priority"]) * near * (1.0 + float(starve.get(id, 0.0)))
		if woken:
			score += 1000.0
		due.append({"id": id, "class": e["class"], "priority": score, "bytes": int(cfg["bytes"])})
	due.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["priority"] == b["priority"]:
			return int(a["id"]) < int(b["id"])
		return float(a["priority"]) > float(b["priority"]))
	var result: Array = []
	var used: int = 0
	for item in due:
		var d: Dictionary = item
		var id2: int = int(d["id"])
		if used + int(d["bytes"]) <= budget:
			used += int(d["bytes"])
			result.append(d)
			last_sent[id2] = clock
			starve.erase(id2)
			var ent: Dictionary = entities[id2]
			wake_seen[id2] = int(ent["wake"])
		else:
			starve[id2] = float(starve.get(id2, 0.0)) + 1.0
	return result
