extends RefCounted
## Cross-training rewards using several different skill branches within a
## short live session. The server records only actions that actually earned XP.
## Session-local data cannot grant offline XP or survive a reconnect.

const Skills = preload("res://scripts/shared/skills.gd")

const WINDOW_SECONDS := 180.0
const RENEW_SECONDS := 15.0
const MIN_ACTION_XP := 5.0
const REQUIRED_BRANCHES := 3


static func qualifies(skill: String, amount: float) -> bool:
	return Skills.SKILLS.has(skill) and is_finite(amount) and amount >= MIN_ACTION_XP


## Only valid server-recorded branches inside the recent window count.
static func branches_count(state: Dictionary, now: float) -> int:
	if not is_finite(now) or now < 0.0:
		return 0
	var count: int = 0
	for branch in Skills.BRANCHES:
		if not state.has(branch):
			continue
		var raw: Variant = state[branch]
		if not (raw is int or raw is float):
			continue
		var at: float = float(raw)
		if is_finite(at) and at >= 0.0 and at <= now and now - at <= WINDOW_SECONDS:
			count += 1
	return count


## The current action can benefit only after three earlier branches were
## verified. Tiny tick-based XP and unknown skills never unlock this modifier.
static func active_for(state: Dictionary, skill: String, amount: float, now: float) -> bool:
	return qualifies(skill, amount) and branches_count(state, now) >= REQUIRED_BRANCHES


## A branch is refreshed at most once every 15 seconds. Keep at most five
## trusted branch timestamps to bound memory and discourage repetitive spam.
static func record(state: Dictionary, skill: String, amount: float, now: float) -> Dictionary:
	if not qualifies(skill, amount) or not is_finite(now) or now < 0.0:
		return state
	var clean: Dictionary = {}
	for branch in Skills.BRANCHES:
		if not state.has(branch):
			continue
		var raw: Variant = state[branch]
		if not (raw is int or raw is float):
			continue
		var at: float = float(raw)
		if is_finite(at) and at >= 0.0 and at <= now and now - at <= WINDOW_SECONDS:
			clean[branch] = at
	var info: Dictionary = Skills.SKILLS[skill]
	var branch: String = str(info.get("branch", ""))
	if not Skills.BRANCHES.has(branch):
		return clean
	if clean.has(branch) and now - float(clean[branch]) < RENEW_SECONDS:
		return clean
	clean[branch] = now
	return clean
