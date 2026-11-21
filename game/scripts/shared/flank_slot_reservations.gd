extends RefCounted
## Portable, server-owned SmartObjectSlotReservations fallback for stock Godot.
## No wall clock, RNG, client RPCs or positional state; ticked by GameServer.
const MAX_ACTIVE_CLAIMS := 2048
const MAX_CANDIDATES := 16
const MAX_LEASE_SECONDS := 5.0
var _claims: Dictionary = {} # Positive slot ID -> {actor:int, remaining:float}.
var _actor_slots: Dictionary = {} # Positive actor ID -> one currently owned slot.


func try_claim_first(slot_ids: PackedInt64Array, actor_id: int, lease_seconds: float) -> int:
	if actor_id <= 0 or slot_ids.is_empty() or slot_ids.size() > MAX_CANDIDATES \
			or not is_finite(lease_seconds) or lease_seconds <= 0.0 or lease_seconds > MAX_LEASE_SECONDS:
		return 0
	# Validate ALL slot IDs before touching the existing reservation.
	var seen: Dictionary = {}
	for slot_id in slot_ids:
		if slot_id <= 0 or seen.has(slot_id):
			return 0
		seen[slot_id] = true
	var owned: int = int(_actor_slots.get(actor_id, 0))
	if owned != 0 and seen.has(owned):
		var active: Dictionary = _claims[owned]
		active["remaining"] = lease_seconds
		return owned
	for slot_id in slot_ids:
		if _claims.has(slot_id):
			continue
		if owned != 0:
			_claims.erase(owned)
		elif _claims.size() >= MAX_ACTIVE_CLAIMS:
			return 0
		_claims[slot_id] = {"actor": actor_id, "remaining": lease_seconds}
		_actor_slots[actor_id] = slot_id
		return slot_id
	return 0


func release_slot(slot_id: int, actor_id: int) -> bool:
	if slot_id <= 0 or actor_id <= 0 or get_owner(slot_id) != actor_id:
		return false
	_claims.erase(slot_id)
	_actor_slots.erase(actor_id)
	return true


func release_actor(actor_id: int) -> int:
	if actor_id <= 0 or not _actor_slots.has(actor_id):
		return 0
	var slot_id: int = int(_actor_slots[actor_id])
	_claims.erase(slot_id)
	_actor_slots.erase(actor_id)
	return 1


func advance_time(delta: float) -> void:
	if not is_finite(delta) or delta <= 0.0:
		return
	for slot_id in _claims.keys():
		var claim: Dictionary = _claims[slot_id]
		if float(claim["remaining"]) <= delta:
			_actor_slots.erase(int(claim["actor"]))
			_claims.erase(slot_id)
		else:
			claim["remaining"] = float(claim["remaining"]) - delta


func clear() -> void:
	_claims.clear()
	_actor_slots.clear()


func get_owner(slot_id: int) -> int:
	return int(_claims[slot_id]["actor"]) if _claims.has(slot_id) else 0


func get_claim_count() -> int:
	return _claims.size()
