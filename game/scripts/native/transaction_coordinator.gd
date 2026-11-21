extends RefCounted
## Facade for CgameTransactionCoordinator: uses the native engine class (modules/cgame_server) when the running
## engine has it and falls back to res://scripts/server/transaction_coordinator.gd otherwise. Both
## implementations share the same API and semantics, so callers never need to care which one they got.
##
## Usage: preload this file and call create() instead of Script.new():
##   const TxCoordinatorFacade = preload("res://scripts/native/transaction_coordinator.gd")
##   var obj = TxCoordinatorFacade.create()

const NATIVE_CLASS := "CgameTransactionCoordinator"
const FALLBACK_SCRIPT = preload("res://scripts/server/transaction_coordinator.gd")


## True when the native C++ implementation is available in this engine build.
static func is_native() -> bool:
	return ClassDB.class_exists(NATIVE_CLASS)


## Creates a new instance, native when possible.
static func create() -> Variant:
	if is_native():
		var obj: Variant = ClassDB.instantiate(NATIVE_CLASS)
		return obj
	return FALLBACK_SCRIPT.new()
