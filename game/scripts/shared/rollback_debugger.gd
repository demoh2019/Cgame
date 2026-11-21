extends RefCounted
## Debug view over a RollbackNetcode: records every rollback (from/to frame, resimulated
## frames, the player whose late input caused it), per-player prediction miss rate, desync
## frames with a state diff, and a text report.
##
## Drive the netcode THROUGH this wrapper (add_remote_input / advance / process) so inputs
## can be classified; the netcode itself is not modified. Original GDScript, no third-party code.

var net: RefCounted
var rollbacks: Array = []  # [{from_frame, to_frame, frames_resimulated, cause}]
var desyncs: Array = []    # [{frame, local_checksum, remote_checksum, local_state, diff}]
var late_inputs: Dictionary = {}   # pid -> remote inputs that arrived for an already simulated frame
var mispredictions: Dictionary = {} # pid -> of those, how many differed from the prediction used

var _cause_by_frame: Dictionary = {} # frame -> pid that first required rollback to it
var _last_advanced: bool = false
var _history: Dictionary = {} # frame -> state recorded at advance time (bounded)
const HISTORY_LIMIT: int = 128


func _init(p_net: RefCounted = null) -> void:
	if p_net != null:
		attach(p_net)


func attach(p_net: RefCounted) -> void:
	net = p_net
	net.desync_detected.connect(_on_desync)


func add_remote_input(pid: Variant, f: int, input: Dictionary) -> void:
	var used: Dictionary = net._used.get(pid, {})
	var stored: Dictionary = net._inputs.get(pid, {})
	var fresh: bool = not stored.has(f) and f >= int(net._floor.get(pid, 0))
	var was_used: bool = fresh and f < net.frame and used.has(f)
	var missed: bool = was_used and (used[f] as Dictionary).hash() != input.hash()
	var pending_before: int = net._pending_rollback
	net.add_remote_input(pid, f, input)
	if was_used:
		late_inputs[pid] = int(late_inputs.get(pid, 0)) + 1
		if missed:
			mispredictions[pid] = int(mispredictions.get(pid, 0)) + 1
	var pending_after: int = net._pending_rollback
	if pending_after >= 0 and pending_after != pending_before:
		_cause_by_frame[pending_after] = pid


func add_local_input(pid: Variant, input: Dictionary) -> int:
	return net.add_local_input(pid, input)


func advance() -> bool:
	_before_and_run(false)
	return _last_advanced




func process() -> void:
	_before_and_run(true)


func _before_and_run(only_process: bool) -> void:
	var rb: int = net.rollbacks
	var resim: int = net.resimulated_frames
	var pending: int = net._pending_rollback
	var frame_before: int = net.frame
	if only_process:
		net.process()
	else:
		_last_advanced = net.advance()
		_history[net.frame] = net.state.duplicate(true)
		_history.erase(net.frame - HISTORY_LIMIT)
	if net.rollbacks > rb:
		var cause: Variant = _cause_by_frame.get(pending, -1)
		rollbacks.append({"from_frame": pending if pending >= 0 else frame_before,
			"to_frame": frame_before, "frames_resimulated": net.resimulated_frames - resim,
			"cause": cause})
		_cause_by_frame.erase(pending)


## Miss rate for a player: mispredicted / late inputs (0.0 when none arrived late).
func miss_rate(pid: Variant) -> float:
	var late: int = int(late_inputs.get(pid, 0))
	if late == 0:
		return 0.0
	return float(int(mispredictions.get(pid, 0))) / float(late)


## Provide the remote peer's state for a desync frame to compute the key-path diff.
func attach_remote_state(frame: int, remote_state: Dictionary) -> Array:
	for d in desyncs:
		var e: Dictionary = d
		if int(e["frame"]) == frame:
			var diff: Array = diff_states(e["local_state"], remote_state)
			e["diff"] = diff
			return diff
	return []


func _on_desync(frame: int, local_checksum: int, remote_checksum: int) -> void:
	var snap: Dictionary = net._snapshots.get(frame, _history.get(frame, {}))
	desyncs.append({"frame": frame, "local_checksum": local_checksum,
		"remote_checksum": remote_checksum, "local_state": snap.duplicate(true), "diff": []})


## Key paths (e.g. "players.1.x", "items[2]") at which a and b differ, sorted.
static func diff_states(a: Variant, b: Variant, path: String = "") -> Array:
	var out: Array = []
	_diff(a, b, path, out)
	out.sort()
	return out


static func _diff(a: Variant, b: Variant, path: String, out: Array) -> void:
	if a is Dictionary and b is Dictionary:
		var da: Dictionary = a
		var db: Dictionary = b
		var keys: Dictionary = {}
		for k in da:
			keys[k] = true
		for k in db:
			keys[k] = true
		for k in keys:
			var p: String = str(k) if path == "" else path + "." + str(k)
			if not da.has(k) or not db.has(k):
				out.append(p)
			else:
				_diff(da[k], db[k], p, out)
	elif a is Array and b is Array:
		var aa: Array = a
		var ab: Array = b
		for i in range(maxi(aa.size(), ab.size())):
			var p: String = "%s[%d]" % [path, i]
			if i >= aa.size() or i >= ab.size():
				out.append(p)
			else:
				_diff(aa[i], ab[i], p, out)
	elif typeof(a) != typeof(b) or a != b:
		out.append(path)


func report() -> String:
	var lines: Array[String] = []
	lines.append("frame=%d confirmed=%d rollbacks=%d resimulated=%d stalls=%d" % [
		net.frame, net.confirmed_frame, net.rollbacks, net.resimulated_frames, net.stall_count])
	for r in rollbacks:
		var d: Dictionary = r
		lines.append("  rollback %d -> %d (%d frames) cause=%s" % [
			int(d["from_frame"]), int(d["to_frame"]), int(d["frames_resimulated"]), str(d["cause"])])
	var pids: Array = late_inputs.keys()
	pids.sort()
	for pid in pids:
		lines.append("  player %s: %d late inputs, %d mispredicted (miss rate %.0f%%)" % [
			str(pid), int(late_inputs[pid]), int(mispredictions.get(pid, 0)), miss_rate(pid) * 100.0])
	if desyncs.is_empty():
		lines.append("no desyncs")
	for ds in desyncs:
		var e: Dictionary = ds
		lines.append("  DESYNC frame %d local=%d remote=%d diff=%s" % [
			int(e["frame"]), int(e["local_checksum"]), int(e["remote_checksum"]), str(e["diff"])])
	return "\n".join(lines)


## State recorded when `frame` was reached (may be mispredicted if a rollback followed), or {}.
func state_history(frame: int) -> Dictionary:
	return (_history.get(frame, {}) as Dictionary).duplicate(true)
