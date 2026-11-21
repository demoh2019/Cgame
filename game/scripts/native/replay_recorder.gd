extends RefCounted
## Facade for CgameReplayRecorder: uses the native engine class (modules/cgame_server) when the running
## engine has it and falls back to res://scripts/server/replay_recorder.gd otherwise. Both
## implementations share the same API and semantics, so callers never need to care which one they got.
##
## Usage: preload this file and call create() instead of Script.new():
##   const ReplayRecorderFacade = preload("res://scripts/native/replay_recorder.gd")
##   var obj = ReplayRecorderFacade.create(seed, world_seed)

const NATIVE_CLASS := "CgameReplayRecorder"
const FALLBACK_SCRIPT = preload("res://scripts/server/replay_recorder.gd")


## True when the native C++ implementation is available in this engine build.
static func is_native() -> bool:
	return ClassDB.class_exists(NATIVE_CLASS)


## Creates a new instance, native when possible.
static func create(seed_value: int = 0, world_seed: int = 0) -> Variant:
	if is_native():
		var obj: Variant = ClassDB.instantiate(NATIVE_CLASS)
		obj.seed_value = seed_value
		obj.world_seed = world_seed
		return obj
	return FALLBACK_SCRIPT.new(seed_value, world_seed)

const FORMAT_VERSION := 1

## Re-runs a replay on make_server.call(seed, world_seed) -> GameServer.
## Returns {"hashes": Array, "rejected": Array[String], "ok": bool}.
static func play(replay: Dictionary, make_server: Callable) -> Dictionary:
	if is_native():
		return (ClassDB.instantiate(NATIVE_CLASS) as Object).call("play", replay, make_server, Callable(FALLBACK_SCRIPT, "state_hash"))
	return FALLBACK_SCRIPT.play(replay, make_server)


## Returns the replay Dictionary, or {} when missing / malformed. (The native method is called "load".)
static func load_replay(path: String) -> Dictionary:
	if is_native():
		return (ClassDB.instantiate(NATIVE_CLASS) as Object).call("load", path)
	return FALLBACK_SCRIPT.load(path)


## Only cmd_* and submit_input may be recorded or replayed.
static func is_allowed_method(method: String) -> bool:
	if is_native():
		return (ClassDB.instantiate(NATIVE_CLASS) as Object).call("is_allowed_method", method)
	return FALLBACK_SCRIPT.is_allowed_method(method)


## First tick at which two hash lists differ (a length mismatch counts), else -1.
static func compare(a_hashes: Array, b_hashes: Array) -> int:
	if is_native():
		return (ClassDB.instantiate(NATIVE_CLASS) as Object).call("compare", a_hashes, b_hashes)
	return FALLBACK_SCRIPT.compare(a_hashes, b_hashes)
