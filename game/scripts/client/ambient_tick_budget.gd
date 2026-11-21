extends RefCounted
## Budgeted cosmetic update dispatcher for the game client.
## No Node references, world writes or network simulation are stored here.
## Each lane accumulates elapsed time while skipped and receives a bounded dt
## when scheduled, so all presentation work stays on the main thread.

const LANES := ["dragonflies", "dust_devils", "tumbleweeds", "dusk_bats"]
const HZ_BY_QUALITY := [12.0, 18.0, 30.0, 60.0]
const MAX_STEP := 0.16

var _elapsed: Dictionary = {}
var _reserved: Array[String] = []
var _tie_start: int = 0
var _quality: int = -1
var _quality_changed: bool = true
var _budget: int = 1
var _spent: int = 0
var _pressure: float = 0.0
var _time_budget_us: int = 2500
var _frame_cost_us: int = 0
var _previous_frame_cost_us: int = 0
var _updated_total: int = 0
var _skipped_total: int = 0
var _last_updated: int = 0
var _last_skipped: int = 0


func begin_frame(delta: float, quality: int) -> void:
	var safe_quality: int = clampi(quality, 0, 3)
	_quality_changed = _quality != safe_quality
	_quality = safe_quality
	_previous_frame_cost_us = _frame_cost_us
	_frame_cost_us = 0
	_spent = 0
	_last_updated = 0
	_last_skipped = 0
	if is_finite(delta) and delta > 0.0:
		if delta > 0.030:
			_pressure = minf(1.0, _pressure + 0.16)
		elif delta < 0.020:
			_pressure = maxf(0.0, _pressure - 0.05)
	var reduction: int = 2 if _pressure >= 0.8 else (1 if _pressure >= 0.4 else 0)
	_budget = maxi(1, mini(LANES.size(), safe_quality + 1 - reduction))

	# Pick due lanes before they call consume(). Previous fixed-order grants
	# could starve dusk bats whenever dust devils used the only low-tier slot.
	_reserved.clear()
	if _quality_changed:
		_tie_start = 0
		return
	_tie_start = (_tie_start + 1) % LANES.size()
	if not is_finite(delta) or delta <= 0.0:
		return
	var interval: float = 1.0 / HZ_BY_QUALITY[_quality]
	for _slot in range(_budget):
		var pick: String = ""
		var best_elapsed: float = -1.0
		for offset in range(LANES.size()):
			var lane: String = LANES[(_tie_start + offset) % LANES.size()]
			if _reserved.has(lane):
				continue
			var due: float = minf(float(_elapsed.get(lane, 0.0)) + delta, MAX_STEP)
			if due + 0.000001 >= interval and due > best_elapsed + 0.000000000001:
				pick = lane
				best_elapsed = due
		if pick.is_empty():
			break
		_reserved.append(pick)


## Returns 0 when the lane should not be updated this frame, or the
## accumulated elapsed time when an update is due. A visibility transition
## always takes effect immediately even if the per-frame budget is exhausted.
func consume(lane: String, delta: float, force: bool = false) -> float:
	if not LANES.has(lane) or not is_finite(delta) or delta <= 0.0:
		return 0.0
	var elapsed: float = minf(float(_elapsed.get(lane, 0.0)) + delta, MAX_STEP)
	if force or _quality_changed:
		_elapsed[lane] = 0.0
		_record_update()
		return elapsed
	_elapsed[lane] = elapsed
	var interval: float = 1.0 / HZ_BY_QUALITY[_quality if _quality >= 0 else 0]
	if elapsed + 0.000001 < interval or _spent >= _budget or not _reserved.has(lane) \
			or (_time_budget_us > 0 and _frame_cost_us >= _time_budget_us):
		_last_skipped += 1
		_skipped_total += 1
		return 0.0
	_spent += 1
	_reserved.erase(lane)
	_elapsed[lane] = 0.0
	_record_update()
	return elapsed


func reset() -> void:
	_elapsed.clear()
	_reserved.clear()
	_tie_start = 0
	_quality = -1
	_quality_changed = true
	_pressure = 0.0
	_frame_cost_us = 0
	_previous_frame_cost_us = 0
	_budget = 1
	_spent = 0
	_last_updated = 0
	_last_skipped = 0


func _record_update() -> void:
	_last_updated += 1
	_updated_total += 1


func updated_total() -> int:
	return _updated_total


func skipped_total() -> int:
	return _skipped_total


func current_budget() -> int:
	return _budget


func pressure_percent() -> float:
	return _pressure * 100.0


func last_frame_counts() -> Vector2i:
	return Vector2i(_last_updated, _last_skipped)

## Zero disables the CPU time cap; a positive limit is a soft upper bound.
func set_frame_time_budget_us(budget_us: int) -> bool:
	if budget_us < 0 or budget_us > 1000000:
		return false
	_time_budget_us = budget_us
	return true


func get_frame_time_budget_us() -> int:
	return _time_budget_us


func record_cost(lane: String, elapsed_us: int) -> bool:
	if not LANES.has(lane) or elapsed_us < 0 or elapsed_us > 10000000:
		return false
	_frame_cost_us = mini(1000000000, _frame_cost_us + elapsed_us)
	return true


func current_frame_cost_us() -> int:
	return _frame_cost_us


func last_frame_cost_us() -> int:
	return _previous_frame_cost_us

