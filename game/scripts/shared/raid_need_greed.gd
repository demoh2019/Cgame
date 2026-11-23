extends RefCounted
## Optional Need / Greed / Pass for the infected core of ONE raid boss bag.
## This script never creates items: winners only gain permission to claim the
## original trophy stack in the normal server inventory transaction.

const RaidLoot = preload("res://scripts/shared/raid_loot.gd")
const ITEM_ID := "infected_core"
const VOTE_SECONDS := 25.0
const MAX_VOTERS := 5
const CHOICES := ["need", "greed", "pass"]


## Freeze tokens at death. Existing bag loot and existing reservations remain.
static func activate(bag: Dictionary, identities: Array, boss_id: int, now: float) -> bool:
	if boss_id <= 0 or not is_finite(now) or now < 0.0 or \
			identities.size() < 2 or identities.size() > MAX_VOTERS or \
			int(bag.get("items", {}).get(ITEM_ID, 0)) <= 0 or \
			not bag.has("raid_reserved_until") or bag.has("raid_need_greed"):
		return false
	# An invalid or already-expired raid reservation must never open an
	# election with a negative, infinite, or unbounded voting deadline.
	var raw_lock: Variant = bag.get("raid_reserved_until", null)
	if not (raw_lock is int or raw_lock is float):
		return false
	var lock_until: float = float(raw_lock)
	if not is_finite(lock_until) or lock_until <= now:
		return false
	var tokens: Array[String] = []
	for identity in identities:
		if not identity is String or str(identity).is_empty() or tokens.has(str(identity)):
			return false
		tokens.append(str(identity))
	bag["raid_need_greed"] = {
		"item": ITEM_ID,
		"amount": int(bag["items"][ITEM_ID]),
		"eligible": tokens,
		"votes": {},
		"until": minf(now + VOTE_SECONDS, lock_until),
		"status": "voting",
		"winner": "",
		"roll": 0,
		"seed": boss_id
	}
	return true


## Deterministic roll: replays, snapshots and concurrent requests cannot
## reroll the winner. NEED beats GREED; PASS is not a candidate.
static func _finish(state: Dictionary, now: float) -> void:
	if str(state.get("status", "")) != "voting":
		return
	var eligible: Array = state["eligible"]
	var votes: Dictionary = state["votes"]
	if now < float(state["until"]) and votes.size() < eligible.size():
		return
	var top_priority: int = 0
	var top_roll: int = -1
	var winner: String = ""
	for token in eligible:
		var choice: String = str(votes.get(token, "pass"))
		var priority: int = 2 if choice == "need" else (1 if choice == "greed" else 0)
		if priority == 0:
			continue
		var roll: int = ((int(str(token).hash()) ^ int(state["seed"])) & 0x7fffffff) % 100 + 1
		if priority > top_priority or (priority == top_priority and \
				(roll > top_roll or (roll == top_roll and (winner.is_empty() or str(token) < winner)))):
			top_priority = priority
			top_roll = roll
			winner = str(token)
	state["winner"] = winner
	state["roll"] = maxi(0, top_roll)
	state["status"] = "awarded" if not winner.is_empty() else "free"


## Lazy, idempotent resolution lets voting finish without a new server ticker.
static func resolve(bag: Dictionary, now: float) -> Dictionary:
	var state: Dictionary = bag.get("raid_need_greed", {})
	if state.is_empty() or not is_finite(now):
		return {}
	_finish(state, now)
	return state


## A remote client sends only a choice and a bag ID. The server supplies
## the real authenticated Player, time, bag and frozen entitlement list.
static func vote(bag: Dictionary, player, choice: String, now: float) -> Dictionary:
	if player == null:
		return {"ok": false, "reason": "not_eligible"}
	if not CHOICES.has(choice):
		return {"ok": false, "reason": "invalid_choice"}
	if RaidLoot.remaining(bag, now) <= 0.0:
		return {"ok": false, "reason": "vote_closed"}
	var state: Dictionary = resolve(bag, now)
	if state.is_empty() or str(state.get("status", "")) != "voting":
		return {"ok": false, "reason": "vote_closed"}
	var token: String = RaidLoot.token(player)
	if not (state["eligible"] as Array).has(token):
		return {"ok": false, "reason": "not_eligible"}
	var votes: Dictionary = state["votes"]
	if votes.has(token):
		return {"ok": false, "reason": "already_voted"}
	votes[token] = choice
	_finish(state, now)
	return {"ok": true, "choice": choice,
		"resolved": str(state["status"]) != "voting"}


## Protect the original trophy only until the existing raid lock expires.
## Other items in the same physical bag can be looted normally.
static func protection(bag: Dictionary, player, now: float) -> Dictionary:
	if player == null:
		return {"locked": true, "reason": "not_eligible"}
	if RaidLoot.remaining(bag, now) <= 0.0 or \
			int(bag.get("items", {}).get(ITEM_ID, 0)) <= 0:
		return {"locked": false}
	var state: Dictionary = resolve(bag, now)
	if state.is_empty() or str(state.get("status", "")) == "free":
		return {"locked": false}
	if str(state["status"]) == "voting":
		return {"locked": true, "reason": "raid_vote_pending",
			"remaining": maxf(0.0, float(state["until"]) - now)}
	if str(state["status"]) == "awarded" and \
			str(state["winner"]) != RaidLoot.token(player):
		return {"locked": true, "reason": "raid_winner_reserved",
			"remaining": RaidLoot.remaining(bag, now)}
	return {"locked": false}


## Only viewer-specific vote status: no account/session tokens, rolls of
## opponents, or private ballots are serialized to the network.
static func visible(bag: Dictionary, player, now: float) -> Dictionary:
	if player == null or RaidLoot.remaining(bag, now) <= 0.0:
		return {}
	var state: Dictionary = resolve(bag, now)
	if state.is_empty():
		return {}
	var token: String = RaidLoot.token(player)
	if not (state["eligible"] as Array).has(token):
		return {}
	var status: String = str(state["status"])
	return {
		"item": ITEM_ID,
		"amount": int(state["amount"]),
		"status": status,
		"your_vote": str((state["votes"] as Dictionary).get(token, "")),
		"votes_cast": (state["votes"] as Dictionary).size(),
		"participants": (state["eligible"] as Array).size(),
		"remaining": maxf(0.0, float(state["until"]) - now) if status == "voting" else 0.0,
		"your_win": status == "awarded" and str(state["winner"]) == token,
		"your_roll": int(state["roll"]) if status == "awarded" and str(state["winner"]) == token else 0
	}
