extends RefCounted
## Budgeted cosmetic update dispatcher for the game client.
## No Node references, world writes or network simulation are stored here.
## Each lane accumulates elapsed time while skipped and receives a bounded dt
## when scheduled, so all presentation work stays on the main thread.

const LANES := ["dragonflies", "dust_devils", "tumbleweeds", "dusk_bats"]
const HZ_BY_QUALITY := [12.0, 18.0, 30.0, 60.0]
const MAX_STEP := 0.16

var _elapsed: Dictionary = {}
var _importance: Dictionary = {}
var _rate_scale: Dictionary = {} # Frequency, not scheduling importance.
var _disabled: Dictionary = {}
var _refresh_pending: Dictionary = {}
var _max_deferred_frames: Dictionary = {} # Opt-in soft deadlines.
var _estimates: Dictionary = {}
var _overdue: Dictionary = {}
var _reserved_estimate_us: int = 0
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
var _lane_frame_cost_us: Dictionary = {}
var _lane_previous_frame_cost_us: Dictionary = {}
var _updated_total: int = 0
var _skipped_total: int = 0
var _last_updated: int = 0
var _last_skipped: int = 0


## Temporarily pause irrelevant lanes without discarding learned CPU costs.
## Re-enabling requests one immediate refresh on the next consume().
func set_lane_enabled(lane: String, enabled: bool) -> bool:
	if not LANES.has(lane):
		return false
	if is_lane_enabled(lane) == enabled:
		return true
	if enabled:
		_disabled.erase(lane)
		_refresh_pending[lane] = true
	else:
		_disabled[lane] = true
		_refresh_pending.erase(lane)
	_elapsed[lane] = 0.0
	_overdue[lane] = 0
	_reserved.clear()
	_reserved_estimate_us = 0
	return true


func is_lane_enabled(lane: String) -> bool:
	return LANES.has(lane) and not _disabled.has(lane)


func get_enabled_lane_count() -> int:
	return LANES.size() - _disabled.size()


func begin_frame(delta: float, quality: int) -> void:
	var safe_quality: int = clampi(quality, 0, 3)
	_quality_changed = _quality != safe_quality
	_quality = safe_quality
	_previous_frame_cost_us = _frame_cost_us
	_frame_cost_us = 0
	# Mirror the native fixed-size frame rotation without a dictionary copy.
	for lane in LANES:
		_lane_previous_frame_cost_us[lane] = int(_lane_frame_cost_us.get(lane, 0))
		_lane_frame_cost_us[lane] = 0
	_spent = 0
	_last_updated = 0
	_last_skipped = 0
	_reserved_estimate_us = 0
	if is_finite(delta) and delta > 0.0:
		if delta > 0.030:
			_pressure = minf(1.0, _pressure + 0.16)
		elif delta < 0.020:
			_pressure = maxf(0.0, _pressure - 0.05)
	var reduction: int = 2 if _pressure >= 0.8 else (1 if _pressure >= 0.4 else 0)
	var enabled_count: int = get_enabled_lane_count()
	_budget = 0 if enabled_count == 0 else maxi(1, mini(enabled_count, safe_quality + 1 - reduction))

	# Pick due lanes before they call consume(). Previous fixed-order grants
	# could starve dusk bats whenever dust devils used the only low-tier slot.
	_reserved.clear()
	if _quality_changed:
		_tie_start = 0
		return
	_tie_start = (_tie_start + 1) % LANES.size()
	if not is_finite(delta) or delta <= 0.0:
		return
	for _slot in range(_budget):
		var pick: String = ""
		var best_priority: float = -1.0
		# Fit already measured costs first; allow one over-budget channel
		# when none fit, so expensive ambience can still make progress.
		for cost_pass in range(2):
			if cost_pass == 1 and not _reserved.is_empty():
				break
			for offset in range(LANES.size()):
				var lane: String = LANES[(_tie_start + offset) % LANES.size()]
				if _reserved.has(lane) or not is_lane_enabled(lane) or _refresh_pending.has(lane):
					continue
				var due: float = minf(float(_elapsed.get(lane, 0.0)) + delta, MAX_STEP)
				var interval: float = 1.0 / (HZ_BY_QUALITY[_quality] * float(_rate_scale.get(lane, 1.0)))
				if due + 0.000001 < interval:
					continue
				var estimated: int = int(_estimates.get(lane, 0))
				var age: int = int(_overdue.get(lane, 0))
				var exceeds: bool = _time_budget_us > 0 and estimated > 0 \
					and _reserved_estimate_us + estimated > _time_budget_us
				var deadline: int = int(_max_deferred_frames.get(lane, 0))
				var deadline_due: bool = deadline > 0 and age >= deadline
				if cost_pass == 0 and exceeds and age < 48 and not deadline_due:
					continue
				# Deadline promotion changes reservation priority, not slots.
				var priority: float = (1000.0 + float(age - deadline) * 0.1 if deadline_due else 0.0) + due * float(_importance.get(lane, 1.0)) \
					+ float(mini(age, 120)) * 0.012
				if priority > best_priority + 0.000000000001:
					pick = lane
					best_priority = priority
			if not pick.is_empty():
				break
		if pick.is_empty():
			break
		_reserved.append(pick)
		_reserved_estimate_us = mini(1000000000,
			_reserved_estimate_us + int(_estimates.get(pick, 0)))
	for lane in LANES:
		if not is_lane_enabled(lane) or _refresh_pending.has(lane):
			continue
		var due: float = minf(float(_elapsed.get(lane, 0.0)) + delta, MAX_STEP)
		var interval: float = 1.0 / (HZ_BY_QUALITY[_quality] * float(_rate_scale.get(lane, 1.0)))
		if due + 0.000001 >= interval and not _reserved.has(lane):
			_overdue[lane] = mini(120, int(_overdue.get(lane, 0)) + 1)


## Returns 0 when the lane should not be updated this frame, or the
## accumulated elapsed time when an update is due. A visibility transition
## always takes effect immediately even if the per-frame budget is exhausted.
func consume(lane: String, delta: float, force: bool = false) -> float:
	if not LANES.has(lane) or not is_finite(delta) or delta <= 0.0:
		return 0.0
	if not is_lane_enabled(lane) and not force:
		return 0.0
	var elapsed: float = minf(float(_elapsed.get(lane, 0.0)) + delta, MAX_STEP)
	if force or _quality_changed or _refresh_pending.has(lane):
		_refresh_pending.erase(lane)
		_reserved.erase(lane)
		_elapsed[lane] = 0.0
		_overdue[lane] = 0
		_record_update()
		return elapsed
	_elapsed[lane] = elapsed
	var interval: float = 1.0 / (HZ_BY_QUALITY[_quality if _quality >= 0 else 0] * float(_rate_scale.get(lane, 1.0)))
	if elapsed + 0.000001 < interval or _spent >= _budget or not _reserved.has(lane) \
			or (_time_budget_us > 0 and _frame_cost_us >= _time_budget_us):
		_last_skipped += 1
		_skipped_total += 1
		return 0.0
	_spent += 1
	_reserved.erase(lane)
	_elapsed[lane] = 0.0
	_overdue[lane] = 0
	_record_update()
	return elapsed


func reset() -> void:
	_elapsed.clear()
	_overdue.clear()
	_refresh_pending.clear()
	_reserved_estimate_us = 0
	_reserved.clear()
	_tie_start = 0
	_quality = -1
	_quality_changed = true
	_pressure = 0.0
	_frame_cost_us = 0
	_previous_frame_cost_us = 0
	_lane_frame_cost_us.clear()
	_lane_previous_frame_cost_us.clear()
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
	if elapsed_us > 0:
		var previous: int = int(_estimates.get(lane, 0))
		_estimates[lane] = elapsed_us if previous == 0 else \
			int((3 * previous + elapsed_us + 2) / 4)
	_frame_cost_us = mini(1000000000, _frame_cost_us + elapsed_us)
	_lane_frame_cost_us[lane] = mini(1000000000,
		int(_lane_frame_cost_us.get(lane, 0)) + elapsed_us)
	return true


## Rate controls how soon a lane becomes eligible. Importance controls how
## urgent it is once due; the two settings deliberately remain independent.
func set_lane_rate_scale(lane: String, scale: float) -> bool:
	if not LANES.has(lane) or not is_finite(scale) or scale < 0.75 or scale > 2.0:
		return false
	_rate_scale[lane] = scale
	return true


func get_lane_rate_scale(lane: String) -> float:
	if not LANES.has(lane):
		return -1.0
	return float(_rate_scale.get(lane, 1.0))


## A soft deferral deadline only changes which already-due lane is reserved.
## Zero disables it; global per-frame slots and measured CPU caps stay intact.
func set_lane_max_deferred_frames(lane: String, frames: int) -> bool:
	if not LANES.has(lane) or frames < 0 or frames > 120:
		return false
	_max_deferred_frames[lane] = frames
	return true


func get_lane_max_deferred_frames(lane: String) -> int:
	return int(_max_deferred_frames.get(lane, 0)) if LANES.has(lane) else -1


func get_deadline_overdue_lane_count() -> int:
	var count: int = 0
	for lane in LANES:
		var deadline: int = int(_max_deferred_frames.get(lane, 0))
		if deadline > 0 and int(_overdue.get(lane, 0)) >= deadline:
			count += 1
	return count


## Deterministic mapping of existing scene importance to a conservative rate.
## 0.25 -> 0.75x, 1.0 -> 1.0x, 4.0 -> 1.5x. No per-frame allocations.
static func rate_scale_for_importance(importance: float) -> float:
	if not is_finite(importance):
		return 1.0
	var safe: float = clampf(importance, 0.25, 4.0)
	if safe <= 1.0:
		return 0.75 + (safe - 0.25) / 3.0
	return 1.0 + (safe - 1.0) / 6.0


## Only currently significant ambient effects receive a short deadline.
static func deadline_frames_for_importance(importance: float) -> int:
	return 8 if is_finite(importance) and importance >= 2.0 else 0


func set_lane_importance(lane: String, importance: float) -> bool:
	if not LANES.has(lane) or not is_finite(importance) \
			or importance < 0.25 or importance > 4.0:
		return false
	_importance[lane] = importance
	return true


func get_lane_importance(lane: String) -> float:
	return float(_importance.get(lane, 1.0)) if LANES.has(lane) else -1.0


## Caller-measured CPU microseconds from the previous completed frame.
func get_lane_last_frame_cost_us(lane: String) -> int:
	return int(_lane_previous_frame_cost_us.get(lane, 0)) if LANES.has(lane) else -1


func get_lane_estimated_cost_us(lane: String) -> int:
	return int(_estimates.get(lane, 0)) if LANES.has(lane) else -1


func get_reserved_estimated_cost_us() -> int:
	return _reserved_estimate_us


## Scene relevance weights are independent of the server simulation.
static func suggested_importance(daylight: float, storming: bool, underground: bool) -> Dictionary:
	var light: float = clampf(daylight, 0.0, 1.0) if is_finite(daylight) else 0.5
	if underground:
		return {
			"dust_devils": 0.25, "dragonflies": 0.25,
			"tumbleweeds": 0.25, "dusk_bats": 0.25
		}
	return {
		"dust_devils": 2.0 if storming else 1.0,
		"dragonflies": 3.0 if light > 0.55 and not storming else 0.5,
		"tumbleweeds": 0.5 if storming else 1.2,
		"dusk_bats": 3.0 if light < 0.4 else 0.4
	}


func current_frame_cost_us() -> int:
	return _frame_cost_us


func last_frame_cost_us() -> int:
	return _previous_frame_cost_us

