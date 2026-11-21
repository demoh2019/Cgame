extends RefCounted
## Portable, server-owned SmartObjectSlotReservations fallback for stock Godot.
## No wall clock, RNG, client RPCs or positional state; ticked by GameServer.
const MAX_ACTIVE_CLAIMS := 2048
const MAX_CANDIDATES := 16
const MAX_LEASE_SECONDS := 5.0
var _claims: Dictionary = {} # Slot -> {actor:int, remaining:float, priority:int, occupied:bool}.
var _actor_slots: Dictionary = {} # Positive actor ID -> one currently owned slot.


func try_claim_first(slot_ids: PackedInt64Array, actor_id: int, lease_seconds: float) -> int:
	return try_claim_first_priority(slot_ids, actor_id, lease_seconds, 0)


func try_claim_first_priority(slot_ids: PackedInt64Array, actor_id: int,
		lease_seconds: float, priority: int) -> int:
	if actor_id <= 0 or priority < 0 or priority > 3 or slot_ids.is_empty() \
			or slot_ids.size() > MAX_CANDIDATES or not is_finite(lease_seconds) \
			or lease_seconds <= 0.0 or lease_seconds > MAX_LEASE_SECONDS:
		return 0
	# Invalid input must never change a valid actor reservation.
	var seen: Dictionary = {}
	for slot_id in slot_ids:
		if slot_id <= 0 or seen.has(slot_id):
			return 0
		seen[slot_id] = true
	var owned: int = int(_actor_slots.get(actor_id, 0))
	if owned != 0 and seen.has(owned):
		var existing: Dictionary = _claims[owned]
		existing["remaining"] = lease_seconds
		existing["priority"] = priority
		return owned
	for slot_id in slot_ids:
		if _claims.has(slot_id):
			continue
		if owned != 0:
			_claims.erase(owned)
		elif _claims.size() >= MAX_ACTIVE_CLAIMS:
			return 0
		_claims[slot_id] = {"actor": actor_id, "remaining": lease_seconds,
			"priority": priority, "occupied": false}
		_actor_slots[actor_id] = slot_id
		return slot_id
	# Do not interrupt a character already using a slot.
	for slot_id in slot_ids:
		var old_claim: Dictionary = _claims[slot_id]
		if bool(old_claim.get("occupied", false)) or int(old_claim.get("priority", 0)) >= priority:
			continue
		_actor_slots.erase(int(old_claim["actor"]))
		if owned != 0:
			_claims.erase(owned)
		_claims[slot_id] = {"actor": actor_id, "remaining": lease_seconds,
			"priority": priority, "occupied": false}
		_actor_slots[actor_id] = slot_id
		return slot_id
	return 0


func set_slot_occupied(slot_id: int, actor_id: int, occupied: bool) -> bool:
	if slot_id <= 0 or actor_id <= 0 or get_owner(slot_id) != actor_id:
		return false
	_claims[slot_id]["occupied"] = occupied
	return true


func is_slot_occupied(slot_id: int) -> bool:
	return bool(_claims[slot_id].get("occupied", false)) if _claims.has(slot_id) else false

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


## O(1) owned-slot lookup, matching native SmartObjectSlotReservations.
## The zombie uses this to reject a cached flank goal after its lease expires.
func get_actor_slot(actor_id: int) -> int:
	return int(_actor_slots.get(actor_id, 0)) if actor_id > 0 else 0


func get_claim_count() -> int:
	return _claims.size()
