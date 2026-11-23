extends RefCounted
## Deep practice rewards learning multiple skills in the same discipline.
## Only confirmed, meaningful server XP awards are recorded. Progress is
## session-only, bounded to known skills and cannot mint XP without paid rest.

const Skills = preload("res://scripts/shared/skills.gd")

const WINDOW_SECONDS := 180.0
const RENEW_SECONDS := 15.0
const MIN_ACTION_XP := 5.0
const REQUIRED_SKILLS := 2


static func qualifies(skill: String, amount: float) -> bool:
	return Skills.SKILLS.has(skill) and is_finite(amount) and amount >= MIN_ACTION_XP


static func skills_in_branch(state: Dictionary, branch: String, now: float) -> int:
	if not Skills.BRANCHES.has(branch) or not is_finite(now) or now < 0.0:
		return 0
	var count: int = 0
	var entry: Dictionary = Skills.BRANCHES[branch]
	for skill in entry["skills"]:
		if not state.has(skill):
			continue
		var raw: Variant = state[skill]
		if not (raw is int or raw is float):
			continue
		var at: float = float(raw)
		if is_finite(at) and at >= 0.0 and at <= now and now - at <= WINDOW_SECONDS:
			count += 1
	return count


## Boost the current skill only after two *earlier* distinct skills in its
## own branch were trained; repeating one skill cannot unlock deep practice.
static func active_for(state: Dictionary, skill: String, amount: float, now: float) -> bool:
	if not qualifies(skill, amount):
		return false
	var info: Dictionary = Skills.SKILLS[skill]
	var branch: String = str(info.get("branch", ""))
	return skills_in_branch(state, branch, now) >= REQUIRED_SKILLS


static func trained_branches(state: Dictionary, now: float) -> int:
	var total: int = 0
	for branch in Skills.BRANCHES:
		if skills_in_branch(state, branch, now) >= REQUIRED_SKILLS:
			total += 1
	return total


## Trim stale or malformed entries on every eligible award. At most one
## timestamp per known skill is retained (13 entries in the current tree).
static func record(state: Dictionary, skill: String, amount: float, now: float) -> Dictionary:
	if not qualifies(skill, amount) or not is_finite(now) or now < 0.0:
		return state
	var clean: Dictionary = {}
	for trained in Skills.SKILLS:
		if not state.has(trained):
			continue
		var raw: Variant = state[trained]
		if not (raw is int or raw is float):
			continue
		var at: float = float(raw)
		if is_finite(at) and at >= 0.0 and at <= now and now - at <= WINDOW_SECONDS:
			clean[trained] = at
	if clean.has(skill) and now - float(clean[skill]) < RENEW_SECONDS:
		return clean
	clean[skill] = now
	return clean
