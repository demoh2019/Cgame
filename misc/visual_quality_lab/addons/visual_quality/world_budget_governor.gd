extends Node
class_name WorldBudgetGovernor3D
## Runtime backpressure on main-thread scene instantiation and AI work.
## Reads CPU process/physics monitors; GPU-bound FPS alone does not throttle.

signal budget_changed(spawns_per_update: int, ai_cells_per_update: int)

@export var automatic_enabled: bool = true
@export_range(8.0, 50.0, 0.5) var target_cpu_ms: float = 16.7
@export_range(0.3, 2.0, 0.05) var low_load_ratio: float = 0.65
@export_range(0.8, 3.0, 0.05) var high_load_ratio: float = 1.08
@export_range(0.4, 3.0, 0.1) var evaluation_interval_seconds: float = 0.8
@export_range(1, 10, 1) var overload_windows: int = 3
@export_range(1, 15, 1) var recovery_windows: int = 5

var streamer: WorldStreamer3D
var ai_interest: WorldAIInterestManager3D
var telemetry: WorldTelemetry3D
var profile: int = 1
var last_cpu_ms: float = 0.0
var _elapsed: float = 0.0
var _last_sample_ms: int = -1
var _overload_streak: int = 0
var _recovery_streak: int = 0
var _spawn_cap: int = 2
var _ai_cap: int = 8


func _ready() -> void:
	set_quality_profile(profile)


func _process(delta: float) -> void:
	if not automatic_enabled or not is_instance_valid(telemetry) or delta <= 0.0:
		return
	_elapsed += delta
	if _elapsed < evaluation_interval_seconds:
		return
	_elapsed = 0.0
	var latest: Dictionary = telemetry.get_latest()
	if latest.is_empty():
		return
	var timestamp: int = int(latest.get("elapsed_ms", -1))
	if timestamp <= _last_sample_ms:
		return
	_last_sample_ms = timestamp
	evaluate_cpu_sample(float(latest.get("cpu_ms", 0.0)))


func evaluate_cpu_sample(cpu_ms: float) -> void:
	if not automatic_enabled or not is_finite(cpu_ms) or cpu_ms <= 0.0:
		return
	last_cpu_ms = cpu_ms
	if cpu_ms > target_cpu_ms * high_load_ratio:
		_overload_streak += 1
		_recovery_streak = 0
	elif cpu_ms < target_cpu_ms * low_load_ratio:
		_recovery_streak += 1
		_overload_streak = 0
	else:
		_overload_streak = 0
		_recovery_streak = 0
	var change: int = 0
	if _overload_streak >= overload_windows:
		change = -1
	elif _recovery_streak >= recovery_windows:
		change = 1
	if change == 0:
		return
	_overload_streak = 0
	_recovery_streak = 0
	if is_instance_valid(streamer):
		streamer.max_spawns_per_update = clampi(
			streamer.max_spawns_per_update + change, 1, _spawn_cap)
	if is_instance_valid(ai_interest):
		ai_interest.max_cells_per_update = clampi(
			ai_interest.max_cells_per_update + change * 2, 2, _ai_cap)
	budget_changed.emit(current_spawn_budget(), current_ai_budget())


func set_quality_profile(value: int) -> void:
	profile = clampi(value, 0, 2)
	var spawns: PackedInt32Array = PackedInt32Array([1, 2, 4])
	var ai_cells: PackedInt32Array = PackedInt32Array([6, 8, 12])
	_spawn_cap = spawns[profile]
	_ai_cap = ai_cells[profile]
	_overload_streak = 0
	_recovery_streak = 0
	_apply_defaults()


func set_automatic_enabled(value: bool) -> void:
	automatic_enabled = value
	_overload_streak = 0
	_recovery_streak = 0
	if not value:
		_apply_defaults()


func _apply_defaults() -> void:
	if is_instance_valid(streamer):
		streamer.max_spawns_per_update = _spawn_cap
	if is_instance_valid(ai_interest):
		ai_interest.max_cells_per_update = _ai_cap
	budget_changed.emit(current_spawn_budget(), current_ai_budget())


func current_spawn_budget() -> int:
	return streamer.max_spawns_per_update if is_instance_valid(streamer) else 0


func current_ai_budget() -> int:
	return ai_interest.max_cells_per_update if is_instance_valid(ai_interest) else 0


static func next_budget(current: int, direction: int, minimum: int, maximum: int) -> int:
	return clampi(current + signi(direction), minimum, maxi(minimum, maximum))
