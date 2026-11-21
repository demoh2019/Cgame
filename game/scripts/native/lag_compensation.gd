extends RefCounted
## Facade for CgameLagCompensation: uses the native engine class (modules/cgame_server) when the running
## engine has it and falls back to res://scripts/server/lag_compensation.gd otherwise. Both
## implementations share the same API and semantics, so callers never need to care which one they got.
##
## Usage: preload this file and call create() instead of Script.new():
##   const LagCompensationFacade = preload("res://scripts/native/lag_compensation.gd")
##   var obj = LagCompensationFacade.create()

const NATIVE_CLASS := "CgameLagCompensation"
const FALLBACK_SCRIPT = preload("res://scripts/server/lag_compensation.gd")


## True when the native C++ implementation is available in this engine build.
static func is_native() -> bool:
	return ClassDB.class_exists(NATIVE_CLASS)


## Creates a new instance, native when possible.
static func create() -> Variant:
	if is_native():
		var obj: Variant = ClassDB.instantiate(NATIVE_CLASS)
		return obj
	return FALLBACK_SCRIPT.new()

const HISTORY_SECONDS := 0.5
const MAX_REWIND := 0.25
const CLIENT_INTERPOLATION := 0.12 # network_jitter_buffer.gd BASE_DELAY.


## How far back to judge an attacker with this round-trip time (seconds).
static func rewind_for(round_trip: float) -> float:
	if is_native():
		return (ClassDB.instantiate(NATIVE_CLASS) as Object).call("rewind_for", round_trip)
	return FALLBACK_SCRIPT.rewind_for(round_trip)
