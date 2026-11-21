extends RefCounted
## Facade over the thermal / battery governor. Prefers the native CgameThermalGovernor (modules/cgame_platform)
## and falls back to scripts/client/thermal_governor.gd. Both objects have configure, sample_frame, record_battery,
## drain_per_hour, hours_remaining, fps_cap, quality_step, apply_to and budget_ms.

const LEGACY = preload("res://scripts/client/thermal_governor.gd")
const NATIVE_CLASS := &"CgameThermalGovernor"


static func is_native() -> bool:
	return ClassDB.class_exists(NATIVE_CLASS)


static func create(target_fps: int = 60) -> Object:
	var governor: Object
	if is_native():
		governor = ClassDB.instantiate(NATIVE_CLASS)
	else:
		governor = LEGACY.new()
	governor.configure(target_fps)
	return governor


## Platform battery probe: {available, percent, charging}.
static func read_system_battery() -> Dictionary:
	if is_native():
		var probe: Object = ClassDB.instantiate(NATIVE_CLASS)
		return probe.read_system_battery()
	return LEGACY.read_system_battery()
