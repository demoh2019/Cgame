extends RefCounted
## Facade for CgameCPUBudget (native) with the GDScript CpuBudget as fallback.
## Same API as scripts/shared/cpu_budget.gd.

const FALLBACK_PATH := "res://scripts/shared/cpu_budget.gd"

var _impl: Object = null
var _native: bool = false

## Smoothing factor of the exponential moving average of reported usage.
var smoothing: float:
	get:
		return _impl.smoothing if _impl != null else 0.0
	set(value):
		if _impl != null:
			_impl.smoothing = value

## Demand = smoothed usage * headroom, clamped to [min_ms, desired_ms].
var headroom: float:
	get:
		return _impl.headroom if _impl != null else 0.0
	set(value):
		if _impl != null:
			_impl.headroom = value


func _init() -> void:
	if ClassDB.class_exists("CgameCPUBudget"):
		_impl = ClassDB.instantiate("CgameCPUBudget")
		_native = true
	elif ResourceLoader.exists(FALLBACK_PATH):
		_impl = (load(FALLBACK_PATH) as GDScript).new()
	else:
		push_error("CpuBudget facade: neither CgameCPUBudget nor %s is available" % FALLBACK_PATH)


func is_native() -> bool:
	return _native


func register_system(system_name: String, priority: float, min_ms: float, desired_ms: float) -> void:
	if _impl != null:
		_impl.register_system(system_name, priority, min_ms, desired_ms)


func unregister_system(system_name: String) -> void:
	if _impl != null:
		_impl.unregister_system(system_name)


func system_count() -> int:
	return _impl.system_count() if _impl != null else 0


func demand_ms(system_name: String) -> float:
	return _impl.demand_ms(system_name) if _impl != null else 0.0


func allocate(frame_budget_ms: float) -> Dictionary:
	return _impl.allocate(frame_budget_ms) if _impl != null else {}


func allocation_ms(system_name: String) -> float:
	return _impl.allocation_ms(system_name) if _impl != null else 0.0


func report_usage(system_name: String, ms: float) -> void:
	if _impl != null:
		_impl.report_usage(system_name, ms)


func smoothed_usage_ms(system_name: String) -> float:
	return _impl.smoothed_usage_ms(system_name) if _impl != null else 0.0


func over_budget() -> PackedStringArray:
	return PackedStringArray(_impl.over_budget()) if _impl != null else PackedStringArray()
