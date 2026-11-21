extends RefCounted
## Server-authoritative movement prediction (Overwatch / Quake / Gabriel Gambetta style).
## The client applies inputs locally at once and keeps them with sequence numbers. When the
## server acknowledges `last_processed_seq` with its authoritative state, reconcile() drops the
## acknowledged inputs and replays the remaining ones on top of the server state. The jump
## between the old and the re-predicted position is not snapped but folded into a visual
## offset that decays exponentially; errors above `error_threshold` snap instantly.
##
## Design source: Gabriel Gambetta "Fast-Paced Multiplayer" and Valve/Overwatch GDC talks
## (ideas only). Independent implementation, no third-party code, no license obligations.
##
## apply: Callable(state: Dictionary, input: Dictionary, dt: float) -> Dictionary (deterministic,
## must match the server's movement code). `position_key` names the float/Vector2/Vector3
## entry in the state used for error measurement and smoothing.

var apply: Callable
var state: Dictionary = {}
var position_key: String = "pos"
var error_threshold: float = 2.0
var smoothing_rate: float = 10.0 ## visual offset decays as exp(-rate * dt)
var max_pending: int = 256

var next_seq: int = 1
var last_acked_seq: int = 0
var last_error: float = 0.0
var snaps: int = 0
var visual_offset: Variant = 0.0

var _pending: Array = [] # {seq, input, dt}


func setup(p_apply: Callable, initial_state: Dictionary, p_position_key: String = "pos",
		p_error_threshold: float = 2.0, p_smoothing_rate: float = 10.0) -> void:
	apply = p_apply
	state = initial_state.duplicate(true)
	position_key = p_position_key
	error_threshold = p_error_threshold
	smoothing_rate = p_smoothing_rate
	next_seq = 1
	last_acked_seq = 0
	_pending.clear()
	snaps = 0
	last_error = 0.0
	visual_offset = _zero_like(state.get(position_key, 0.0))


## Applies `input` locally and queues it. Returns its sequence number (send it to the server).
func predict(input: Dictionary, dt: float) -> int:
	var seq: int = next_seq
	next_seq += 1
	state = apply.call(state.duplicate(true), input, dt)
	_pending.append({"seq": seq, "input": input.duplicate(true), "dt": dt})
	if _pending.size() > max_pending:
		_pending.pop_front()
	return seq


func pending_count() -> int:
	return _pending.size()


## Server ack. Returns the position error (magnitude) between the old prediction and the
## server-corrected re-prediction. Stale acks (older than the last one) are ignored.
func reconcile(server_state: Dictionary, last_processed_seq: int) -> float:
	if last_processed_seq < last_acked_seq:
		return 0.0
	last_acked_seq = last_processed_seq
	var old_pos: Variant = state.get(position_key, 0.0)
	while not _pending.is_empty() and int((_pending[0] as Dictionary)["seq"]) <= last_processed_seq:
		_pending.pop_front()
	var s: Dictionary = server_state.duplicate(true)
	for entry in _pending:
		var e: Dictionary = entry
		s = apply.call(s, e["input"], float(e["dt"]))
	state = s
	var new_pos: Variant = state.get(position_key, 0.0)
	var diff: Variant = old_pos - new_pos
	var err: float = _mag(diff)
	last_error = err
	if err > error_threshold:
		visual_offset = _zero_like(new_pos)
		snaps += 1
	else:
		visual_offset = visual_offset + diff
	return err


## Decays the visual correction offset (call once per rendered frame).
func update(delta: float) -> void:
	visual_offset = visual_offset * exp(-smoothing_rate * delta)


func offset_magnitude() -> float:
	return _mag(visual_offset)


## Predicted state with the smoothed correction offset applied to the position entry.
func visual_state() -> Dictionary:
	var v: Dictionary = state.duplicate(true)
	if v.has(position_key):
		v[position_key] = v[position_key] + visual_offset
	return v


static func _mag(v: Variant) -> float:
	if v is float or v is int:
		return absf(float(v))
	return float(v.length())


static func _zero_like(v: Variant) -> Variant:
	if v is int:
		return 0.0
	return v * 0.0
