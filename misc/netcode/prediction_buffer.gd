extends RefCounted
## Reusable deterministic input history for server-authoritative games.
##
## The caller supplies a *pure, deterministic* simulation function:
##   simulate(state: Dictionary, input: Dictionary, tick: int) -> Dictionary
##
## This class intentionally does not send RPCs, run physics or guess network
## ownership. Transport, authentication and authority remain game responsibilities.
##
## States/inputs must only contain serializable value data (no Objects, RIDs,
## Callables or Signals). Nested structures are limited to depth 8.

const MAX_SNAPSHOT_DEPTH: int = 8
const MAX_COLLECTION_ELEMENTS: int = 4096
const MIN_HISTORY: int = 2
const MAX_HISTORY: int = 2048

var _initialized: bool = false
var _simulator: Callable = Callable()
var _comparator: Callable = Callable()
var _states: Dictionary = {}
var _commands: Dictionary = {}
var _latest_tick: int = -1
var _earliest_tick: int = -1
var _history_limit: int = 128


func configure_history(limit: int) -> bool:
	if limit < MIN_HISTORY or limit > MAX_HISTORY:
		return false
	_history_limit = limit
	_trim_history()
	return true


func get_history_limit() -> int:
	return _history_limit


func initialize(initial_tick: int, initial_state: Dictionary, simulator: Callable,
		comparator: Callable = Callable()) -> bool:
	if initial_tick < 0 or not simulator.is_valid():
		return false
	if not _is_safe_value(initial_state):
		return false
	_simulator = simulator
	_comparator = comparator
	_states.clear()
	_commands.clear()
	_latest_tick = initial_tick
	_earliest_tick = initial_tick
	_states[initial_tick] = _copy(initial_state)
	_initialized = true
	return true


func reset() -> void:
	_initialized = false
	_simulator = Callable()
	_comparator = Callable()
	_states.clear()
	_commands.clear()
	_latest_tick = -1
	_earliest_tick = -1


func is_initialized() -> bool:
	return _initialized


func get_current_tick() -> int:
	return _latest_tick


func get_earliest_tick() -> int:
	return _earliest_tick


func get_current_state() -> Dictionary:
	if not _initialized:
		return {}
	return _copy(_states[_latest_tick])


func get_state_at(tick: int) -> Dictionary:
	if not _states.has(tick):
		return {}
	return _copy(_states[tick])


func get_buffered_command(tick: int) -> Dictionary:
	if not _commands.has(tick):
		return {}
	return _copy(_commands[tick])


func predict(tick: int, command: Dictionary) -> Dictionary:
	if not _initialized:
		return _result(false, "uninitialized")
	if tick != _latest_tick + 1:
		return _result(false, "out_of_order")
	if not _is_safe_value(command):
		return _result(false, "invalid_command")

	# Always pass copies: gameplay simulation may mutate its arguments.
	var next_state: Variant = _simulator.call(
			_copy(_states[_latest_tick]), _copy(command), tick)
	if not (next_state is Dictionary) or not _is_safe_value(next_state):
		return _result(false, "invalid_simulation_result")

	_commands[tick] = _copy(command)
	_states[tick] = _copy(next_state)
	_latest_tick = tick
	_trim_history()
	return _result(true, "predicted")


func reconcile(tick: int, authoritative_state: Dictionary) -> Dictionary:
	if not _initialized:
		return _result(false, "uninitialized")
	if tick > _latest_tick:
		return _result(false, "future_tick")
	if tick < _earliest_tick:
		# A delayed snapshot outside the retained history cannot be replayed.
		# The game should request a full resynchronization when appropriate.
		return _result(false, "stale_tick")
	if not _states.has(tick):
		return _result(false, "missing_state")
	if not _is_safe_value(authoritative_state):
		return _result(false, "invalid_authoritative_state")

	var matched: Variant
	if _comparator.is_valid():
		matched = _comparator.call(_copy(_states[tick]), _copy(authoritative_state))
		if not (matched is bool):
			return _result(false, "invalid_comparator_result")
	else:
		matched = _states[tick] == authoritative_state

	if matched:
		return _result(true, "matched")

	# Replay is transactional. If a simulator fails during replay, the full
	# original prediction history is retained without partial corrections.
	var replacements: Dictionary = {}
	var corrected: Dictionary = _copy(authoritative_state)
	replacements[tick] = _copy(corrected)
	for step in range(tick + 1, _latest_tick + 1):
		if not _commands.has(step):
			return _result(false, "missing_command")
		var candidate: Variant = _simulator.call(
				_copy(corrected), _copy(_commands[step]), step)
		if not (candidate is Dictionary) or not _is_safe_value(candidate):
			return _result(false, "invalid_simulation_result")
		corrected = _copy(candidate)
		replacements[step] = _copy(corrected)

	for step in replacements:
		_states[step] = replacements[step]
	return _result(true, "replayed", _latest_tick - tick)


func _trim_history() -> void:
	if not _initialized:
		return
	while _latest_tick - _earliest_tick > _history_limit:
		_states.erase(_earliest_tick)
		_commands.erase(_earliest_tick + 1)
		_earliest_tick += 1


func _copy(value: Dictionary) -> Dictionary:
	return value.duplicate(true)


func _result(success: bool, status: String, replayed_steps: int = 0) -> Dictionary:
	return {
		"ok": success,
		"status": status,
		"tick": _latest_tick,
		"replayed_steps": replayed_steps,
	}


func _is_safe_value(value: Variant, depth: int = 0) -> bool:
	if depth > MAX_SNAPSHOT_DEPTH:
		return false
	match typeof(value):
		TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_STRING, TYPE_STRING_NAME:
			return true
		TYPE_FLOAT:
			return is_finite(value)
		TYPE_VECTOR2:
			return is_finite(value.x) and is_finite(value.y)
		TYPE_VECTOR3:
			return is_finite(value.x) and is_finite(value.y) and is_finite(value.z)
		TYPE_VECTOR2I, TYPE_VECTOR3I:
			return true
		TYPE_COLOR:
			return is_finite(value.r) and is_finite(value.g) \
					and is_finite(value.b) and is_finite(value.a)
		TYPE_ARRAY:
			if value.size() > MAX_COLLECTION_ELEMENTS:
				return false
			for item in value:
				if not _is_safe_value(item, depth + 1):
					return false
			return true
		TYPE_DICTIONARY:
			if value.size() > MAX_COLLECTION_ELEMENTS:
				return false
			for key in value:
				if not _is_safe_value(key, depth + 1):
					return false
				if not _is_safe_value(value[key], depth + 1):
					return false
			return true
		_:
			# Reject object references, RIDs, callables, signals and obscure
			# variants instead of retaining unsafe mutable references.
			return false
