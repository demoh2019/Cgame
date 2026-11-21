@tool
extends RefCounted
## Facade for Utility AI: uses the native CgameUtilityAI engine class when it is
## available and falls back to res://scripts/shared/utility_ai.gd otherwise.
## Same API as the GDScript library (Response enum, curve, combine, best); also
## exposes the infected prey scoring as infected_target_score().

const Fallback = preload("res://scripts/shared/utility_ai.gd")
const InfectedFallback = preload("res://scripts/shared/infected_target_utility.gd")
const NATIVE_CLASS := &"CgameUtilityAI"

## Values match both the GDScript and the native CgameUtilityAI.Response enum.
enum Response { LINEAR, QUADRATIC, INVERSE_QUADRATIC, LOGISTIC, STEP }

static var _native: RefCounted = null


static func is_native() -> bool:
	return ClassDB.class_exists(NATIVE_CLASS)


static func _impl() -> RefCounted:
	if _native == null:
		_native = ClassDB.instantiate(NATIVE_CLASS)
	return _native


static func curve(kind: int, x: float, slope: float = 1.0, shift: float = 0.0) -> float:
	if is_native():
		return _impl().curve(kind, x, slope, shift)
	return Fallback.curve(kind, x, slope, shift)


## Product of considerations with IAUS compensation.
static func combine(scores: PackedFloat32Array) -> float:
	if is_native():
		return _impl().combine(scores)
	return Fallback.combine(scores)


## Index of the best scoring option (ties keep the earliest; -1 if all zero).
static func best(scores: PackedFloat32Array) -> int:
	if is_native():
		return _impl().best(scores)
	return Fallback.best(scores)


## Infected prey choice scored with Utility AI (see infected_target_utility.gd).
static func infected_target_score(distance: float, leash: float, health_fraction: float,
		is_current: bool, noisy: bool) -> float:
	if is_native():
		return _impl().infected_target_score(distance, leash, health_fraction, is_current, noisy)
	return InfectedFallback.score(distance, leash, health_fraction, is_current, noisy)
