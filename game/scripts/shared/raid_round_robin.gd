extends RefCounted
## Optional fair-share raid loot on ONE server-owned boss bag.
## The same bag's inventory is reduced on every accepted claim; no duplication.
## Identity tokens and turns are never accepted from clients.

const RaidLoot = preload("res://scripts/shared/raid_loot.gd")
const TURN_SECONDS := 12.0
const MAX_PARTICIPANTS := 5


static func activate(bag: Dictionary, identities: Array, boss_id: int, now: float) -> bool:
	var items: Variant = bag.get("items", null)
	var raw_lock: Variant = bag.get("raid_reserved_until", null)
	if not is_finite(now) or now < 0.0 or boss_id <= 0 or identities.is_empty() \
			or identities.size() > MAX_PARTICIPANTS or not (items is Dictionary) \
			or (items as Dictionary).is_empty() or not (raw_lock is int or raw_lock is float) \
			or not is_finite(float(raw_lock)) or float(raw_lock) <= now \
			or bag.has("raid_round_robin"):
		return false
	var ordered: Array[String] = []
	for identity in identities:
		if not (identity is String) or str(identity).is_empty() or ordered.has(str(identity)):
			return false
		ordered.append(str(identity))
	bag["raid_round_robin"] = {
		"order": ordered,
		"index": posmod(boss_id, ordered.size()),
		"until": minf(now + TURN_SECONDS, float(raw_lock)),
		"original": (items as Dictionary).duplicate(true)
	}
	return true


static func active(bag: Dictionary, now: float) -> bool:
	return bag.has("raid_round_robin") and RaidLoot.remaining(bag, now) > 0.0


static func _validated_rule(bag: Dictionary) -> Dictionary:
	var raw: Variant = bag.get("raid_round_robin", null)
	if not (raw is Dictionary):
		return {}
	var rule: Dictionary = raw
	var order_raw: Variant = rule.get("order", null)
	var index_raw: Variant = rule.get("index", null)
	var until_raw: Variant = rule.get("until", null)
	var original_raw: Variant = rule.get("original", null)
	var items_raw: Variant = bag.get("items", null)
	if not (order_raw is Array) or not (index_raw is int) or \
			not (until_raw is int or until_raw is float) or \
			not is_finite(float(until_raw)) or not (original_raw is Dictionary) or \
			not (items_raw is Dictionary):
		return {}
	var order: Array = order_raw
	if order.is_empty() or order.size() > MAX_PARTICIPANTS or \
			int(index_raw) < 0 or int(index_raw) >= order.size():
		return {}
	var seen: Dictionary = {}
	for identity in order:
		if not (identity is String) or str(identity).is_empty() or seen.has(identity):
			return {}
		seen[identity] = true
	var original: Dictionary = original_raw
	var contents: Dictionary = items_raw
	for item_id in original:
		var amount: Variant = original[item_id]
		if not (item_id is String) or not (amount is int or amount is float) or \
				not is_finite(float(amount)) or float(amount) < 0.0 or \
				float(amount) > 1000000000.0 or float(amount) != floor(float(amount)):
			return {}
	for item_id in contents:
		var amount: Variant = contents[item_id]
		if not (item_id is String) or not (amount is int or amount is float) or \
				not is_finite(float(amount)) or float(amount) < 0.0 or \
				float(amount) > 1000000000.0 or float(amount) != floor(float(amount)):
			return {}
	return rule


## No state mutation when merely checking a turn (e.g. for snapshots).
static func turn(bag: Dictionary, player, now: float) -> Dictionary:
	if not active(bag, now):
		return {"ok": true, "active": false}
	var rule: Dictionary = _validated_rule(bag)
	if rule.is_empty() or player == null or not is_finite(now) or now < 0.0:
		return {"ok": false, "reason": "invalid_state"}
	var order: Array = rule["order"]
	var owner: String = RaidLoot.token(player)
	if not order.has(owner):
		return {"ok": false, "reason": "raid_reserved"}
	var deadline: float = float(rule["until"])
	var skips: int = 0
	if now >= deadline:
		skips = maxi(0, int(floor((now - deadline) / TURN_SECONDS)) + 1)
	var current: int = posmod(int(rule["index"]) + skips, order.size())
	var remaining: float = maxf(0.0, deadline + float(skips) * TURN_SECONDS - now)
	return {"ok": str(order[current]) == owner, "active": true,
		"index": current, "seconds": remaining, "reason": "not_your_turn"}


## One claim gets one item type and at most 1/N of its ORIGINAL count.
## This prevents a first-click grab of an entire currency stack.
## Empty choice preserves Q auto-loot; explicit choices are validated against
## the original server-owned bag before any inventory transfer.
static func offer(bag: Dictionary, player, now: float, requested_item: String = "") -> Dictionary:
	var status: Dictionary = turn(bag, player, now)
	if not bool(status.get("active", false)) or not bool(status.get("ok", false)):
		return {"ok": false, "reason": status.get("reason", "not_active"),
			"remaining": float(status.get("seconds", 0.0))}
	var rule: Dictionary = _validated_rule(bag)
	if rule.is_empty():
		return {"ok": false, "reason": "invalid_state"}
	var count: int = (rule["order"] as Array).size()
	var contents: Dictionary = bag["items"]
	var original: Dictionary = rule["original"]
	var ids: Array = contents.keys()
	ids.sort()
	if not requested_item.is_empty():
		if not contents.has(requested_item) or not (contents[requested_item] is int or contents[requested_item] is float) or \
				float(contents[requested_item]) <= 0.0 or not original.has(requested_item):
			return {"ok": false, "reason": "item_unavailable"}
		ids = [requested_item]
	for item_id in ids:
		var raw_available: Variant = contents[item_id]
		if not (raw_available is int or raw_available is float) or \
				not is_finite(float(raw_available)) or float(raw_available) <= 0.0:
			continue
		var raw_original: Variant = original.get(item_id, raw_available)
		if not (raw_original is int or raw_original is float) or \
				not is_finite(float(raw_original)) or float(raw_original) <= 0.0:
			return {"ok": false, "reason": "invalid_state"}
		var available: int = int(raw_available)
		var share: int = maxi(1, ceili(float(raw_original) / float(count)))
		return {"ok": true, "item": str(item_id),
			"quantity": mini(available, share), "index": int(status["index"])}
	return {"ok": false, "reason": "empty"}


## Called only after inventory.add actually accepts positive items.
## Only material item IDs, not identities or private loot rotation metadata,
## may be sent to a contributor whose turn is active.
static func choice_ids(bag: Dictionary) -> Array[String]:
	var result: Array[String] = []
	var contents_raw: Variant = bag.get("items", null)
	if not (contents_raw is Dictionary):
		return result
	var contents: Dictionary = contents_raw
	for item_id in contents:
		var amount: Variant = contents[item_id]
		if (amount is int or amount is float) and is_finite(float(amount)) and \
				float(amount) > 0.0:
			result.append(str(item_id))
	result.sort()
	return result


static func complete(bag: Dictionary, current_index: int, now: float) -> void:
	if not active(bag, now) or not is_finite(now) or now < 0.0:
		return
	var rule: Dictionary = _validated_rule(bag)
	if rule.is_empty():
		return
	var count: int = (rule["order"] as Array).size()
	if current_index < 0 or current_index >= count:
		return
	var lock_remaining: float = RaidLoot.remaining(bag, now)
	rule["index"] = posmod(current_index + 1, count)
	rule["until"] = minf(now + TURN_SECONDS, now + lock_remaining)


## The actual turn holder may yield without claiming anything. This does not
## mutate the bag inventory and cannot be requested for another identity.
static func skip_turn(bag: Dictionary, player, now: float) -> Dictionary:
	var status: Dictionary = turn(bag, player, now)
	if not bool(status.get("active", false)):
		return {"ok": false, "reason": "not_active"}
	if not bool(status.get("ok", false)):
		return {"ok": false, "reason": str(status.get("reason", "not_your_turn"))}
	var rule: Dictionary = bag["raid_round_robin"]
	if (rule["order"] as Array).size() < 2 or (bag.get("items", {}) as Dictionary).is_empty():
		return {"ok": false, "reason": "empty"}
	complete(bag, int(status["index"]), now)
	return {"ok": true}


static func visible(bag: Dictionary, player, now: float) -> Dictionary:
	var info: Dictionary = turn(bag, player, now)
	if not bool(info.get("active", false)):
		return {"active": false}
	return {"active": true, "your_turn": bool(info["ok"]),
		"seconds": float(info.get("seconds", 0.0))}
