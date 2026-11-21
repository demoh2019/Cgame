extends RefCounted
## Portal-based sound propagation between rooms (Wwise Rooms & Portals concept):
## Dijkstra over portals, geometric path length, virtual source position,
## closed-portal attenuation and a UTD-inspired diffraction low-pass cutoff.
## Concepts from Wwise/Steam Audio docs and the Uniform Theory of Diffraction
## (Kouyoumjian & Pathak); implemented from scratch.

const CLOSED_PORTAL_DB := 40.0
const MAX_CUTOFF_HZ := 20000.0
const MIN_CUTOFF_HZ := 200.0

var _rooms: Dictionary = {}
var _portals: Array[Dictionary] = []


func add_room(id: Variant, center: Vector3) -> void:
	_rooms[id] = center


## Returns the portal id (usable in propagate()'s "path").
func add_portal(room_a: Variant, room_b: Variant, position: Vector3, openness: float = 1.0) -> int:
	_portals.append({"a": room_a, "b": room_b, "pos": position, "open": clampf(openness, 0.0, 1.0)})
	return _portals.size() - 1


func set_openness(portal_id: int, openness: float) -> void:
	if portal_id >= 0 and portal_id < _portals.size():
		_portals[portal_id]["open"] = clampf(openness, 0.0, 1.0)


func propagate(source_room: Variant, source_pos: Vector3, listener_room: Variant, listener_pos: Vector3) -> Dictionary:
	if source_room == listener_room:
		return _result([], [source_pos, listener_pos], source_pos, listener_pos)
	var count: int = _portals.size()
	var dist: PackedFloat64Array = PackedFloat64Array()
	dist.resize(count)
	dist.fill(INF)
	var prev: PackedInt32Array = PackedInt32Array()
	prev.resize(count)
	prev.fill(-1)
	var done: PackedByteArray = PackedByteArray()
	done.resize(count)
	for i in count:
		if _touches(i, source_room):
			dist[i] = source_pos.distance_to(_ppos(i))
	var best: int = -1
	var best_total: float = INF
	while true:
		var u: int = -1
		var ud: float = INF
		for i in count:
			if done[i] == 0 and dist[i] < ud:
				ud = dist[i]
				u = i
		if u < 0:
			break
		done[u] = 1
		if _touches(u, listener_room):
			var total: float = ud + _ppos(u).distance_to(listener_pos)
			if total < best_total:
				best_total = total
				best = u
		for v in count:
			if done[v] == 0 and _shares_room(u, v):
				var nd: float = ud + _ppos(u).distance_to(_ppos(v))
				if nd < dist[v]:
					dist[v] = nd
					prev[v] = u
	if best < 0:
		return {"blocked": true}
	var path: Array = []
	var cur: int = best
	while cur >= 0:
		path.push_front(cur)
		cur = prev[cur]
	var points: Array = [source_pos]
	for pid in path:
		points.append(_ppos(int(pid)))
	points.append(listener_pos)
	return _result(path, points, source_pos, listener_pos)


func _result(path: Array, points: Array, source_pos: Vector3, listener_pos: Vector3) -> Dictionary:
	var total: float = 0.0
	var bend: float = 0.0
	var atten: float = 0.0
	for i in range(1, points.size()):
		var p0: Vector3 = points[i - 1]
		var p1: Vector3 = points[i]
		total += p0.distance_to(p1)
	for i in range(1, points.size() - 1):
		var d_in: Vector3 = (points[i] as Vector3) - (points[i - 1] as Vector3)
		var d_out: Vector3 = (points[i + 1] as Vector3) - (points[i] as Vector3)
		if d_in.length_squared() > 0.000001 and d_out.length_squared() > 0.000001:
			bend += d_in.angle_to(d_out)
	for pid in path:
		var open: float = _portals[int(pid)]["open"]
		atten += (1.0 - open) * CLOSED_PORTAL_DB
	var virtual_pos: Vector3 = source_pos
	if not path.is_empty():
		var last_pos: Vector3 = _ppos(int(path[path.size() - 1]))
		var dir: Vector3 = last_pos - listener_pos
		if dir.length_squared() < 0.000001:
			dir = source_pos - listener_pos
		if dir.length_squared() < 0.000001:
			dir = Vector3.FORWARD
		virtual_pos = listener_pos + dir.normalized() * total
	return {
		"path": path,
		"distance": total,
		"virtual_position": virtual_pos,
		"attenuation_db": atten,
		"bend_angle": bend,
		"diffraction_cutoff_hz": cutoff_for_bend(bend),
	}


## UTD-inspired: shadow-region loss grows with bend angle, so the cutoff falls
## roughly with 1 / (1 + k * theta^2).
static func cutoff_for_bend(bend_radians: float) -> float:
	return clampf(MAX_CUTOFF_HZ / (1.0 + 6.0 * bend_radians * bend_radians), MIN_CUTOFF_HZ, MAX_CUTOFF_HZ)


func _ppos(i: int) -> Vector3:
	var p: Vector3 = _portals[i]["pos"]
	return p


func _touches(i: int, room: Variant) -> bool:
	return _portals[i]["a"] == room or _portals[i]["b"] == room


func _shares_room(i: int, j: int) -> bool:
	var a: Variant = _portals[i]["a"]
	var b: Variant = _portals[i]["b"]
	return _touches(j, a) or _touches(j, b)
