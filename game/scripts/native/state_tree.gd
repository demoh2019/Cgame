extends RefCounted
## Facade for the StateTree runtime: create() returns a native CgameStateTree when
## the engine module is available and a GDScript state_tree.gd instance otherwise.
## Both expose the same API (register_task/condition/evaluator/subtree, validate,
## set_asset, start, stop, send_event, tick, debug_path, current_state, is_active and
## the errors / tree_status / running / active_path / trace properties).
##
## Differences of the native class: `errors`, `validate()` and `trace` are
## PackedStringArray instead of Array[String]; the Status enum values are identical.
##
## Usage:  var st = StateTreeFacade.create()
##         if st.tick(dt, ctx) == StateTreeFacade.Status.SUCCEEDED: ...

const Fallback = preload("res://scripts/shared/state_tree.gd")
const NATIVE_CLASS := &"CgameStateTree"

## Values match both the GDScript and the native CgameStateTree.Status enum.
enum Status { RUNNING, SUCCEEDED, FAILED }


static func is_native() -> bool:
	return ClassDB.class_exists(NATIVE_CLASS)


static func create() -> RefCounted:
	if is_native():
		return ClassDB.instantiate(NATIVE_CLASS)
	return Fallback.new()
