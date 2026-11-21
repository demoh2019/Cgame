extends RefCounted
## Server-only CPU tick telemetry and conservative encounter backpressure.
## Existing actors still simulate every tick; only future random incident
## reinforcements are reduced on sustained overload.

const HISTORY_CAP: int = 200
const WINDOW_TICKS: int = 20
const MIN_SPAWN_CAP: int = 2
const MAX_SPAWN_CAP: int = 10
const TARGET_TICK_MS: float = 50.0 # GameServer runs at Defs.TICK_RATE = 20.
const HIGH_RATIO: float = 0.90
const LOW_RATIO: float = 0.60
const HIGH_WINDOWS: int = 3
const LOW_WINDOWS: int = 5

var enabled: bool = true
var spawn_cap: int = MAX_SPAWN_CAP
var last_window_p95_ms: float = 0.0
var total_ticks: int = 0
var _history: Array[float] = []
var _window: Array[float] = []
var _next_history_slot: int = 0
var _high_streak: int = 0
var _low_streak: int = 0


## Called by the dedicated server after the *authoritative network+simulation
## tick*, before optional disk checkpoint work. Invalid samples are ignored.
func observe_tick(elapsed_usec: int, active_players: int) -> void:
	if elapsed_usec < 0 or elapsed_usec > 60000000 or active_players < 0:
		return
	var tick_ms: float = float(elapsed_usec) / 1000.0
	total_ticks += 1
	if _history.size() < HISTORY_CAP:
		_history.append(tick_ms)
	else:
		_history[_next_history_slot] = tick_ms
	_next_history_slot = (_next_history_slot + 1) % HISTORY_CAP

	# Idle servers should never throttle the next real survivor's incident.
	if active_players == 0:
		_window.clear()
		_high_streak = 0
		_low_streak = 0
		return
	_window.append(tick_ms)
	if _window.size() < WINDOW_TICKS:
		return
	last_window_p95_ms = percentile_nearest_rank(_window, 0.95)
	_window.clear()
	if not enabled:
		return
	if last_window_p95_ms > TARGET_TICK_MS * HIGH_RATIO:
		_high_streak += 1
		_low_streak = 0
	elif last_window_p95_ms < TARGET_TICK_MS * LOW_RATIO:
		_low_streak += 1
		_high_streak = 0
	else:
		_high_streak = 0
		_low_streak = 0
	if _high_streak >= HIGH_WINDOWS:
		spawn_cap = maxi(MIN_SPAWN_CAP, spawn_cap - 2)
		_high_streak = 0
	elif _low_streak >= LOW_WINDOWS:
		spawn_cap = mini(MAX_SPAWN_CAP, spawn_cap + 1)
		_low_streak = 0


func set_enabled(value: bool) -> void:
	enabled = value
	_high_streak = 0
	_low_streak = 0
	_window.clear()
	if not enabled:
		spawn_cap = MAX_SPAWN_CAP


func history_count() -> int:
	return _history.size()


func samples_oldest_first() -> Array[float]:
	var samples: Array[float] = []
	var n: int = _history.size()
	var first: int = _next_history_slot if n == HISTORY_CAP else 0
	for i in range(n):
		samples.append(_history[(first + i) % n])
	return samples


func snapshot() -> Dictionary:
	var high: float = 0.0
	for sample in _history:
		high = maxf(high, sample)
	return {
		"sample_count": _history.size(),
		"total_ticks": total_ticks,
		"tick_p95_ms": percentile_nearest_rank(_history, 0.95),
		"last_window_p95_ms": last_window_p95_ms,
		"tick_max_ms": high,
		"incident_spawn_cap": spawn_cap,
		"adaptive_enabled": enabled
	}


## Deterministic nearest-rank p95; never mutates caller's samples.
static func percentile_nearest_rank(samples: Array[float], percentile: float) -> float:
	if samples.is_empty() or not is_finite(percentile):
		return 0.0
	var sorted_samples: Array[float] = samples.duplicate()
	sorted_samples.sort()
	var rank: int = clampi(ceili(clampf(percentile, 0.0, 1.0) * sorted_samples.size()) - 1,
		0, sorted_samples.size() - 1)
	return sorted_samples[rank]
