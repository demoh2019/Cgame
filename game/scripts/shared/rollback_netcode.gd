extends RefCounted
## Rollback netcode core (GGPO-style): input ring buffers, local prediction, confirmed-frame
## tracking, rollback + resimulation, bounded snapshot ring, per-frame checksums with desync
## detection, input delay and a max prediction window (stalls when exceeded).
##
## Design source: Tony Cannon's GGPO write-ups / the public rollback-netcode literature and
## Glenn Fiedler's "Deterministic Lockstep" article (ideas only). No third-party code was
## copied; this is an independent reimplementation (no license obligations, no Apache-2.0
## notice needed).
##
## Contract: step is a pure deterministic Callable(state: Dictionary, inputs: Dictionary,
## dt: float) -> Dictionary. `inputs` maps player_id -> input (Dictionary) in sorted player
## order. The step receives a deep copy and may mutate it and return it.
##
## Frame semantics: snapshot[f] is the state at the START of frame f (before f's inputs).
## advance() simulates the current frame f -> f+1. A frame is "confirmed" once real inputs of
## every player are known for it and all earlier frames.
##
## Transport glue (caller): send drain_outgoing() entries to peers, feed received entries to
## add_remote_input(), optionally exchange get_checksum_report() and feed add_remote_checksum().

signal desync_detected(frame: int, local_checksum: int, remote_checksum: int)

const MAX_FINAL_CHECKSUMS: int = 256
const MAX_SCAN_BACK: int = 512

var step: Callable
var dt: float = 1.0 / 60.0
var input_delay: int = 0
var max_prediction: int = 8
var snapshot_capacity: int = 16

var frame: int = 0
var confirmed_frame: int = -1
var state: Dictionary = {}

var players: Array = []
var local_players: Array = []

var rollbacks: int = 0
var resimulated_frames: int = 0
var stall_count: int = 0
var desync_frames: Array[int] = []

var _snapshots: Dictionary = {}       # frame -> state Dictionary
var _final_checksums: Dictionary = {} # frame -> int (checksums of pruned final frames)
var _inputs: Dictionary = {}          # pid -> {frame -> input}
var _used: Dictionary = {}            # pid -> {frame -> input actually simulated}
var _contiguous: Dictionary = {}      # pid -> highest frame with real inputs for all frames <= it
var _floor: Dictionary = {}           # pid -> first frame still stored
var _base: Dictionary = {}            # pid -> last pruned real input (prediction fallback)
var _local_next: Dictionary = {}      # pid -> next frame a local input is scheduled for
var _outgoing: Array = []
var _pending_rollback: int = -1
var _remote_checksums: Dictionary = {} # frame -> int
var _report_next: int = 0


func setup(p_step: Callable, p_initial_state: Dictionary, p_players: Array, p_local_players: Array,
		p_dt: float = 1.0 / 60.0, p_input_delay: int = 0, p_max_prediction: int = 8, p_snapshot_capacity: int = 0) -> void:
	step = p_step
	dt = p_dt
	input_delay = maxi(0, p_input_delay)
	max_prediction = maxi(0, p_max_prediction)
	snapshot_capacity = maxi(p_snapshot_capacity, max_prediction + 3)
	players = p_players.duplicate()
	players.sort()
	local_players = p_local_players.duplicate()
	state = p_initial_state.duplicate(true)
	frame = 0
	confirmed_frame = -1
	rollbacks = 0
	resimulated_frames = 0
	stall_count = 0
	desync_frames.clear()
	_snapshots.clear()
	_final_checksums.clear()
	_inputs.clear()
	_used.clear()
	_contiguous.clear()
	_floor.clear()
	_base.clear()
	_local_next.clear()
	_outgoing.clear()
	_remote_checksums.clear()
	_pending_rollback = -1
	_report_next = 0
	for pid in players:
		_inputs[pid] = {}
		_used[pid] = {}
		_contiguous[pid] = -1
		_floor[pid] = 0
		_base[pid] = {}
	_snapshots[0] = state.duplicate(true)
	# Delay prefill: the first `input_delay` frames carry empty inputs for local players.
	for pid in local_players:
		for f in range(input_delay):
			_store_input(pid, f, {}, true)
		_local_next[pid] = input_delay
	_recompute_confirmed()


static func state_checksum(s: Dictionary) -> int:
	return hash(var_to_bytes(s))


## Schedules `input` for frame (current local frame + input_delay). Returns that frame.
func add_local_input(pid: Variant, input: Dictionary) -> int:
	var f: int = _local_next[pid]
	_local_next[pid] = f + 1
	_store_input(pid, f, input.duplicate(true), true)
	_recompute_confirmed()
	return f


## Feeds a remote player's real input for `f`. Duplicates and stale frames are ignored.
func add_remote_input(pid: Variant, f: int, input: Dictionary) -> void:
	if not _inputs.has(pid) or f < int(_floor[pid]):
		return
	if (_inputs[pid] as Dictionary).has(f):
		return
	_store_input(pid, f, input.duplicate(true), false)
	_recompute_confirmed()


## Entries {player, frame, input} for local inputs not yet drained (includes delay prefill).
func drain_outgoing() -> Array:
	var out: Array = _outgoing
	_outgoing = []
	return out


func add_remote_checksum(f: int, checksum: int) -> void:
	_remote_checksums[f] = checksum
	process()
	_verify_checksums()


## New {frame, checksum} reports for frames that became final since the last call.
func get_checksum_report() -> Array:
	process() # reports must come from corrected, not mispredicted, snapshots
	var out: Array = []
	while _report_next <= confirmed_frame + 1 and _report_next <= frame:
		var cs: int = checksum_of(_report_next)
		if cs == 0 and not _snapshots.has(_report_next) and not _final_checksums.has(_report_next):
			break
		out.append({"frame": _report_next, "checksum": cs})
		_report_next += 1
	return out


## Applies a pending rollback (if any), then simulates one frame. False when stalled.
func advance() -> bool:
	process()
	if is_stalled():
		stall_count += 1
		return false
	_simulate_one(false)
	_prune()
	_verify_checksums()
	return true


## Resolves a pending rollback caused by late/corrected inputs.
func process() -> void:
	if _pending_rollback >= 0:
		var target: int = _pending_rollback
		_pending_rollback = -1
		rollback_to(target)
		_prune()
		_verify_checksums()


func is_stalled() -> bool:
	return frame - (confirmed_frame + 1) >= max_prediction


## Restores the snapshot at `f` and resimulates up to the current frame. False if `f` is
## outside the snapshot ring or in the future.
func rollback_to(f: int) -> bool:
	if f > frame or not _snapshots.has(f):
		return false
	if f == frame:
		return true
	var target: int = frame
	state = (_snapshots[f] as Dictionary).duplicate(true)
	frame = f
	rollbacks += 1
	resimulated_frames += target - f
	while frame < target:
		_simulate_one(true)
	return true


func snapshot_count() -> int:
	return _snapshots.size()


func get_state() -> Dictionary:
	return state


## Checksum of the state at the start of `f` (current or final), or 0 if unknown.
func checksum_of(f: int) -> int:
	if _snapshots.has(f):
		return state_checksum(_snapshots[f])
	if _final_checksums.has(f):
		return _final_checksums[f]
	return 0


func has_desync() -> bool:
	return not desync_frames.is_empty()


## Input that was/will be used for (pid, f): real if known, else predicted (repeat last).
func input_for(pid: Variant, f: int) -> Dictionary:
	var stored: Dictionary = _inputs[pid]
	if stored.has(f):
		return stored[f]
	var lo: int = maxi(int(_floor[pid]), f - MAX_SCAN_BACK)
	var g: int = f - 1
	while g >= lo:
		if stored.has(g):
			return stored[g]
		g -= 1
	return _base[pid]


func has_real_input(pid: Variant, f: int) -> bool:
	return (_inputs[pid] as Dictionary).has(f)


func _store_input(pid: Variant, f: int, input: Dictionary, is_local: bool) -> void:
	(_inputs[pid] as Dictionary)[f] = input
	if is_local:
		_outgoing.append({"player": pid, "frame": f, "input": input})
	# Late real input for an already simulated frame: rollback if the prediction was wrong.
	if f < frame and (_used[pid] as Dictionary).has(f):
		if (_used[pid][f] as Dictionary).hash() != input.hash():
			if _pending_rollback < 0 or f < _pending_rollback:
				_pending_rollback = f
	var c: int = _contiguous[pid]
	while (_inputs[pid] as Dictionary).has(c + 1):
		c += 1
	_contiguous[pid] = c


func _recompute_confirmed() -> void:
	var m: int = 1 << 40
	for pid in players:
		m = mini(m, int(_contiguous[pid]))
	confirmed_frame = m


func _simulate_one(_resim: bool) -> void:
	var inputs: Dictionary = {}
	for pid in players:
		var inp: Dictionary = input_for(pid, frame)
		inputs[pid] = inp
		(_used[pid] as Dictionary)[frame] = inp
	state = step.call(state.duplicate(true), inputs, dt)
	frame += 1
	_snapshots[frame] = state.duplicate(true)


func _prune() -> void:
	# Snapshots older than the oldest frame that can still need rollback are dropped.
	var keep_from: int = mini(confirmed_frame + 1, frame)
	var keys: Array = _snapshots.keys()
	keys.sort()
	for f in keys:
		if f < keep_from or _snapshots.size() > snapshot_capacity:
			_retire_snapshot(f)
	var in_floor: int = mini(confirmed_frame, frame) - 1
	for pid in players:
		var stored: Dictionary = _inputs[pid]
		var used: Dictionary = _used[pid]
		var fl: int = _floor[pid]
		while fl < in_floor:
			if stored.has(fl):
				_base[pid] = stored[fl]
			stored.erase(fl)
			used.erase(fl)
			fl += 1
		_floor[pid] = fl


func _retire_snapshot(f: int) -> void:
	if f <= confirmed_frame + 1:
		_final_checksums[f] = state_checksum(_snapshots[f])
		while _final_checksums.size() > MAX_FINAL_CHECKSUMS:
			var oldest: int = 1 << 40
			for k in _final_checksums:
				oldest = mini(oldest, int(k))
			_final_checksums.erase(oldest)
	_snapshots.erase(f)


func _verify_checksums() -> void:
	if _pending_rollback >= 0:
		return # snapshots may still hold mispredicted states
	var done: Array = []
	for f in _remote_checksums:
		if f > confirmed_frame + 1 or f > frame:
			continue
		if not _snapshots.has(f) and not _final_checksums.has(f):
			if f < frame - snapshot_capacity - MAX_FINAL_CHECKSUMS:
				done.append(f)
			continue
		var local: int = checksum_of(f)
		var remote: int = _remote_checksums[f]
		if local != remote:
			desync_frames.append(f)
			desync_detected.emit(f, local, remote)
		done.append(f)
	for f in done:
		_remote_checksums.erase(f)
