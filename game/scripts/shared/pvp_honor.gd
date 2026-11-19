extends RefCounted
## PvP glory independent from persistent PvE renown and criminal infamy.
## Only real server-confirmed PvP deaths add kills; repeated victims earn
## honor at most once per five minutes per stable account or guest identity.

const RaidLoot = preload("res://scripts/shared/raid_loot.gd")

const MAX_POINTS := 100000
const RED_REWARD := 4
const BLACK_REWARD := 10
const SAME_VICTIM_SECONDS := 300.0
const MAX_VICTIMS := 24
const MAX_ATTACKERS := 1024


static func rank(points: int) -> String:
	if points >= 100:
		return "Champion"
	if points >= 30:
		return "Veteran"
	if points >= 10:
		return "Contender"
	return "Wanderer"


## The ledger is session-scoped and never client-provided or persisted.
static func record(attacker, victim, zone: int, now: float, ledger: Dictionary) -> Dictionary:
	if attacker == null or victim == null or attacker == victim or 			not is_finite(now) or zone < 2 or zone > 3:
		return {"ok": false, "reason": "invalid_kill"}
	var who: String = RaidLoot.token(attacker)
	var target: String = RaidLoot.token(victim)
	if who == target:
		return {"ok": false, "reason": "same_account"}
	attacker.pvp_kills = mini(MAX_POINTS, attacker.pvp_kills + 1)
	var history: Dictionary = ledger.get(who, {})
	for key in history.keys():
		if now - float(history[key]) >= SAME_VICTIM_SECONDS:
			history.erase(key)
	var points: int = 0
	if now - float(history.get(target, -INF)) >= SAME_VICTIM_SECONDS:
		if history.size() >= MAX_VICTIMS and not history.has(target):
			var oldest: String = ""
			var first_seen: float = INF
			for key in history:
				if float(history[key]) < first_seen:
					first_seen = float(history[key])
					oldest = str(key)
			if not oldest.is_empty():
				history.erase(oldest)
		history[target] = now
		points = mini(MAX_POINTS - attacker.pvp_honor,
			BLACK_REWARD if zone == 3 else RED_REWARD)
		attacker.pvp_honor += points
	if not ledger.has(who) and ledger.size() >= MAX_ATTACKERS:
		var earliest_name: String = ""
		var earliest_time: float = INF
		for key in ledger:
			var times: Dictionary = ledger[key]
			var newest: float = -INF
			for entry in times:
				newest = maxf(newest, float(times[entry]))
			if newest < earliest_time:
				earliest_time = newest
				earliest_name = str(key)
		if not earliest_name.is_empty():
			ledger.erase(earliest_name)
	ledger[who] = history
	return {"ok": true, "awarded": points, "pvp_kills": attacker.pvp_kills,
		"honor": attacker.pvp_honor, "rank": rank(attacker.pvp_honor)}
