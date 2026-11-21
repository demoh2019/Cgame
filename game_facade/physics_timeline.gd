extends RefCounted
## Facade for the physics timeline profiler. Prefers the native engine class CgamePhysicsTimeline and falls
## back to scripts/shared/physics_timeline.gd. Use create() instead of new(), and attach() to hook it into a
## world created by the deterministic_physics facade.

const _FALLBACK_SCRIPT = preload("res://scripts/shared/physics_timeline.gd")
const NATIVE_CLASS: String = "CgamePhysicsTimeline"
const PHASES: Array[String] = ["broadphase", "narrowphase", "solve", "integrate"]

static var _native: int = -1 # -1 unknown, 0 no, 1 yes


static func is_native() -> bool:
	if _native < 0:
		_native = 1 if ClassDB.class_exists(NATIVE_CLASS) else 0
	return _native == 1


static func create() -> RefCounted:
	if is_native():
		return ClassDB.instantiate(NATIVE_CLASS)
	return _FALLBACK_SCRIPT.new()


## Attaches `timeline` to `world` (native worlds use set_timeline(), script worlds the timeline variable).
static func attach(world: RefCounted, timeline: RefCounted) -> void:
	if world.has_method("set_timeline"):
		world.call("set_timeline", timeline)
	else:
		world.set("timeline", timeline)
