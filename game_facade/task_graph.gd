extends RefCounted
## Facade for CgameTaskGraph (native) with the GDScript TaskGraph as fallback.
##
## Same API as scripts/shared/task_graph.gd. Native execution keeps the wave semantics but
## schedules directly on the WorkerThreadPool without script-side bookkeeping, and feeds
## CgameTrace (task scopes + dependency flows) when tracing is enabled.

const FALLBACK_PATH := "res://scripts/shared/task_graph.gd"

enum State { PENDING, DONE, FAILED, CANCELLED }

var _impl: Object = null
var _native: bool = false


func _init() -> void:
	if ClassDB.class_exists("CgameTaskGraph"):
		_impl = ClassDB.instantiate("CgameTaskGraph")
		_native = true
	elif ResourceLoader.exists(FALLBACK_PATH):
		_impl = (load(FALLBACK_PATH) as GDScript).new()
	else:
		push_error("TaskGraph facade: neither CgameTaskGraph nor %s is available" % FALLBACK_PATH)


func is_native() -> bool:
	return _native


func add_task(task_name: String, callable: Callable, deps: PackedStringArray = PackedStringArray(), thread_safe: bool = true) -> String:
	return _impl.add_task(task_name, callable, deps, thread_safe) if _impl != null else ""


func add_dependency(task_name: String, dep: String) -> bool:
	return _impl != null and _impl.add_dependency(task_name, dep)


func has_task(task_name: String) -> bool:
	return _impl != null and _impl.has_task(task_name)


func task_count() -> int:
	return _impl.task_count() if _impl != null else 0


func clear() -> void:
	if _impl != null:
		_impl.clear()


func validate() -> PackedStringArray:
	return _impl.validate() if _impl != null else PackedStringArray()


func topological_order() -> PackedStringArray:
	return _impl.topological_order() if _impl != null else PackedStringArray()


## Returns {ok, order, failed, cancelled, waves, total_ms, error}.
func run() -> Dictionary:
	return _impl.run() if _impl != null else {"ok": false, "error": "no task graph backend"}


func result_of(task_name: String) -> Variant:
	return _impl.result_of(task_name) if _impl != null else null


func state_of(task_name: String) -> int:
	return _impl.state_of(task_name) if _impl != null else -1


func error_of(task_name: String) -> String:
	return _impl.error_of(task_name) if _impl != null else ""


func timing(task_name: String) -> Dictionary:
	return _impl.timing(task_name) if _impl != null else {}


func results() -> Dictionary:
	return _impl.results() if _impl != null else {}


## Longest dependency chain; always returned as a plain Array of task names.
func critical_path() -> Array:
	if _impl == null:
		return []
	return Array(_impl.critical_path())


func critical_path_ms() -> float:
	return _impl.critical_path_ms() if _impl != null else 0.0


func to_dot() -> String:
	return _impl.to_dot() if _impl != null else ""
