extends RefCounted
## One-server, opt-in ranked duel matchmaking using real Nakama account IDs.
## A queued survivor consents to automatically accept the chosen opponent.
const ArenaRating = preload("res://scripts/shared/arena_rating.gd")
const TrainingDuel = preload("res://scripts/shared/training_duel.gd")

const MAX_QUEUED := 64
const BASE_ELO_GAP := 125
const ELO_GAP_STEP := 30
const ELO_GAP_STEP_SECONDS := 20.0
const MAX_ELO_GAP := 350
const CHECK_EVERY_TICKS := 10


static func join_reason(world, player, now: float) -> String:
	if player == null or not is_finite(now):
		return "invalid_player"
	if player.user_id.is_empty():
		return "account_required"
	if not player.position.is_finite():
		return "invalid_position"
	if not player.survival.alive:
		return "dead"
	if world.zone_at(player.position.x, player.position.z) != 0:
		return "safe_hub_only"
	if player.combat_tag_until > now:
		return "in_combat"
	if not ArenaRating.valid_rating(player.arena_rating):
		return "invalid_rating"
	return ""


static func gap_after(wait_seconds: float) -> int:
	if not is_finite(wait_seconds):
		return BASE_ELO_GAP
	var steps: int = maxi(0, floori(maxf(0.0, wait_seconds) / ELO_GAP_STEP_SECONDS))
	return mini(MAX_ELO_GAP, BASE_ELO_GAP + steps * ELO_GAP_STEP)


## Both participants must be eligible, uninvited and still the same
## authenticated Player instances that opted into queue.
static func entry_valid(entry: Dictionary, player, world, now: float,
		duels: Dictionary, invitations: Dictionary) -> bool:
	if join_reason(world, player, now) != "" or entry.is_empty():
		return false
	if int(entry.get("instance", -1)) != player.get_instance_id() or \
			str(entry.get("account", "")) != player.user_id:
		return false
	if duels.has(player.id) or invitations.has(player.id):
		return false
	for invitation in invitations.values():
		if int(invitation.get("from", -1)) == player.id:
			return false
	return true


## Prefer closest Elo of all eligible pairs, tie-breaking by time in queue
## then peer numbers. This is a capped, deterministic O(64^2) scan.
static func choose(queue: Dictionary, players: Dictionary, world, now: float,
		cooldowns: Dictionary, duels: Dictionary, invitations: Dictionary) -> Array[int]:
	var candidates: Array = queue.keys()
	candidates.sort()
	var best: Array[int] = []
	var best_gap: int = 999999
	var best_wait: float = INF
	for i in candidates.size():
		var a_id: int = int(candidates[i])
		var a = players.get(a_id)
		if not entry_valid(queue[a_id], a, world, now, duels, invitations):
			continue
		for j in range(i + 1, candidates.size()):
			var b_id: int = int(candidates[j])
			var other = players.get(b_id)
			if not entry_valid(queue[b_id], other, world, now, duels, invitations):
				continue
			if ArenaRating.eligibility(a, other, now, cooldowns) != "":
				continue
			if TrainingDuel.invitation_reason(world, a, other, now) != "":
				continue
			var gap: int = absi(a.arena_rating - other.arena_rating)
			var a_wait: float = now - float(queue[a_id].get("at", now))
			var b_wait: float = now - float(queue[b_id].get("at", now))
			if gap > mini(gap_after(a_wait), gap_after(b_wait)):
				continue
			var first_at: float = minf(float(queue[a_id]["at"]), float(queue[b_id]["at"]))
			if gap < best_gap or (gap == best_gap and first_at < best_wait):
				best_gap = gap
				best_wait = first_at
				best = [a_id, b_id]
	return best
