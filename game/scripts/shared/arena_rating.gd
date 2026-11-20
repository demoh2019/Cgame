extends RefCounted
## Optional ranked PvP sparring built on existing no-loot, consent-only hub duels.
## Only the server resolves knockouts/forfeits and changes persisted rating.
const START_RATING := 1200
const MIN_RATING := 600
const MAX_RATING := 2400
const MAX_RECORD := 100000
const K_FACTOR := 32
const REMATCH_SECONDS := 1200.0
const MAX_PAIRS := 2048


static func valid_rating(value: Variant) -> bool:
	return value is int and value >= MIN_RATING and value <= MAX_RATING


static func valid_record(value: Variant) -> bool:
	return value is int and value >= 0 and value <= MAX_RECORD


static func tier(value: int) -> String:
	if value >= 1900:
		return "Diamond"
	if value >= 1600:
		return "Platinum"
	if value >= 1300:
		return "Gold"
	if value >= 1100:
		return "Silver"
	return "Bronze"


static func pair_key(first, second) -> String:
	if first == null or second == null or first.user_id.is_empty() or second.user_id.is_empty():
		return ""
	if first.user_id == second.user_id:
		return ""
	var ids: Array[String] = [first.user_id, second.user_id]
	ids.sort()
	return JSON.stringify(ids)


## Nakama-authenticated accounts only: guest / peer IDs can be recycled.
static func eligibility(first, second, now: float, history: Dictionary) -> String:
	if not is_finite(now):
		return "invalid_time"
	var key: String = pair_key(first, second)
	if key == "":
		return "account_required"
	if now < float(history.get(key, -INF)) + REMATCH_SECONDS:
		return "ranked_rematch_cooldown"
	return ""


static func settle(winner, loser, now: float, history: Dictionary) -> Dictionary:
	var error: String = eligibility(winner, loser, now, history)
	if error != "":
		return {"ok": false, "reason": error}
	if not valid_rating(winner.arena_rating) or not valid_rating(loser.arena_rating):
		return {"ok": false, "reason": "invalid_rating"}
	if winner.arena_wins >= MAX_RECORD or loser.arena_losses >= MAX_RECORD:
		return {"ok": false, "reason": "record_cap"}
	var key: String = pair_key(winner, loser)
	# Standard deterministic two-player Elo (K=32), with hard rating limits.
	var winner_expect: float = 1.0 / (1.0 + pow(10.0,
		float(loser.arena_rating - winner.arena_rating) / 400.0))
	var change: int = clampi(roundi(float(K_FACTOR) * (1.0 - winner_expect)), 1, K_FACTOR)
	winner.arena_rating = mini(MAX_RATING, winner.arena_rating + change)
	loser.arena_rating = maxi(MIN_RATING, loser.arena_rating - change)
	winner.arena_wins += 1
	loser.arena_losses += 1
	winner.dirty_character = true
	loser.dirty_character = true
	# Bound server session memory; do not trust an RPC to write this history.
	if history.size() >= MAX_PAIRS:
		var oldest: String = ""
		var when: float = INF
		for other_key in history:
			if float(history[other_key]) < when:
				when = float(history[other_key])
				oldest = str(other_key)
		if oldest != "":
			history.erase(oldest)
	history[key] = now
	return {"ok": true, "change": change,
		"winner_rating": winner.arena_rating, "loser_rating": loser.arena_rating}
