extends RefCounted
## Facade for the physics rollback adapter and lag compensation. Prefers the native engine class
## CgamePhysicsRollback (which also steps natively inside CgameRollbackNetcode) and falls back to
## scripts/shared/physics_rollback.gd. Use create() instead of new().
##
## Create the netcode with the rollback_netcode facade so adapter and netcode are both native or both
## script; setup_net() works in either case. rewind_query() and step_state() have identical signatures.

const _FALLBACK_SCRIPT = preload("res://scripts/shared/physics_rollback.gd")
const NATIVE_CLASS: String = "CgamePhysicsRollback"

static var _native: int = -1 # -1 unknown, 0 no, 1 yes


static func is_native() -> bool:
	if _native < 0:
		_native = 1 if ClassDB.class_exists(NATIVE_CLASS) else 0
	return _native == 1


static func create() -> RefCounted:
	if is_native():
		return ClassDB.instantiate(NATIVE_CLASS)
	return _FALLBACK_SCRIPT.new()
