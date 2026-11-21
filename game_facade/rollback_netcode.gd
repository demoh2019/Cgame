extends RefCounted
## Facade for the rollback netcode. Prefers the native engine class CgameRollbackNetcode (module
## cgame_rollback) and falls back to scripts/shared/rollback_netcode.gd when the engine build does not
## include it. Use create() instead of new().
##
## Differences: native player ids must be integers; frame/confirmed_frame/rollbacks/... are read-only
## properties in the native class (the script exposes plain variables); native stepping can also use a
## native step provider (see the physics_rollback facade).

const _FALLBACK_SCRIPT = preload("res://scripts/shared/rollback_netcode.gd")
const NATIVE_CLASS: String = "CgameRollbackNetcode"

static var _native: int = -1 # -1 unknown, 0 no, 1 yes


static func is_native() -> bool:
	if _native < 0:
		_native = 1 if ClassDB.class_exists(NATIVE_CLASS) else 0
	return _native == 1


static func create() -> RefCounted:
	if is_native():
		return ClassDB.instantiate(NATIVE_CLASS)
	return _FALLBACK_SCRIPT.new()


static func state_checksum(state: Dictionary) -> int:
	if is_native():
		return (ClassDB.instantiate(NATIVE_CLASS) as RefCounted).state_checksum(state)
	return _FALLBACK_SCRIPT.state_checksum(state)
