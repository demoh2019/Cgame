extends RefCounted
## Albion After — Chapter I: The Last Transmission.
## A persistent, linear narrative with milestones taken ONLY from completed
## authoritative server actions. Clients may request to hear/transmit a
## broadcast; they may never submit chapter stage, kills, loot IDs or prizes.

const Inventory = preload("res://scripts/shared/inventory.gd")

const TITLE := "Chapter I — The Last Transmission"
const REQUIRED_KILLS := 3
const MIN_RUIN_ZONE := 2
const REWARD := {"silver": 90, "bandage": 2, "ammo_9mm": 10}
const LAST_STAGE := 4

const OBJECTIVES := [
	"At a camp workbench, tune the abandoned emergency radio.",
	"Find one unopened ruin cache in a red or black danger zone.",
	"Defeat 3 infected to protect the recovered radio log.",
	"Return to a camp workbench and transmit the encrypted recording.",
	"Chapter complete — the next signal comes from below the island.",
]

const TRANSCRIPT := [
	"DAY 0 / EMERGENCY BAND: A dead radio whispers: 'Beacon Seven... the cure was never meant to leave this island.'",
	"BEACON SEVEN / AUTOMATED ROUTING: Dr. Mara Voss left an encrypted field log inside a quarantined ruin. The old evacuation maps are wrong.",
	"RECOVERED LOG / DR. VOSS: 'Protocol ASH did not cure the infection. It taught the infected to listen.' Three carriers answer the recording's pulse.",
	"RELAY FRAGMENT: The three carriers are silent. One coordinate survived the corruption. The camp transmitter can decode it.",
	"FINAL TRANSMISSION: 'The island was never the source. We built the first beacon to contain what lies BELOW.' A second transmitter answers in the dark. END OF CHAPTER I.",
]


static func empty_state() -> Dictionary:
	return {"stage": 0, "kills": 0}


## A strict parser for account persistence, not the game's public snapshot.
## No incomplete chapter can be restored as completed for a free payout.
static func valid_state(data: Variant) -> bool:
	if not (data is Dictionary) or data.size() != 2 or not data.has("stage") or not data.has("kills"):
		return false
	if typeof(data["stage"]) != TYPE_INT or typeof(data["kills"]) != TYPE_INT:
		return false
	var stage: int = data["stage"]
	var kills: int = data["kills"]
	if stage < 0 or stage > LAST_STAGE or kills < 0 or kills > REQUIRED_KILLS:
		return false
	if stage < 2:
		return kills == 0
	if stage == 2:
		return kills < REQUIRED_KILLS
	return kills == REQUIRED_KILLS


static func objective(state: Dictionary) -> String:
	if not valid_state(state):
		return "Story data unavailable."
	var stage: int = int(state["stage"])
	if stage == 2:
		return "%s (%d/%d)" % [OBJECTIVES[stage], int(state["kills"]), REQUIRED_KILLS]
	return str(OBJECTIVES[stage])


static func public_state(state: Dictionary) -> Dictionary:
	if not valid_state(state):
		return {}
	var stage: int = int(state["stage"])
	var revealed: Array[String] = []
	for i in range(stage + 1):
		revealed.append(str(TRANSCRIPT[i]))
	return {
		"title": TITLE, "stage": stage, "kills": int(state["kills"]),
		"objective": objective(state), "transcript": revealed,
		"complete": stage == LAST_STAGE,
	}


static func current_line(state: Dictionary) -> String:
	if not valid_state(state):
		return ""
	return str(TRANSCRIPT[int(state["stage"])])


## Only called after the server confirms an actual player at the workbench.
static func listen(state: Dictionary) -> Dictionary:
	if not valid_state(state):
		return {"ok": false, "reason": "invalid_story"}
	if int(state["stage"]) != 0:
		return {"ok": false, "reason": "already_heard"}
	state["stage"] = 1
	return {"ok": true, "title": TITLE, "stage": 1,
		"line": current_line(state), "objective": objective(state)}


## An unopened, physically reached and successfully looted danger-zone crate
## is the only evidence that advances the plot. Loot itself remains unchanged.
static func record_ruin_cache(state: Dictionary, crate_id: int, zone: int) -> bool:
	if not valid_state(state) or int(state["stage"]) != 1 or crate_id <= 0 or zone < MIN_RUIN_ZONE:
		return false
	state["stage"] = 2
	return true


## Called exclusively by the existing confirmed zombie-death branch.
## Old kills, client reports, player PvP or repeat damage never count.
static func record_infected_kill(state: Dictionary) -> bool:
	if not valid_state(state) or int(state["stage"]) != 2:
		return false
	state["kills"] = int(state["kills"]) + 1
	if int(state["kills"]) == REQUIRED_KILLS:
		state["stage"] = 3
	return true


## Rewards are staged in a temporary backpack. No duplicate claims, partial
## payments, or progress consumption on full inventory.
static func transmit(state: Dictionary, carried) -> Dictionary:
	if not valid_state(state):
		return {"ok": false, "reason": "invalid_story"}
	if int(state["stage"]) == LAST_STAGE:
		return {"ok": false, "reason": "already_complete"}
	if int(state["stage"]) != 3:
		return {"ok": false, "reason": "incomplete"}
	var trial = Inventory.new(carried.slots.size())
	if not trial.load_dict(carried.to_dict()):
		return {"ok": false, "reason": "invalid_inventory"}
	for item_id in REWARD:
		if trial.add(str(item_id), int(REWARD[item_id])) != 0:
			return {"ok": false, "reason": "no_space"}
	carried.load_dict(trial.to_dict())
	state["stage"] = LAST_STAGE
	return {"ok": true, "title": TITLE, "stage": LAST_STAGE,
		"line": current_line(state), "objective": objective(state),
		"reward": REWARD.duplicate(true)}
