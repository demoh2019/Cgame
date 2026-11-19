extends RefCounted
## A small bounded server-only PvE hate list (MMORPG tank/aggro rules).
## Players cannot send threat values over RPC; only confirmed zombie damage
## records threat. Entries are temporary and never persisted to characters.

const MAX_TARGETS := 5
const MAX_VALUE := 10000.0
const DECAY_PER_SECOND := 0.75
const SWITCH_MARGIN := 1.25


static func record(entries: Dictionary, peer_id: int, damage: float) -> bool:
	if peer_id <= 0 or not is_finite(damage) or damage <= 0.0:
		return false
	var earned: float = minf(MAX_VALUE, damage)
	if not entries.has(peer_id) and entries.size() >= MAX_TARGETS:
		var smallest_id: int = -1
		var smallest: float = INF
		for id in entries:
			var amount: float = float(entries[id])
			if amount < smallest:
				smallest = amount
				smallest_id = int(id)
		# A low-value incidental hit cannot evict an established participant.
		if smallest_id == -1 or earned <= smallest:
			return false
		entries.erase(smallest_id)
	entries[peer_id] = minf(MAX_VALUE, float(entries.get(peer_id, 0.0)) + earned)
	return true


static func decay(entries: Dictionary, delta: float) -> void:
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
		if value > best_threat:
			best_target = int(id)
			best_threat = value
	if current_threat > 0.0 and best_target != current_target and best_threat < current_threat * SWITCH_MARGIN:
		return current_target
	return best_target
