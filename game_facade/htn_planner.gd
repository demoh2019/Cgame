extends RefCounted
## Facade for the HTN planner: uses the native CgameHTNPlanner engine class when
## it is available and falls back to res://scripts/shared/htn_planner.gd otherwise.
## Same API as the GDScript planner (static plan()).

const Fallback = preload("res://scripts/shared/htn_planner.gd")
const NATIVE_CLASS := &"CgameHTNPlanner"

static var _native: RefCounted = null


static func is_native() -> bool:
	return ClassDB.class_exists(NATIVE_CLASS)


static func plan(domain: Dictionary, root_task: String, state: Dictionary, max_steps: int = 256) -> Array[String]:
	if not is_native():
		return Fallback.plan(domain, root_task, state, max_steps)
	if _native == null:
		_native = ClassDB.instantiate(NATIVE_CLASS)
	var out: Array[String] = []
	out.assign(_native.plan(domain, root_task, state, max_steps))
	return out
