extends RefCounted
## Facade for the rollback debugger. Prefers the native engine class CgameRollbackDebugger and falls back
## to scripts/shared/rollback_debugger.gd. Use create(net) instead of new(net).
## `net` must come from the rollback_netcode facade so both are native or both are script.

const _FALLBACK_SCRIPT = preload("res://scripts/shared/rollback_debugger.gd")
const NATIVE_CLASS: String = "CgameRollbackDebugger"

static var _native: int = -1 # -1 unknown, 0 no, 1 yes


static func is_native() -> bool:
	if _native < 0:
		_native = 1 if ClassDB.class_exists(NATIVE_CLASS) else 0
	return _native == 1


static func create(net: RefCounted = null) -> RefCounted:
	if is_native() and (net == null or net.get_class() == "CgameRollbackNetcode"):
		var dbg: RefCounted = ClassDB.instantiate(NATIVE_CLASS)
		if net != null:
			dbg.attach(net)
		return dbg
	return _FALLBACK_SCRIPT.new(net)


static func diff_states(a: Variant, b: Variant, path: String = "") -> Array:
	return _FALLBACK_SCRIPT.diff_states(a, b, path)
