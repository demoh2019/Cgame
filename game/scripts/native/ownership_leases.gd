extends RefCounted
## Facade for CgameOwnershipLeases: uses the native engine class (modules/cgame_server) when the running
## engine has it and falls back to res://scripts/server/ownership_leases.gd otherwise. Both
## implementations share the same API and semantics, so callers never need to care which one they got.
##
## Usage: preload this file and call create() instead of Script.new():
##   const OwnershipLeasesFacade = preload("res://scripts/native/ownership_leases.gd")
##   var obj = OwnershipLeasesFacade.create()

const NATIVE_CLASS := "CgameOwnershipLeases"
const FALLBACK_SCRIPT = preload("res://scripts/server/ownership_leases.gd")


## True when the native C++ implementation is available in this engine build.
static func is_native() -> bool:
	return ClassDB.class_exists(NATIVE_CLASS)


## Creates a new instance, native when possible.
static func create() -> Variant:
	if is_native():
		var obj: Variant = ClassDB.instantiate(NATIVE_CLASS)
		return obj
	return FALLBACK_SCRIPT.new()


## Creates the protected resource that rejects writes with stale fencing tokens.
static func create_fenced_store() -> Variant:
	if ClassDB.class_exists("CgameFencedStore"):
		return ClassDB.instantiate("CgameFencedStore")
	return FALLBACK_SCRIPT.FencedStore.new()


## Holder-side check with a drift allowance: stop acting `drift` before the server-side expiry.
static func client_valid(expires: float, now: float, drift: float) -> bool:
	return now < expires - drift
