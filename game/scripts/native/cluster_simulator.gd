extends RefCounted
## Facade for CgameClusterSimulator: uses the native engine class (modules/cgame_server) when the running
## engine has it and falls back to res://scripts/server/cluster_simulator.gd otherwise. Both
## implementations share the same API and semantics, so callers never need to care which one they got.
##
## Usage: preload this file and call create() instead of Script.new():
##   const ClusterSimulatorFacade = preload("res://scripts/native/cluster_simulator.gd")
##   var obj = ClusterSimulatorFacade.create()

const NATIVE_CLASS := "CgameClusterSimulator"
const FALLBACK_SCRIPT = preload("res://scripts/server/cluster_simulator.gd")


## True when the native C++ implementation is available in this engine build.
static func is_native() -> bool:
	return ClassDB.class_exists(NATIVE_CLASS)


## Creates a new instance, native when possible.
static func create() -> Variant:
	if is_native():
		var obj: Variant = ClassDB.instantiate(NATIVE_CLASS)
		return obj
	return FALLBACK_SCRIPT.new()
