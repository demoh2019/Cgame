extends RefCounted
## Facade for CgameProfiledMutex (native) with the GDScript LockProfiler as fallback.
##
## Mirrors scripts/shared/lock_profiler.gd: `LockProfiler.create(name)` returns an object with
## lock()/try_lock()/unlock()/stats()/reset(); report(), sync_point(), sync_report() and
## long_syncs() are static. The native mutex waits by blocking (no spin loop) and shows contended
## waits in CgameTrace.

const FALLBACK_PATH := "res://scripts/shared/lock_profiler.gd"


static func _native() -> bool:
	return ClassDB.class_exists("CgameProfiledMutex")


static func _fallback() -> GDScript:
	if ResourceLoader.exists(FALLBACK_PATH):
		return load(FALLBACK_PATH) as GDScript
	return null


static func is_native() -> bool:
	return _native()


## Native: a CgameProfiledMutex. Fallback: LockProfiler.ProfiledMutex. Both share the same API.
static func create(mutex_name: String) -> Object:
	if _native():
		return ClassDB.instantiate("CgameProfiledMutex").call("create", mutex_name)
	var fb := _fallback()
	return fb.create(mutex_name) if fb != null else null


static func clear() -> void:
	if _native():
		ClassDB.instantiate("CgameProfiledMutex").call("clear_registry")
		return
	var fb := _fallback()
	if fb != null:
		fb.clear()


static func report() -> Array:
	if _native():
		return ClassDB.instantiate("CgameProfiledMutex").call("report")
	var fb := _fallback()
	return fb.report() if fb != null else []


static func sync_point(point_name: String, callable: Callable) -> Variant:
	if _native():
		return ClassDB.instantiate("CgameProfiledMutex").call("sync_point", point_name, callable)
	var fb := _fallback()
	return fb.sync_point(point_name, callable) if fb != null else callable.call()


static func sync_report() -> Array:
	if _native():
		return ClassDB.instantiate("CgameProfiledMutex").call("sync_report")
	var fb := _fallback()
	return fb.sync_report() if fb != null else []


static func long_syncs() -> PackedStringArray:
	if _native():
		return ClassDB.instantiate("CgameProfiledMutex").call("long_syncs")
	var fb := _fallback()
	return fb.long_syncs() if fb != null else PackedStringArray()


static func set_long_sync_threshold_ms(ms: float) -> void:
	if _native():
		ClassDB.instantiate("CgameProfiledMutex").call("set_long_sync_threshold_ms", ms)
		return
	var fb := _fallback()
	if fb != null:
		fb.long_sync_threshold_ms = ms
