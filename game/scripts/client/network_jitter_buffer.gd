extends RefCounted
## Adaptive, presentation-only network jitter buffer for simulated proxies.
## Server positions and combat remain authoritative. No future extrapolation.
## Arrival timestamps use a monotonic local clock, never FPS or wall time.

const BASE_DELAY := 0.12
const MAX_DELAY := 0.35
const EXPECTED_SNAPSHOT_STEP := 0.10
const MAX_NETWORK_GAP := 0.65
const MAX_EXTRA := 0.17
const EXTRA_MULTIPLIER := 1.35
const PEAK_RELEASE_PER_SECOND := 0.04
const DELAY_RELEASE_PER_SECOND := 0.03

var delay := BASE_DELAY
var _peak_jitter := 0.0
var _last_server_time := -1.0
var _last_arrival_time := -1.0
var _base_delay := BASE_DELAY
var _max_delay := MAX_DELAY
var _expected_step := EXPECTED_SNAPSHOT_STEP
var _accepted_packets := 0
var _ignored_packets := 0
var _resets := 0
var _network_gaps := 0


func configure(base_delay: float, max_delay: float, expected_snapshot_step: float) -> bool:
	if not is_finite(base_delay) or not is_finite(max_delay) \
			or not is_finite(expected_snapshot_step) \
			or base_delay < 0.01 or base_delay > 1.0 \
			or max_delay < base_delay or max_delay > 1.0 \
			or expected_snapshot_step < 0.01 or expected_snapshot_step > 1.0:
		return false
	_base_delay = base_delay
	_max_delay = max_delay
	_expected_step = expected_snapshot_step
	reset()
	return true


func _reset_timing() -> void:
	delay = _base_delay
	_peak_jitter = 0.0
	_last_server_time = -1.0
	_last_arrival_time = -1.0


func get_stats() -> Dictionary:
	return {
		"delay": delay,
		"peak_jitter": _peak_jitter,
		"accepted_packets": _accepted_packets,
		"ignored_packets": _ignored_packets,
		"resets": _resets,
		"network_gaps": _network_gaps,
		"expected_snapshot_step": _expected_step,
		"native_backend": false,
	}



func reset() -> void:
	_reset_timing()
	_accepted_packets = 0
	_ignored_packets = 0
	_resets = 0
	_network_gaps = 0


## Call on the same main thread as EntityView.update_from. Repeated reads of
## the same snapshot (render FPS > server tick) never change the delay.
func observe(server_time: float, local_arrival_time: float) -> float:
	if not is_finite(server_time) or not is_finite(local_arrival_time) \
			or server_time < 0.0 or local_arrival_time < 0.0:
		_ignored_packets += 1
		return delay
	# A frame loop may see the same snapshot thousands of times while
	# disconnected; this is NOT an arrival event even after several seconds.
	if _last_server_time >= 0.0 and server_time <= _last_server_time \
			and server_time >= _last_server_time - 0.5:
		_ignored_packets += 1
		return delay
	if _last_server_time < 0.0 or server_time < _last_server_time - 0.5 \
			or local_arrival_time < _last_arrival_time \
			or local_arrival_time - _last_arrival_time > 2.0:
		if _last_server_time >= 0.0:
			_resets += 1
		_reset_timing()
		_last_server_time = server_time
		_last_arrival_time = local_arrival_time
		_accepted_packets += 1
		return delay
	if server_time <= _last_server_time:
		_ignored_packets += 1
		return delay
	var server_span: float = server_time - _last_server_time
	var arrival_span: float = local_arrival_time - _last_arrival_time
	_last_server_time = server_time
	_last_arrival_time = local_arrival_time
	_accepted_packets += 1
	if server_span > MAX_NETWORK_GAP:
		# Reconnect or background pause: do not drag huge stale jitter tails.
		_peak_jitter = 0.0
		delay = _base_delay
		_network_gaps += 1
		return delay
	# Late network arrival and missing server ticks both need more historical
	# snapshots. A subsequent packet arriving early cannot cancel the spike.
	var late: float = maxf(0.0, arrival_span - server_span)
	var skipped: float = maxf(0.0, server_span - _expected_step)
	var extra: float = minf(MAX_EXTRA, maxf(late, skipped))
	_peak_jitter = maxf(extra, maxf(0.0,
		_peak_jitter - arrival_span * PEAK_RELEASE_PER_SECOND))
	var target: float = clampf(_base_delay + _peak_jitter * EXTRA_MULTIPLIER,
		_base_delay, _max_delay)
	if target > delay:
		delay = target
	else:
		delay = maxf(target, delay - arrival_span * DELAY_RELEASE_PER_SECOND)
	return delay


## Same deterministic algorithm as Cgame's native Node3D extension, with a
## stock-Godot fallback. One policy instance controls all visible actors.
static func advance_clock(render_time: float, newest_time: float, target_delay: float,
		delta: float, host: Node3D = null) -> float:
	if host != null and host.has_method("advance_network_render_time"):
		return float(host.call("advance_network_render_time",
			render_time, newest_time, target_delay, delta))
	if not is_finite(newest_time) or newest_time < 0.0 \
			or not is_finite(target_delay) or target_delay < 0.0:
		return render_time if is_finite(render_time) else 0.0
	var target: float = newest_time - clampf(target_delay, 0.0, MAX_DELAY)
	if not is_finite(render_time) or render_time < 0.0 \
			or absf(target - render_time) > 0.5:
		return target
	if not is_finite(delta) or delta <= 0.0:
		return minf(render_time, newest_time)
	var step: float = minf(delta, 0.2)
	var rate: float = clampf(1.0 + 2.0 * (target - render_time), 0.4, 1.6)
	return minf(newest_time, render_time + step * rate)
