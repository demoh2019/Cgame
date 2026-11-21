extends RefCounted
## Sequencer-style cinematic timeline data model: multi-shot camera cuts,
## transform / float / event / animation tracks, sampling and serialization.
##
## References (concepts only, implementation written from scratch):
## - Catmull-Rom splines: Edwin Catmull & Raphael Rom (public domain math);
##   positions use Godot's Vector3.cubic_interpolate.
## - Squad (spherical cubic quaternion interpolation): Shoemake 1985,
##   formulation as in the public-domain math notes by Ken Shoemake / Eberly.
## - Track/key/shot model inspired by Unreal Sequencer and Unity Timeline
##   (design ideas only, no code copied).

var length: float = 10.0
var shots: Array = []  # [{"start": float, "end": float, "camera": String}]
var transform_tracks: Dictionary = {}  # name -> Array of {time, position, rotation, interp}
var float_tracks: Dictionary = {}  # name -> Array of {time, value, ease}
var event_tracks: Dictionary = {}  # name -> Array of {time, name, args}
var animation_tracks: Dictionary = {}  # name -> Array of {time, target, animation}


func add_shot(start: float, end: float, camera: String) -> void:
	shots.append({"start": start, "end": end, "camera": camera})
	shots.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["start"]) < float(b["start"]))


func add_transform_key(track: String, key: Dictionary) -> void:
	var k: Dictionary = {
		"time": float(key.get("time", 0.0)),
		"position": key.get("position", Vector3.ZERO),
		"rotation": (key.get("rotation", Quaternion.IDENTITY) as Quaternion).normalized(),
		"interp": String(key.get("interp", "linear")),
	}
	_insert_sorted(transform_tracks, track, k)


func add_float_key(track: String, key: Dictionary) -> void:
	var k: Dictionary = {
		"time": float(key.get("time", 0.0)),
		"value": float(key.get("value", 0.0)),
		"ease": String(key.get("ease", "linear")),
	}
	_insert_sorted(float_tracks, track, k)


func add_event(track: String, time: float, event_name: String, args: Array = []) -> void:
	_insert_sorted(event_tracks, track, {"time": time, "name": event_name, "args": args})


func add_animation_key(track: String, time: float, target: String, animation: String) -> void:
	_insert_sorted(animation_tracks, track, {"time": time, "target": target, "animation": animation})


func _insert_sorted(store: Dictionary, track: String, key: Dictionary) -> void:
	if not store.has(track):
		store[track] = []
	var arr: Array = store[track]
	var kt: float = key["time"]
	var i: int = arr.size()
	while i > 0 and float((arr[i - 1] as Dictionary)["time"]) > kt:
		i -= 1
	arr.insert(i, key)


## Index of the last key with time <= t, or -1.
static func _find_segment(arr: Array, t: float) -> int:
	var lo: int = 0
	var hi: int = arr.size() - 1
	var res: int = -1
	while lo <= hi:
		var mid: int = (lo + hi) >> 1
		if float((arr[mid] as Dictionary)["time"]) <= t:
			res = mid
			lo = mid + 1
		else:
			hi = mid - 1
	return res


func sample_transform(track: String, t: float) -> Transform3D:
	if not transform_tracks.has(track):
		return Transform3D.IDENTITY
	var keys: Array = transform_tracks[track]
	if keys.is_empty():
		return Transform3D.IDENTITY
	var i: int = _find_segment(keys, t)
	if i < 0:
		var f: Dictionary = keys[0]
		return Transform3D(Basis(f["rotation"] as Quaternion), f["position"] as Vector3)
	var a: Dictionary = keys[i]
	var pa: Vector3 = a["position"]
	var qa: Quaternion = a["rotation"]
	if i >= keys.size() - 1:
		return Transform3D(Basis(qa), pa)
	var b: Dictionary = keys[i + 1]
	var pb: Vector3 = b["position"]
	var qb: Quaternion = b["rotation"]
	var mode: String = a["interp"]
	if mode == "constant":
		return Transform3D(Basis(qa), pa)
	var span: float = float(b["time"]) - float(a["time"])
	var w: float = 0.0 if span <= 0.0 else clampf((t - float(a["time"])) / span, 0.0, 1.0)
	if mode == "cubic":
		var prev: Dictionary = keys[maxi(i - 1, 0)]
		var nxt: Dictionary = keys[mini(i + 2, keys.size() - 1)]
		var pos: Vector3 = pa.cubic_interpolate(pb, prev["position"] as Vector3, nxt["position"] as Vector3, w)
		var s1: Quaternion = _squad_control(prev["rotation"] as Quaternion, qa, qb)
		var s2: Quaternion = _squad_control(qa, qb, nxt["rotation"] as Quaternion)
		return Transform3D(Basis(_squad(qa, qb, s1, s2, w)), pos)
	return Transform3D(Basis(qa.slerp(qb, w)), pa.lerp(pb, w))


static func _quat_log(q: Quaternion) -> Vector3:
	var v := Vector3(q.x, q.y, q.z)
	var l: float = v.length()
	if l < 0.000001:
		return Vector3.ZERO
	return v / l * atan2(l, q.w)


static func _quat_exp(v: Vector3) -> Quaternion:
	var l: float = v.length()
	if l < 0.000001:
		return Quaternion.IDENTITY
	var n: Vector3 = v / l * sin(l)
	return Quaternion(n.x, n.y, n.z, cos(l))


## Squad inner control point for q1 given neighbours q0 and q2.
static func _squad_control(q0: Quaternion, q1: Quaternion, q2: Quaternion) -> Quaternion:
	if q1.dot(q0) < 0.0:
		q0 = -q0
	if q1.dot(q2) < 0.0:
		q2 = -q2
	var inv: Quaternion = q1.inverse()
	var sum: Vector3 = _quat_log(inv * q2) + _quat_log(inv * q0)
	return (q1 * _quat_exp(sum * -0.25)).normalized()


static func _squad(q1: Quaternion, q2: Quaternion, s1: Quaternion, s2: Quaternion, w: float) -> Quaternion:
	if q1.dot(q2) < 0.0:
		q2 = -q2
		s2 = -s2
	var a: Quaternion = q1.slerp(q2, w)
	var b: Quaternion = s1.slerp(s2, w)
	return a.slerp(b, 2.0 * w * (1.0 - w)).normalized()


static func apply_ease(w: float, ease_name: String) -> float:
	match ease_name:
		"constant":
			return 0.0
		"in":
			return w * w
		"out":
			return 1.0 - (1.0 - w) * (1.0 - w)
		"in_out":
			return w * w * (3.0 - 2.0 * w)
		_:
			return w


func sample_float(track: String, t: float) -> float:
	if not float_tracks.has(track):
		return 0.0
	var keys: Array = float_tracks[track]
	if keys.is_empty():
		return 0.0
	var i: int = _find_segment(keys, t)
	if i < 0:
		return float((keys[0] as Dictionary)["value"])
	var a: Dictionary = keys[i]
	if i >= keys.size() - 1:
		return float(a["value"])
	var b: Dictionary = keys[i + 1]
	var span: float = float(b["time"]) - float(a["time"])
	var w: float = 0.0 if span <= 0.0 else clampf((t - float(a["time"])) / span, 0.0, 1.0)
	return lerpf(float(a["value"]), float(b["value"]), apply_ease(w, String(a["ease"])))


## Events with t0 <= time < t1, sorted by time. When t1 < t0 the range wraps
## through the end of the sequence: [t0, length) then [0, t1).
func events_between(t0: float, t1: float) -> Array:
	return _keys_between(event_tracks, t0, t1)


func animations_between(t0: float, t1: float) -> Array:
	return _keys_between(animation_tracks, t0, t1)


func _keys_between(store: Dictionary, t0: float, t1: float) -> Array:
	var out: Array = []
	if t1 >= t0:
		_collect(store, t0, t1, 0.0, out)
	else:
		_collect(store, t0, INF, 0.0, out)
		_collect(store, 0.0, t1, length, out)
	return out


func _collect(store: Dictionary, t0: float, t1: float, offset: float, out: Array) -> void:
	var found: Array = []
	for track in store.keys():
		for k in (store[track] as Array):
			var kd: Dictionary = k
			var kt: float = kd["time"]
			if kt >= t0 and kt < t1:
				var copy: Dictionary = kd.duplicate()
				copy["track"] = track
				copy["order"] = kt + offset
				found.append(copy)
	found.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["order"]) < float(b["order"]))
	out.append_array(found)


func _shot_index(t: float) -> int:
	for i in shots.size():
		var s: Dictionary = shots[i]
		if t >= float(s["start"]) and t < float(s["end"]):
			return i
	if not shots.is_empty() and t >= float((shots[shots.size() - 1] as Dictionary)["end"]):
		return shots.size() - 1
	return -1


func active_shot(t: float) -> Dictionary:
	var i: int = _shot_index(t)
	if i < 0:
		return {}
	return shots[i]


## {"from": String, "to": String, "weight": float}; weight 0 shows `from`,
## 1 shows `to`. Only the first blend_seconds of a shot blend from the
## previous shot's camera.
func camera_cut_blend(t: float, blend_seconds: float) -> Dictionary:
	var i: int = _shot_index(t)
	if i < 0:
		return {"from": "", "to": "", "weight": 1.0}
	var cur: Dictionary = shots[i]
	var cam: String = cur["camera"]
	if i > 0 and blend_seconds > 0.0:
		var since: float = t - float(cur["start"])
		if since < blend_seconds:
			var prev: Dictionary = shots[i - 1]
			return {"from": String(prev["camera"]), "to": cam, "weight": clampf(since / blend_seconds, 0.0, 1.0)}
	return {"from": cam, "to": cam, "weight": 1.0}


func to_dict() -> Dictionary:
	var tt: Dictionary = {}
	for track in transform_tracks.keys():
		var arr: Array = []
		for k in (transform_tracks[track] as Array):
			var kd: Dictionary = k
			var p: Vector3 = kd["position"]
			var q: Quaternion = kd["rotation"]
			arr.append({"time": kd["time"], "position": [p.x, p.y, p.z], "rotation": [q.x, q.y, q.z, q.w], "interp": kd["interp"]})
		tt[track] = arr
	return {
		"length": length,
		"shots": shots.duplicate(true),
		"transform_tracks": tt,
		"float_tracks": float_tracks.duplicate(true),
		"event_tracks": event_tracks.duplicate(true),
		"animation_tracks": animation_tracks.duplicate(true),
	}


static func from_dict(d: Dictionary) -> RefCounted:
	var s := new()
	s.length = float(d.get("length", 10.0))
	for sh in (d.get("shots", []) as Array):
		var shd: Dictionary = sh
		s.add_shot(float(shd["start"]), float(shd["end"]), String(shd["camera"]))
	var tt: Dictionary = d.get("transform_tracks", {})
	for track in tt.keys():
		for k in (tt[track] as Array):
			var kd: Dictionary = k
			var pa: Array = kd["position"]
			var qa: Array = kd["rotation"]
			s.add_transform_key(String(track), {
				"time": kd["time"],
				"position": Vector3(float(pa[0]), float(pa[1]), float(pa[2])),
				"rotation": Quaternion(float(qa[0]), float(qa[1]), float(qa[2]), float(qa[3])),
				"interp": kd.get("interp", "linear"),
			})
	var ft: Dictionary = d.get("float_tracks", {})
	for track in ft.keys():
		for k in (ft[track] as Array):
			s.add_float_key(String(track), k as Dictionary)
	var et: Dictionary = d.get("event_tracks", {})
	for track in et.keys():
		for k in (et[track] as Array):
			var kd: Dictionary = k
			s.add_event(String(track), float(kd["time"]), String(kd["name"]), kd.get("args", []) as Array)
	var at: Dictionary = d.get("animation_tracks", {})
	for track in at.keys():
		for k in (at[track] as Array):
			var kd: Dictionary = k
			s.add_animation_key(String(track), float(kd["time"]), String(kd["target"]), String(kd["animation"]))
	return s
