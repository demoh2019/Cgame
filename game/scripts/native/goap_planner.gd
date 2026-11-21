extends RefCounted
## Facade for the GOAP planner: uses the native CgameGOAPPlanner engine class when
## it is available and falls back to res://scripts/shared/goap_planner.gd otherwise.
## Same API as the GDScript planner (static plan()).

const Fallback = preload("res://scripts/shared/goap_planner.gd")
const NATIVE_CLASS := &"CgameGOAPPlanner"

static var _native: RefCounted = null


static func is_native() -> bool:
	return ClassDB.class_exists(NATIVE_CLASS)


static func plan(actions: Array, state: Dictionary, goal: Dictionary, max_nodes: int = 2048) -> Array[String]:
	if not is_native():
		return Fallback.plan(actions, state, goal, max_nodes)
	if _native == null:
		_native = ClassDB.instantiate(NATIVE_CLASS)
	var out: Array[String] = []
	out.assign(_native.plan(actions, state, goal, max_nodes))
	return out
