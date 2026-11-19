extends RefCounted
## Deterministic, clock-driven network impairment simulator for local tests.
##
## This does NOT change Godot's actual UDP/ENet transport. Schedule packet
## envelopes with a caller-supplied time in milliseconds, then poll_due().
## Simulates latency, jitter, packet loss and packet reordering at the queue
## level. The caller decides whether/how to forward due envelopes to peers.

const MAX_QUEUE: int = 8192
const MAX_DELAY_MS: int = 60000
const MAX_SAFE_TIME_MS: int = 9223372036854775807 - MAX_DELAY_MS * 2

var _latency_ms: int = 0
var _jitter_ms: int = 0
var _loss_rate: float = 0.0
var _seed: int = 1
var _next_sequence: int = 0
var _pending: Array[Dictionary] = []
var _dropped: int = 0
var _delivered: int = 0


func configure(latency_ms: int, jitter_ms: int, loss_rate: float, seed: int = 1) -> bool:
	if latency_ms < 0 or latency_ms > MAX_DELAY_MS:
		return false
	if jitter_ms < 0 or jitter_ms > MAX_DELAY_MS:
		return false
	if not is_finite(loss_rate) or loss_rate < 0 or loss_rate > 1:
		return false
	_latency_ms = latency_ms
	_jitter_ms = jitter_ms
	_loss_rate = loss_rate
	_seed = seed
	reset()
	return true


func reset() -> void:
	_pending.clear()
	_next_sequence = 0
	_dropped = 0
	_delivered = 0


func get_pending_count() -> int:
	return _pending.size()


func get_dropped_count() -> int:
	return _dropped


func get_delivered_count() -> int:
	return _delivered


func schedule(payload: Dictionary, now_ms: int) -> Dictionary:
	if now_ms < 0 or now_ms > MAX_SAFE_TIME_MS:
		return {"ok": false, "status": "invalid_time"}
	if _pending.size() >= MAX_QUEUE:
		return {"ok": false, "status": "queue_full"}
	if not _valid_value(payload):
		return {"ok": false, "status": "invalid_payload"}

	var sequence := _next_sequence
	_next_sequence += 1

	if _random01(sequence, 1) < _loss_rate:
		_dropped += 1
		return {"ok": true, "status": "dropped", "sequence": sequence}

	var jitter_offset := roundi((_random01(sequence, 2) * 2.0 - 1.0) * _jitter_ms)
	var delay := maxi(0, _latency_ms + jitter_offset)
	var due_ms := now_ms + delay
	_pending.append({
		"sequence": sequence,
		"due_ms": due_ms,
		"payload": payload.duplicate(true),
	})
	return {"ok": true, "status": "scheduled", "sequence": sequence, "due_ms": due_ms}


func poll_due(now_ms: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if now_ms < 0:
		return result

	var still_pending: Array[Dictionary] = []
	for envelope: Dictionary in _pending:
		if envelope["due_ms"] <= now_ms:
			result.append(envelope.duplicate(true))
		else:
			still_pending.append(envelope)
	_pending = still_pending

	# Stable ordering: due time, then original sequence number. Differing
	# jitter may reorder packets even if they were scheduled in order.
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["due_ms"] == b["due_ms"]:
			return a["sequence"] < b["sequence"]
		return a["due_ms"] < b["due_ms"]
	)
	_delivered += result.size()
	return result


func _random01(sequence: int, channel: int) -> float:
	# 31-bit LCG with explicitly masked intermediate state. No calls to
	# global randf(): the same seed and sequence give identical outcomes.
	var value: int = (_seed ^ (sequence * 1103515245 + channel * 12345)) & 0x7fffffff
	value = (value * 1103515245 + 12345) & 0x7fffffff
	return float(value) / 2147483648.0


func _valid_value(value: Variant, depth: int = 0) -> bool:
	if depth > 8:
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
		TYPE_DICTIONARY:
			if value.size() > 4096:
				return false
			for key in value:
				if not _valid_value(key, depth + 1) or not _valid_value(value[key], depth + 1):
					return false
			return true
		TYPE_ARRAY:
			if value.size() > 4096:
				return false
			for item in value:
				if not _valid_value(item, depth + 1):
					return false
			return true
		_:
			return false
