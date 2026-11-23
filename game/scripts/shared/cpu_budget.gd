extends RefCounted
## Unified per-frame CPU budget allocator. Systems register {priority, min_ms, desired_ms};
## allocate() splits the frame budget: minima are guaranteed first (scaled down proportionally if
## they alone exceed the budget), the remainder is shared priority-weighted by water-filling, each
## system capped by its demand. Demand adapts to smoothed measured usage via report_usage().
##
## Concepts only (original GDScript): Unreal time-sliced "budgeted" subsystems, Unity Adaptive
## Performance, and the common weighted max-min fair share scheme.

## Smoothing factor of the exponential moving average of reported usage.
var smoothing: float = 0.2
## Demand = smoothed usage * headroom, clamped to [min_ms, desired_ms].
var headroom: float = 1.25

var _systems: Dictionary = {}
var _allocation: Dictionary = {}


func register_system(system_name: String, priority: float, min_ms: float, desired_ms: float) -> void:
	if system_name.is_empty():
		return
	var mn: float = maxf(min_ms, 0.0) if is_finite(min_ms) else 0.0
	var want: float = maxf(desired_ms, mn) if is_finite(desired_ms) else mn
	var weight: float = maxf(priority, 0.0001) if is_finite(priority) else 0.0001
	_systems[system_name] = {"priority": weight, "min_ms": mn,
		"desired_ms": want, "ema": -1.0, "last": 0.0}
	_allocation.erase(system_name)


func unregister_system(system_name: String) -> void:
	_systems.erase(system_name)
	_allocation.erase(system_name)


func system_count() -> int:
	return _systems.size()


## Current demand of a system after adaptation.
func demand_ms(system_name: String) -> float:
	if not _systems.has(system_name):
		return 0.0
	var s: Dictionary = _systems[system_name]
	var ema: float = s["ema"]
	var mn: float = s["min_ms"]
	var want: float = s["desired_ms"]
	if ema < 0.0:
		return want
	var safe_headroom: float = maxf(headroom, 0.0) if is_finite(headroom) else 1.0
	return clampf(ema * safe_headroom, mn, want)


func allocate(frame_budget_ms: float) -> Dictionary:
	# A dropped/invalid frame must never produce a negative or NaN CPU grant.
	var budget: float = maxf(frame_budget_ms, 0.0) if is_finite(frame_budget_ms) else 0.0
	var out: Dictionary = {}
	var min_sum := 0.0
	for n in _systems:
		var s: Dictionary = _systems[n]
		min_sum += float(s["min_ms"])
	if min_sum >= budget:
		var scale: float = budget / min_sum if min_sum > 0.0 else 0.0
		for n in _systems:
			var s: Dictionary = _systems[n]
			out[n] = float(s["min_ms"]) * scale
		_allocation = out
		return out
	var remaining: float = budget
	var open: Array = []
	for n in _systems:
		var s: Dictionary = _systems[n]
		out[n] = float(s["min_ms"])
		remaining -= float(s["min_ms"])
		open.append(n)
	# Water-filling: share what is left by priority; clamp at demand and redistribute.
	while remaining > 0.000001 and not open.is_empty():
		var wsum := 0.0
		for n in open:
			wsum += float((_systems[n] as Dictionary)["priority"])
		var next_open: Array = []
		var spent := 0.0
		var capped := false
		for n in open:
			var share := remaining * float((_systems[n] as Dictionary)["priority"]) / wsum
			var room := demand_ms(n) - float(out[n])
			if share >= room:
				out[n] = float(out[n]) + maxf(room, 0.0)
				spent += maxf(room, 0.0)
				capped = true
			else:
				next_open.append(n)
		if not capped:
			for n in open:
				var share := remaining * float((_systems[n] as Dictionary)["priority"]) / wsum
				out[n] = float(out[n]) + share
			remaining = 0.0
			break
		remaining -= spent
		open = next_open
	_allocation = out
	return out


func allocation_ms(system_name: String) -> float:
	return float(_allocation.get(system_name, 0.0))


func report_usage(system_name: String, ms: float) -> void:
	if not _systems.has(system_name) or not is_finite(ms) or ms < 0.0:
		return
	var s: Dictionary = _systems[system_name]
	var ema: float = s["ema"]
	var blend: float = clampf(smoothing, 0.0, 1.0) if is_finite(smoothing) else 0.2
	s["ema"] = ms if ema < 0.0 else lerpf(ema, ms, blend)
	s["last"] = ms


func smoothed_usage_ms(system_name: String) -> float:
	if not _systems.has(system_name):
		return 0.0
	return maxf(float((_systems[system_name] as Dictionary)["ema"]), 0.0)


## Systems whose smoothed usage exceeds their last allocation, worst overshoot first.
func over_budget() -> PackedStringArray:
	var rows: Array = []
	for n in _systems:
		var s: Dictionary = _systems[n]
		var ema: float = s["ema"]
		if ema < 0.0 or not _allocation.has(n):
			continue
		var over := ema - float(_allocation[n])
		if over > 0.0001:
			rows.append([over, n])
	rows.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
	var out := PackedStringArray()
	for r in rows:
		out.append(str(r[1]))
	return out
