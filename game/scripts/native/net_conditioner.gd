extends RefCounted
## Facade for the network condition simulator. Prefers the native engine class CgameNetConditioner and
## falls back to scripts/shared/net_conditioner.gd. Use create() instead of new().
## The API is identical (configure, send, receive, packet, timeline, stats, delay_cause). The native RNG
## differs from RandomNumberGenerator, so a seed yields a different but equally deterministic stream.

const _FALLBACK_SCRIPT = preload("res://scripts/shared/net_conditioner.gd")
const NATIVE_CLASS: String = "CgameNetConditioner"

static var _native: int = -1 # -1 unknown, 0 no, 1 yes


static func is_native() -> bool:
	if _native < 0:
		_native = 1 if ClassDB.class_exists(NATIVE_CLASS) else 0
	return _native == 1


static func create() -> RefCounted:
	if is_native():
		return ClassDB.instantiate(NATIVE_CLASS)
	return _FALLBACK_SCRIPT.new()
