extends RefCounted
## One UTC-rotating, account-persisted camp bounty per real-world day.
## The dedicated server selects the mission from its own UTC clock. A client
## cannot submit progress, reward quantities, a mission ID or an alternate day.

const Inventory = preload("res://scripts/shared/inventory.gd")
const SaveValidation = preload("res://scripts/shared/save_validation.gd")

const SECONDS_PER_DAY := 86400.0
const MAX_DAY := 100000
const BOUNTIES := [
	{"id": "infected_sweep", "title": "Daily: Infected sweep",
		"kind": "kills", "goal": 4, "deliver": {},
		"reward": {"silver": 24, "bandage": 1}, "renown": 4},
	{"id": "ruin_recon", "title": "Daily: Ruin reconnaissance",
		"kind": "crates", "goal": 2, "deliver": {},
		"reward": {"silver": 30, "water_bottle": 1}, "renown": 5},
	{"id": "camp_resupply", "title": "Daily: Supply the settlement",
		"kind": "deliver", "goal": 0,
		"deliver": {"wood_1": 5, "fiber_1": 4},
		"reward": {"silver": 28, "canned_food": 1}, "renown": 4},
]

static func utc_day() -> int:
	return maxi(0, int(floor(Time.get_unix_time_from_system() / SECONDS_PER_DAY)))


static func assignment(day: int) -> Dictionary:
	if day < 0 or day > MAX_DAY:
		return {}
	return BOUNTIES[day % BOUNTIES.size()]


static func empty_state() -> Dictionary:
	return {"day": 0, "progress": 0, "crate_ids": [], "claimed": false}


static func valid_state(data: Variant) -> bool:
	if not (data is Dictionary) or data.size() != 4:
		return false
	if not data.has("day") or not SaveValidation.valid_counter(data["day"]) \
			or int(data["day"]) > MAX_DAY:
		return false
	if not data.has("progress") or not SaveValidation.valid_counter(data["progress"]):
		return false
	if not data.has("claimed") or not (data["claimed"] is bool):
		return false
	var visited: Variant = data.get("crate_ids")
	if not (visited is Array):
		return false
	var rule: Dictionary = assignment(int(data["day"]))
	if rule.is_empty():
		return false
	var target: int = int(rule["goal"])
	var progress: int = int(data["progress"])
	if progress > target or visited.size() > 2:
		return false
	if bool(data["claimed"]) and (progress != 0 or not visited.is_empty()):
		return false
	var known: Dictionary = {}
	for identifier in visited:
		if not (identifier is String) or identifier.is_empty() or identifier.length() > 24 \
				or not identifier.is_valid_int() or known.has(identifier):
			return false
		known[identifier] = true
	if str(rule["kind"]) == "crates":
		return visited.size() == progress
	return visited.is_empty()


## Returning a new-day flag allows the owner to dirty the persistent character.
## A backwards-moving host clock never reopens a completed daily bounty.
static func refresh(state: Dictionary, today: int) -> bool:
	if not valid_state(state) or assignment(today).is_empty() or today <= int(state["day"]):
		return false
	state["day"] = today
	state["progress"] = 0
	state["crate_ids"] = []
	state["claimed"] = false
	return true


static func description(state: Dictionary, today: int) -> String:
	if not valid_state(state):
		return "Daily bounty record invalid"
	if int(state["day"]) < today:
		return "New UTC daily bounty available"
	var rule: Dictionary = assignment(int(state["day"]))
	if int(state["day"]) != today:
		return "Daily bounty clock not yet available"
	if bool(state["claimed"]):
		return "Daily bounty claimed — next UTC day"
	var details: String = ""
	if str(rule["kind"]) == "kills":
		details = "%d/%d confirmed infected" % [int(state["progress"]), int(rule["goal"])]
	elif str(rule["kind"]) == "crates":
		details = "%d/%d distinct ruin crates" % [int(state["progress"]), int(rule["goal"])]
	else:
		details = "deliver %s" % str(rule["deliver"])
	return "%s (%s)" % [str(rule["title"]), details]


static func record_kill(state: Dictionary, today: int) -> bool:
	refresh(state, today)
	if not valid_state(state) or int(state["day"]) != today or bool(state["claimed"]):
		return false
	var rule: Dictionary = assignment(today)
	if str(rule["kind"]) != "kills" or int(state["progress"]) >= int(rule["goal"]):
		return false
	state["progress"] = int(state["progress"]) + 1
	return true


## Only invoke after the server confirms a real, previously unopened crate.
static func record_crate(state: Dictionary, today: int, crate_id: int) -> bool:
	refresh(state, today)
	if not valid_state(state) or int(state["day"]) != today or bool(state["claimed"]):
		return false
	var rule: Dictionary = assignment(today)
	if str(rule["kind"]) != "crates" or int(state["progress"]) >= int(rule["goal"]):
		return false
	if crate_id < 0:
		return false
	var key := str(crate_id)
	var visited: Array = state["crate_ids"]
	if visited.has(key):
		return false
	visited.append(key)
	state["progress"] = int(state["progress"]) + 1
	return true


## Transactional delivery and reward: no partial debit or free prize on full bags.
static func claim(carried, state: Dictionary, today: int) -> Dictionary:
	refresh(state, today)
	if not valid_state(state) or int(state["day"]) != today:
		return {"ok": false, "reason": "invalid_day"}
	if bool(state["claimed"]):
		return {"ok": false, "reason": "already_claimed"}
	var rule: Dictionary = assignment(today)
	if int(state["progress"]) < int(rule["goal"]):
		return {"ok": false, "reason": "incomplete"}
	var trial = Inventory.new(carried.slots.size())
	trial.load_dict(carried.to_dict())
	for item_id in rule["deliver"]:
		if not trial.remove(str(item_id), int(rule["deliver"][item_id])):
			return {"ok": false, "reason": "missing_items"}
	for item_id in rule["reward"]:
		if trial.add(str(item_id), int(rule["reward"][item_id])) != 0:
			return {"ok": false, "reason": "no_space"}
	carried.load_dict(trial.to_dict())
	carried.unequip_missing()
	state["claimed"] = true
	state["progress"] = 0
	state["crate_ids"] = []
	return {"ok": true, "title": str(rule["title"]),
		"reward": (rule["reward"] as Dictionary).duplicate(true),
		"renown": int(rule["renown"]), "day": today}
