extends RefCounted
## A small bounded server-only PvE hate list (MMORPG tank/aggro rules).
## Players cannot send threat values over RPC; only confirmed zombie damage
## records threat. Entries are temporary and never persisted to characters.

const MAX_TARGETS := 5
const MAX_VALUE := 10000.0
const DECAY_PER_SECOND := 0.75
const SWITCH_MARGIN := 1.25

# Shared stateless native threat arithmetic; server-owned dictionaries remain
# the source of truth for combat, healer aggro and all existing callers.
static var _native_checked: bool = false
static var _native: Object = null


static func has_native() -> bool:
	if not _native_checked:
		_native_checked = true
		if ClassDB.class_exists("AIThreatTable2D"):
			_native = ClassDB.instantiate("AIThreatTable2D")
	return _native != null


static func record(entries: Dictionary, peer_id: int, damage: float) -> bool:
	if has_native():
		return bool(_native.record(entries, peer_id, damage))
	if peer_id <= 0 or not is_finite(damage) or damage <= 0.0:
		return false
	var earned: float = minf(MAX_VALUE, damage)
	if not entries.has(peer_id) and entries.size() >= MAX_TARGETS:
		var smallest_id: int = -1
		var smallest: float = INF
		for id in entries:
			var amount: float = float(entries[id])
			if amount < smallest or (amount == smallest and (smallest_id == -1 or int(id) < smallest_id)):
				smallest = amount
				smallest_id = int(id)
		# A low-value incidental hit cannot evict an established participant.
		if smallest_id == -1 or earned <= smallest:
			return false
		entries.erase(smallest_id)
	entries[peer_id] = minf(MAX_VALUE, float(entries.get(peer_id, 0.0)) + earned)
	return true


## Reduce a single actor's existing server-authoritative threat.
## Never fabricates new aggro. The fallback works on ordinary Godot.
static func scale(entries: Dictionary, peer_id: int, factor: float) -> bool:
	if has_native():
		return bool(_native.scale(entries, peer_id, factor))
	if peer_id <= 0 or not is_finite(factor) or factor < 0.0 or factor > 1.0:
		return false
	if not entries.has(peer_id):
		return false
	var raw: Variant = entries[peer_id]
	if typeof(raw) != TYPE_FLOAT and typeof(raw) != TYPE_INT:
		entries.erase(peer_id)
		return false
	var value: float = float(raw)
	if not is_finite(value) or value <= 0.0:
		entries.erase(peer_id)
		return false
	var remaining: float = minf(MAX_VALUE, value * factor)
	if remaining <= 0.0:
		entries.erase(peer_id)
	else:
		entries[peer_id] = remaining
	return true


static func decay(entries: Dictionary, delta: float) -> void:
	if has_native():
		_native.decay(entries, delta)
		return
	if not is_finite(delta) or delta <= 0.0:
		return
	for id in entries.keys():
		var current: float = float(entries[id])
		if not is_finite(current):
			entries.erase(id)
			continue
		var remaining: float = current - DECAY_PER_SECOND * delta
		if remaining <= 0.0:
			entries.erase(id)
		else:
			entries[id] = remaining


static func pick(entries: Dictionary, players: Dictionary, origin: Vector2,
		leash: float, current_target: int = -1) -> int:
	if has_native():
		return int(_native.pick(entries, players, origin, leash, current_target))
	if not origin.is_finite() or not is_finite(leash) or leash <= 0.0:
		return -1
	var current_threat: float = 0.0
	var best_target: int = -1
	var best_threat: float = 0.0
	for id in entries.keys():
		var data: Variant = players.get(id, null)
		if not (data is Dictionary) or not bool(data.get("alive", false)) or bool(data.get("safe", true)):
			entries.erase(id)
			continue
		var at: Variant = data.get("position", Vector3.INF)
		if not (at is Vector3) or not at.is_finite():
			entries.erase(id)
			continue
		var distance: float = origin.distance_to(Vector2(at.x, at.z))
		if distance > leash:
			entries.erase(id)
			continue
		var value: float = float(entries[id])
		if not is_finite(value) or value <= 0.0:
			entries.erase(id)
			continue
		if id == current_target:
			current_threat = value
		if value > best_threat or (value == best_threat and (best_target == -1 or int(id) < best_target)):
			best_target = int(id)
			best_threat = value
	if current_threat > 0.0 and best_target != current_target and best_threat < current_threat * SWITCH_MARGIN:
		return current_target
	return best_target
