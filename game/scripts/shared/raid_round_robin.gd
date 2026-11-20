extends RefCounted
## Optional fair-share raid loot on ONE server-owned boss bag.
## The same bag's inventory is reduced on every accepted claim; no duplication.
## Identity tokens and turns are never accepted from clients.

const RaidLoot = preload("res://scripts/shared/raid_loot.gd")
const TURN_SECONDS := 12.0
const MAX_PARTICIPANTS := 5


static func activate(bag: Dictionary, identities: Array, boss_id: int, now: float) -> bool:
	if not is_finite(now) or now < 0.0 or boss_id <= 0 or identities.is_empty() \
			or identities.size() > MAX_PARTICIPANTS or bag.get("items", {}).is_empty() \
			or not bag.has("raid_reserved_until"):
		return false
	var ordered: Array[String] = []
	for token in identities:
		if not token is String or str(token).is_empty() or ordered.has(str(token)):
			return false
		ordered.append(str(token))
	bag["raid_round_robin"] = {
		"order": ordered,
		"index": posmod(boss_id, ordered.size()),
		"until": now + TURN_SECONDS,
		"original": (bag["items"] as Dictionary).duplicate(true)
	}
	return true


static func active(bag: Dictionary, now: float) -> bool:
	return bag.has("raid_round_robin") and RaidLoot.remaining(bag, now) > 0.0


## No state mutation when merely checking a turn (e.g. for snapshots).
static func turn(bag: Dictionary, player, now: float) -> Dictionary:
	if not active(bag, now):
		return {"ok": true, "active": false}
	var rule: Dictionary = bag["raid_round_robin"]
	var order: Array = rule["order"]
	if order.is_empty() or not is_finite(now):
		return {"ok": false, "reason": "invalid_state"}
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
static func offer(bag: Dictionary, player, now: float) -> Dictionary:
	var status: Dictionary = turn(bag, player, now)
	if not bool(status["ok"]):
		return {"ok": false, "reason": status.get("reason", "not_your_turn"),
			"remaining": float(status.get("seconds", 0.0))}
	if not bool(status.get("active", false)):
		return {"ok": false, "reason": "not_active"}
	var rule: Dictionary = bag["raid_round_robin"]
	var count: int = (rule["order"] as Array).size()
	var contents: Dictionary = bag.get("items", {})
	var ids: Array = contents.keys()
	ids.sort()
	for item_id in ids:
		var available: int = int(contents[item_id])
		if available <= 0:
			continue
		var original: int = maxi(1, int((rule["original"] as Dictionary).get(item_id, available)))
		var share: int = maxi(1, ceili(float(original) / float(count)))
		return {"ok": true, "item": str(item_id),
			"quantity": mini(available, share), "index": int(status["index"])}
	return {"ok": false, "reason": "empty"}


## Called only after inventory.add actually accepts positive items.
static func complete(bag: Dictionary, current_index: int, now: float) -> void:
	if not active(bag, now):
		return
	var rule: Dictionary = bag["raid_round_robin"]
	var count: int = (rule["order"] as Array).size()
	if count <= 0:
		return
	rule["index"] = posmod(current_index + 1, count)
	rule["until"] = now + TURN_SECONDS


static func visible(bag: Dictionary, player, now: float) -> Dictionary:
	var info: Dictionary = turn(bag, player, now)
	if not bool(info.get("active", false)):
		return {"active": false}
	return {"active": true, "your_turn": bool(info["ok"]),
		"seconds": float(info.get("seconds", 0.0))}
