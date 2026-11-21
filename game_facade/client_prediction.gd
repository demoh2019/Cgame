extends RefCounted
## Facade for client-side movement prediction. Prefers the native engine class CgameClientPrediction and
## falls back to scripts/shared/client_prediction.gd. Use create() instead of new().
## The API is identical (setup, predict, reconcile, update, visual_state, offset_magnitude).

const _FALLBACK_SCRIPT = preload("res://scripts/shared/client_prediction.gd")
const NATIVE_CLASS: String = "CgameClientPrediction"

static var _native: int = -1 # -1 unknown, 0 no, 1 yes


static func is_native() -> bool:
	if _native < 0:
		_native = 1 if ClassDB.class_exists(NATIVE_CLASS) else 0
	return _native == 1


static func create() -> RefCounted:
	if is_native():
		return ClassDB.instantiate(NATIVE_CLASS)
	return _FALLBACK_SCRIPT.new()
