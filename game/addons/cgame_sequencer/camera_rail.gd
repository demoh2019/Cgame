extends RefCounted
## Procedural camera rail: Catmull-Rom path with arc-length parameterisation,
## baking to cinematic transform keys, and focus-distance key generation.
##
## Sources / credits:
## - Catmull-Rom spline: Edwin Catmull & Raphael Rom (1974), public-domain
##   mathematics, evaluated with Godot's Vector3.cubic_interpolate (MIT, Godot
##   Engine contributors).
## - Arc-length lookup table + binary search: standard technique (e.g. Game
##   Programming Gems "Curve arc length parameterization"); written from scratch.
## License of this file: MIT.

const CinematicSequence = preload("res://scripts/client/cinematic_sequence.gd")

const SAMPLES_PER_SEGMENT: int = 32

var points: Array[Vector3] = []
var closed: bool = false

var _table_pos: PackedVector3Array = PackedVector3Array()
var _table_dist: PackedFloat32Array = PackedFloat32Array()
var _dirty: bool = true


func add_point(p: Vector3) -> void:
	points.append(p)
	_dirty = true


func set_points(pts: Array[Vector3]) -> void:
	points = pts.duplicate()
	_dirty = true


func clear() -> void:
	points.clear()
	_dirty = true


## Catmull-Rom position for segment i (between points i and i+1), w in 0..1.
func _eval_segment(i: int, w: float) -> Vector3:
	var n: int = points.size()
	var i0: int
	var i1: int = i
	var i2: int
	var i3: int
	if closed:
		i0 = (i - 1 + n) % n
		i2 = (i + 1) % n
		i3 = (i + 2) % n
	else:
		i0 = maxi(i - 1, 0)
		i2 = mini(i + 1, n - 1)
		i3 = mini(i + 2, n - 1)
	var p1: Vector3 = points[i1]
	return p1.cubic_interpolate(points[i2], points[i0], points[i3], w)


func segment_count() -> int:
	var n: int = points.size()
	if n < 2:
		return 0
	return n if closed else n - 1


func _rebuild() -> void:
	_dirty = false
	_table_pos = PackedVector3Array()
	_table_dist = PackedFloat32Array()
	if points.is_empty():
		return
	if points.size() == 1:
		_table_pos.append(points[0])
		_table_dist.append(0.0)
		return
	var acc: float = 0.0
	_table_pos.append(points[0])
	_table_dist.append(0.0)
	for s in segment_count():
		for k in range(1, SAMPLES_PER_SEGMENT + 1):
			var p: Vector3 = _eval_segment(s, float(k) / float(SAMPLES_PER_SEGMENT))
			acc += p.distance_to(_table_pos[_table_pos.size() - 1])
			_table_pos.append(p)
			_table_dist.append(acc)


func length() -> float:
	if _dirty:
		_rebuild()
	if _table_dist.is_empty():
		return 0.0
	return _table_dist[_table_dist.size() - 1]


## Position at arc-length distance d (clamped to [0, length]); uniform speed
## when d advances linearly.
func position_at_distance(d: float) -> Vector3:
	if _dirty:
		_rebuild()
	if _table_pos.is_empty():
		return Vector3.ZERO
	var total: float = _table_dist[_table_dist.size() - 1]
	var dd: float = clampf(d, 0.0, total)
	var lo: int = 0
	var hi: int = _table_dist.size() - 1
	while hi - lo > 1:
		var mid: int = (lo + hi) >> 1
		if _table_dist[mid] <= dd:
			lo = mid
		else:
			hi = mid
	if hi == lo:
		return _table_pos[lo]
	var span: float = _table_dist[hi] - _table_dist[lo]
	var w: float = 0.0 if span <= 0.000001 else (dd - _table_dist[lo]) / span
	return _table_pos[lo].lerp(_table_pos[hi], w)


func tangent_at_distance(d: float) -> Vector3:
	var total: float = length()
	var eps: float = maxf(total * 0.002, 0.001)
	var a: float = clampf(d - eps, 0.0, total)
	var b: float = clampf(d + eps, 0.0, total)
	var dir: Vector3 = position_at_distance(b) - position_at_distance(a)
	if dir.length_squared() < 0.0000001:
		return Vector3.FORWARD
	return dir.normalized()


func _look_quat(from: Vector3, dir: Vector3) -> Quaternion:
	if dir.length_squared() < 0.0000001:
		return Quaternion.IDENTITY
	var up: Vector3 = Vector3.UP
	if absf(dir.normalized().dot(up)) > 0.999:
		up = Vector3.FORWARD
	var basis: Basis = Basis.looking_at(dir.normalized(), up)
	return basis.get_rotation_quaternion()


func _resolve_target(target: Variant, t: float) -> Variant:
	if target is Vector3:
		return target
	if target is Callable:
		var c: Callable = target
		return c.call(t)
	return null


## Writes transform keys (one per frame) to `track` for t in [start, end].
## speed_curve (optional Curve, x = normalised time, y = normalised distance)
## remaps progress; null means constant speed. look_target: null looks along
## the path tangent; Vector3 (or Callable(t) -> Vector3) looks at that point.
## Returns the number of keys written.
func bake_to_track(sequence: CinematicSequence, track: String, start: float, end: float, fps: float,
		speed_curve: Curve = null, look_target: Variant = null) -> int:
	if sequence == null or points.size() < 2 or end <= start or fps <= 0.0:
		return 0
	var total: float = length()
	var span: float = end - start
	var frames: int = maxi(1, int(ceil(span * fps - 0.0001)))
	var written: int = 0
	for f in frames + 1:
		var t: float = minf(start + float(f) / fps, end)
		var u: float = clampf((t - start) / span, 0.0, 1.0)
		if speed_curve != null:
			u = clampf(speed_curve.sample(u), 0.0, 1.0)
		var d: float = u * total
		var pos: Vector3 = position_at_distance(d)
		var tgt: Variant = _resolve_target(look_target, t)
		var dir: Vector3
		if tgt is Vector3:
			dir = (tgt as Vector3) - pos
		else:
			dir = tangent_at_distance(d)
		sequence.add_transform_key(track, {
			"time": t,
			"position": pos,
			"rotation": _look_quat(pos, dir),
			"interp": "linear",
		})
		written += 1
	return written


## Writes float keys (default track name "focus_distance") with the distance
## from the camera (sampled from `camera_track`) to `target` (Vector3 or
## Callable(t) -> Vector3) for t in [start, end]. Returns keys written.
static func focus_track_from_target(sequence: CinematicSequence, camera_track: String, focus_track: String,
		start: float, end: float, fps: float, target: Variant) -> int:
	if sequence == null or end <= start or fps <= 0.0:
		return 0
	var frames: int = maxi(1, int(ceil((end - start) * fps - 0.0001)))
	var written: int = 0
	for f in frames + 1:
		var t: float = minf(start + float(f) / fps, end)
		var tgt: Vector3 = Vector3.ZERO
		if target is Vector3:
			tgt = target
		elif target is Callable:
			var c: Callable = target
			tgt = c.call(t)
		var cam: Transform3D = sequence.sample_transform(camera_track, t)
		sequence.add_float_key(focus_track, {
			"time": t,
			"value": cam.origin.distance_to(tgt),
			"ease": "linear",
		})
		written += 1
	return written
