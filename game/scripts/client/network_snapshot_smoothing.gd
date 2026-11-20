extends RefCounted
## Jitter-buffered visual smoothing for replicated players and enemies.
## Endpoints are server-authoritative; no prediction, movement or physics edits.
## Unreal simulated-proxy smoothing + Gaffer Hermite snapshots, bounded to
## prevent curve overshoot at walls, teleport gates and rapid turnarounds.

const TELEPORT_DISTANCE := 8.0
const MAX_SAMPLE_SECONDS := 0.5


## Hermite axis whose endpoint derivatives cannot reverse the server chord.
## Keeping every component inside the endpoint box is critical for collision
## silhouettes, network spikes, stair steps and pathfinding around walls.
static func _axis(a: float, b: float, va: float, vb: float, span: float, t: float) -> float:
	var chord: float = b - a
	if absf(chord) <= 0.00001:
		return a
	var m0: float = chord * clampf(va * span / chord, 0.0, 3.0)
	var m1: float = chord * clampf(vb * span / chord, 0.0, 3.0)
	var t2: float = t * t
	var t3: float = t2 * t
	var result: float = (2.0 * t3 - 3.0 * t2 + 1.0) * a \
		+ (t3 - 2.0 * t2 + t) * m0 \
		+ (-2.0 * t3 + 3.0 * t2) * b + (t3 - t2) * m1
	return clampf(result, minf(a, b), maxf(a, b))


static func hermite(from: Vector3, to: Vector3, v_from: Vector3,
		v_to: Vector3, span: float, alpha: float, host: Node3D = null) -> Vector3:
	var t: float = clampf(alpha if is_finite(alpha) else 0.0, 0.0, 1.0)
	if t <= 0.0:
		return from
	if t >= 1.0:
		return to
	if not is_finite(span) or span <= 0.00001 or span > MAX_SAMPLE_SECONDS \
			or from.distance_squared_to(to) > TELEPORT_DISTANCE * TELEPORT_DISTANCE \
			or not v_from.is_finite() or not v_to.is_finite():
		return from.lerp(to, t)
	if host != null and host.has_method("interpolate_network_snapshot"):
		return host.call("interpolate_network_snapshot", from, to, v_from, v_to, span, t)
	return Vector3(
		_axis(from.x, to.x, v_from.x, v_to.x, span, t),
		_axis(from.y, to.y, v_from.y, v_to.y, span, t),
		_axis(from.z, to.z, v_from.z, v_to.z, span, t))


## Each sample is [server_time, Vector3 position, yaw]. Extra samples provide
## better endpoint velocity estimates; two samples reproduce the original
## straight linear path exactly. Never derive tangents across a teleport.
static func sample_position(previous: Array, older: Array, newer: Array,
		following: Array, alpha: float, host: Node3D = null) -> Vector3:
	var from: Vector3 = older[1]
	var to: Vector3 = newer[1]
	var t0: float = float(older[0])
	var t1: float = float(newer[0])
	var span: float = t1 - t0
	if span <= 0.00001:
		return to
	var segment_velocity: Vector3 = (to - from) / span
	var v_from: Vector3 = segment_velocity
	var v_to: Vector3 = segment_velocity
	if previous.size() >= 2:
		var previous_pos: Vector3 = previous[1]
		var earlier_span: float = t1 - float(previous[0])
		if earlier_span > 0.00001 and earlier_span <= MAX_SAMPLE_SECONDS * 3.0 \
				and previous_pos.distance_to(from) <= TELEPORT_DISTANCE:
			v_from = (to - previous_pos) / earlier_span
	if following.size() >= 2:
		var following_pos: Vector3 = following[1]
		var later_span: float = float(following[0]) - t0
		if later_span > 0.00001 and later_span <= MAX_SAMPLE_SECONDS * 3.0 \
				and following_pos.distance_to(to) <= TELEPORT_DISTANCE:
			v_to = (following_pos - from) / later_span
	return hermite(from, to, v_from, v_to, span, alpha, host)
