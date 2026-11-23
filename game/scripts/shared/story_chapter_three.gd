extends RefCounted
## Albion After — Chapter III: The Missing Convoy.
## A separate account-bound journal. Its opening remembers the *actual*
## completed Chapter II ending. All evidence comes from verified world actions.

const Inventory = preload("res://scripts/shared/inventory.gd")

const TITLE := "Chapter III — The Missing Convoy"
const LAST_STAGE := 4
const MIN_MANIFEST_ZONE := 2
const GUIDE := "guide"
const MASK := "mask"
const GUIDE_REWARD := {"silver": 160, "bandage": 3}
const MASK_REWARD := {"silver": 140, "ammo_9mm": 16}
const OBJECTIVES := [
	"Finish Chapter II and trace the new signal at a camp workbench.",
	"Find an unopened surface ruin cache in a red or black zone.",
	"Deliver a genuine merchant caravan between two settlements.",
	"At a camp workbench, guide the missing convoy or mask its route.",
	"Chapter III complete. Your decision is permanently recorded.",
]

const INTRO := "FREQUENCY 13 / STATIC: An unregistered convoy is transmitting a list of names. One belongs to Dr. Mara Voss."
const SEALED_SIGNAL := "AFTER THE SEAL: The underground network fell quiet, but a convoy is calling over the abandoned civilian band. Someone still knows the old route."
const BROADCAST_SIGNAL := "AFTER THE BROADCAST: Every settlement heard the truth. The network now repeats your name as a missing medical convoy calls for passage."
const MANIFEST := "RECOVERED MANIFEST: The relief trucks carried people, not specimens. Their last route crossed the quarantined trade roads. An ordinary supply caravan can recover the missing waypoint."
const ROUTE := "TRADE-ROAD RELAY: Your delivered caravan restored the route marker. A stranded convoy waits in the fog. A guidance pulse might lead them home; masking the route might keep ASH from following."
const GUIDE_SEALED := "GUIDANCE SENT: Survivors emerge from the fog under radio silence. Mara's last message: 'The cure was never in the vault. It was in the people we chose to save.'"
const GUIDE_BROADCAST := "GUIDANCE SENT: The camps answer with lanterns and take in the stranded survivors. The network hears their arrival too, and a distant beacon starts moving."
const MASK_SEALED := "ROUTE MASKED: No beacon can track the caravan now, but the stranded convoy disappears into the static. The island remains quiet, at a terrible cost."
const MASK_BROADCAST := "ROUTE MASKED: You flood the airwaves with false coordinates. ASH follows the decoy; the convoy vanishes from both the network and the camps' radios."


static func empty_state() -> Dictionary:
	return {"stage": 0, "source": "", "ending": ""}


static func valid_state(data: Variant) -> bool:
	if not (data is Dictionary):
		return false
	var state: Dictionary = data as Dictionary
	if state.size() != 3 or not state.has("stage") or not state.has("source") or not state.has("ending"):
		return false
	if typeof(state["stage"]) != TYPE_INT or not (state["source"] is String) or not (state["ending"] is String):
		return false
	var stage: int = state["stage"]
	var source: String = state["source"]
	var ending: String = state["ending"]
	if stage < 0 or stage > LAST_STAGE:
		return false
	if stage == 0:
		return source.is_empty() and ending.is_empty()
	if source != "seal" and source != "broadcast":
		return false
	return (ending == GUIDE or ending == MASK) if stage == LAST_STAGE else ending.is_empty()


static func objective(state: Dictionary) -> String:
	if not valid_state(state):
		return "Story data unavailable."
	return str(OBJECTIVES[int(state["stage"])])


static func _source_line(state: Dictionary) -> String:
	return SEALED_SIGNAL if str(state["source"]) == "seal" else BROADCAST_SIGNAL


static func current_line(state: Dictionary) -> String:
	if not valid_state(state):
		return ""
	match int(state["stage"]):
		0:
			return INTRO
		1:
			return _source_line(state)
		2:
			return MANIFEST
		3:
			return ROUTE
		_:
			if str(state["ending"]) == GUIDE:
				return GUIDE_SEALED if str(state["source"]) == "seal" else GUIDE_BROADCAST
			return MASK_SEALED if str(state["source"]) == "seal" else MASK_BROADCAST


static func public_state(state: Dictionary) -> Dictionary:
	if not valid_state(state):
		return {}
	var stage: int = int(state["stage"])
	var transcript: Array[String] = [INTRO]
	if stage >= 1:
		transcript.append(_source_line(state))
	if stage >= 2:
		transcript.append(MANIFEST)
	if stage >= 3:
		transcript.append(ROUTE)
	if stage == LAST_STAGE:
		transcript.append(current_line(state))
	return {
		"title": TITLE, "stage": stage, "source": str(state["source"]),
		"ending": str(state["ending"]), "objective": objective(state),
		"transcript": transcript, "complete": stage == LAST_STAGE,
	}


## Call only after authenticating a living player at the workbench and
## verifying their saved Chapter II is complete. No client-supplied choices.
static func begin(state: Dictionary, previous_ending: String) -> Dictionary:
	if not valid_state(state):
		return {"ok": false, "reason": "invalid_story"}
	if int(state["stage"]) != 0:
		return {"ok": false, "reason": "already_started"}
	if previous_ending != "seal" and previous_ending != "broadcast":
		return {"ok": false, "reason": "invalid_previous_ending"}
	state["stage"] = 1
	state["source"] = previous_ending
	return {"ok": true, "title": TITLE, "stage": 1,
		"line": current_line(state), "objective": objective(state)}


## Awarded only after the server has *already* opened a real, accessible,
## previously unopened surface cache with a danger-zone marker.
static func record_manifest(state: Dictionary, crate_id: int, zone: int) -> bool:
	if not valid_state(state) or int(state["stage"]) != 1 or crate_id <= 0 or zone < MIN_MANIFEST_ZONE:
		return false
	state["stage"] = 2
	return true


## Awarded only after CaravanEscortRewards.settle accepted real cargo at
## the verified destination NPC station. Accept/abandon/escort do not count.
static func record_delivery(state: Dictionary) -> bool:
	if not valid_state(state) or int(state["stage"]) != 2:
		return false
	state["stage"] = 3
	return true


## One atomic backpack transaction, one permanently recorded ending.
static func resolve(state: Dictionary, carried, choice: String) -> Dictionary:
	if not valid_state(state):
		return {"ok": false, "reason": "invalid_story"}
	if choice != GUIDE and choice != MASK:
		return {"ok": false, "reason": "unknown_action"}
	if int(state["stage"]) == LAST_STAGE:
		return {"ok": false, "reason": "already_complete"}
	if int(state["stage"]) != 3:
		return {"ok": false, "reason": "incomplete"}
	var reward: Dictionary = GUIDE_REWARD if choice == GUIDE else MASK_REWARD
	var trial = Inventory.new(carried.slots.size())
	trial.load_dict(carried.to_dict())
	for item_id in reward:
		if trial.add(str(item_id), int(reward[item_id])) != 0:
			return {"ok": false, "reason": "no_space"}
	carried.load_dict(trial.to_dict())
	state["stage"] = LAST_STAGE
	state["ending"] = choice
	return {"ok": true, "title": TITLE, "stage": LAST_STAGE,
		"ending": choice, "line": current_line(state),
		"objective": objective(state), "reward": reward.duplicate(true)}
