extends RefCounted
## Server-side lag compensation (Source engine / Overwatch / UE5 rewind):
## a short history of every survivor's position lets the server judge a PvP
## swing or shot against where the target was on the attacker's screen,
## i.e. half the round trip plus the client's interpolation delay ago.
## Rewind is capped so high-ping players cannot hit around corners.

const HISTORY_SECONDS := 0.5
const MAX_REWIND := 0.25
const CLIENT_INTERPOLATION := 0.12 # network_jitter_buffer.gd BASE_DELAY.

var _history: Dictionary = {} # id -> Array of [time, Vector3]


func record(id: int, now: float, position: Vector3) -> void:
	if not is_finite(now) or not position.is_finite():
		return
	var samples: Array = _history.get(id, [])
	if not samples.is_empty():
		var last_time: float = float(samples[-1][0])
		if now < last_time:
			return
		if now == last_time:
			samples[-1] = [now, position]
			return
	samples.append([now, position])
	while samples.size() > 128 or (samples.size() > 2 and now - float(samples[0][0]) > HISTORY_SECONDS):
		samples.pop_front()
	_history[id] = samples


## Same diagnostic as the native engine implementation.
func sample_count(id: int) -> int:
	var samples: Array = _history.get(id, [])
	return samples.size()


func forget(id: int) -> void:
	_history.erase(id)


func prune(alive_ids: Dictionary) -> void:
	for id in _history.keys():
		if not alive_ids.has(id):
			_history.erase(id)


## How far back to judge an attacker with this round-trip time (seconds).
static func rewind_for(round_trip: float) -> float:
	if not is_finite(round_trip) or round_trip <= 0.0:
		return 0.0
	return clampf(round_trip * 0.5 + CLIENT_INTERPOLATION, 0.0, MAX_REWIND)


## Interpolated position at `at`; `fallback` when no usable history exists.
func position_at(id: int, at: float, fallback: Vector3) -> Vector3:
	var samples: Array = _history.get(id, [])
	if not is_finite(at) or samples.is_empty() or at >= float(samples[-1][0]):
		return fallback
	if at <= float(samples[0][0]):
		return samples[0][1]
	for i in range(samples.size() - 1, 0, -1):
		var t0: float = float(samples[i - 1][0])
		var t1: float = float(samples[i][0])
		if at >= t0:
			var k: float = 0.0 if t1 <= t0 else (at - t0) / (t1 - t0)
			return (samples[i - 1][1] as Vector3).lerp(samples[i][1], k)
	return fallback
