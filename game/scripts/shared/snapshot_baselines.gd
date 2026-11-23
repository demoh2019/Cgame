extends RefCounted
## Per-client baseline tracker (Quake 3 netchan / Source delta snapshots / UE Iris):
## deltas are built against the last state the client acknowledged, so a lost packet
## only means the next delta is larger, never a desync.

const SnapshotDelta = preload("res://scripts/shared/snapshot_delta.gd")
const MAX_UNACKED := 32

# client_id -> {"acked_seq": int, "acked_state": Dictionary, "pending": {seq: state}, "order": Array[int]}
var _clients: Dictionary = {}


func _slot(client_id: int) -> Dictionary:
	if not _clients.has(client_id):
		var order: Array[int] = []
		_clients[client_id] = {"acked_seq": -1, "acked_state": {}, "pending": {}, "order": order}
	return _clients[client_id]


func record_sent(client_id: int, sequence: int, state: Dictionary) -> void:
	var slot: Dictionary = _slot(client_id)
	var pending: Dictionary = slot["pending"]
	# Late/replayed sends cannot re-enter the pending window after an ACK.
	# One sequence always names one immutable snapshot, even on retries.
	if sequence <= int(slot["acked_seq"]) or pending.has(sequence):
		return
	var order: Array[int] = slot["order"]
	order.append(sequence)
	pending[sequence] = state.duplicate(true)
	while order.size() > MAX_UNACKED:
		var oldest: int = order.pop_front()
		pending.erase(oldest)


func acknowledge(client_id: int, sequence: int) -> void:
	if not _clients.has(client_id):
		return
	var slot: Dictionary = _clients[client_id]
	var pending: Dictionary = slot["pending"]
	if not pending.has(sequence) or sequence <= int(slot["acked_seq"]):
		return
	slot["acked_seq"] = sequence
	slot["acked_state"] = pending[sequence]
	var order: Array[int] = slot["order"]
	var keep: Array[int] = []
	for s in order:
		if s > sequence:
			keep.append(s)
		else:
			pending.erase(s)
	slot["order"] = keep


func baseline_for(client_id: int) -> Dictionary:
	if not _clients.has(client_id):
		return {}
	var slot: Dictionary = _clients[client_id]
	var state: Dictionary = slot["acked_state"]
	# Never leak the stored acknowledged state to callers: an accidental HUD
	# or debug mutation would corrupt every later delta for this client.
	return state.duplicate(true)


func build_packet(client_id: int, sequence: int, state: Dictionary, tolerances: Dictionary = {}) -> Dictionary:
	var slot: Dictionary = _slot(client_id)
	# The server can read its private baseline directly without cloning the
	# entire entity set on every snapshot tick.
	var baseline: Dictionary = slot["acked_state"]
	var delta: Dictionary = SnapshotDelta.diff(baseline, state, tolerances)
	var packet: Dictionary = {"sequence": sequence, "baseline": int(slot["acked_seq"]), "delta": delta}
	record_sent(client_id, sequence, state)
	return packet


func forget(client_id: int) -> void:
	_clients.erase(client_id)
