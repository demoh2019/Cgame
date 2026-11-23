extends RefCounted
## Chapter II: Beneath the Island. A separate account-bound journal preserves
## every Chapter I checkpoint without migrating or resetting earlier rewards.
## Only the authoritative dungeon hatch, physical underground cache, real
## champion death and hub radio may advance it.

const Inventory = preload("res://scripts/shared/inventory.gd")

const TITLE := "Chapter II — Beneath the Island"
const LAST_STAGE := 5
const SEAL := "seal"
const BROADCAST := "broadcast"
const SEAL_REWARD := {"silver": 110, "bandage": 3}
const BROADCAST_REWARD := {"silver": 130, "ammo_9mm": 12}
const OBJECTIVES := [
	"Decode the second transmission at a workbench (after Chapter I).",
	"Find a real bunker hatch and descend into the underground complex.",
	"Recover a sealed research cache from any underground dungeon room.",
	"Defeat the elite guardian in the dungeon's deepest chamber.",
	"Return to a workbench: seal the signal or broadcast the truth.",
	"Chapter II complete. Your decision is recorded.",
]
const RECORDINGS := [
	"BEACON SEVEN / FOLLOW-UP: A second transmitter answered from the underground quarantine vault. The reply uses Dr. Voss's voice.",
	"DR. VOSS / SECOND CHANNEL: 'There is a hatch beneath every old bunker. If my signal returns, do not trust what says it is me.'",
	"SUBLEVEL 01: The bunker opens onto an underground ward. Scratches on the stone walls repeat one sentence: WE ARE STILL LISTENING.",
	"VAULT LOG 4: 'ASH was a network, not a medicine. The guardians remember every voice we fed into it. The deepest chamber holds the root key.'",
	"ROOT KEY: The guardian is dead, but the network continues to speak. You can silence this relay, or warn the surviving camps. Choose at a workbench.",
]
const SEAL_EPILOGUE := "SIGNAL SEALED: You burned the relay key. For the first time, the bunker is silent. Far below, one light stays on. Someone wanted the silence."
const BROADCAST_EPILOGUE := "TRUTH BROADCAST: Every settlement hears the story of Project ASH. An unknown voice answers, 'Thank you for finding us.' The network knows your name."


static func empty_state() -> Dictionary:
	return {"stage": 0, "ending": ""}


static func valid_state(data: Variant) -> bool:
	if not (data is Dictionary) or data.size() != 2 or not data.has("stage") or not data.has("ending"):
		return false
	if typeof(data["stage"]) != TYPE_INT or not (data["ending"] is String):
		return false
	var stage: int = int(data["stage"])
	var ending: String = data["ending"]
	if stage < 0 or stage > LAST_STAGE:
		return false
	return (ending == SEAL or ending == BROADCAST) if stage == LAST_STAGE else ending.is_empty()


static func current_line(state: Dictionary) -> String:
	if not valid_state(state):
		return ""
	var stage: int = int(state["stage"])
	if stage == LAST_STAGE:
		return SEAL_EPILOGUE if str(state["ending"]) == SEAL else BROADCAST_EPILOGUE
	return str(RECORDINGS[stage])


static func objective(state: Dictionary) -> String:
	if not valid_state(state):
		return "Story data unavailable."
	return str(OBJECTIVES[int(state["stage"])])


static func public_state(state: Dictionary) -> Dictionary:
	if not valid_state(state):
		return {}
	var stage: int = int(state["stage"])
	var revealed: Array[String] = []
	for i in range(mini(stage, RECORDINGS.size() - 1) + 1):
		revealed.append(str(RECORDINGS[i]))
	if stage == LAST_STAGE:
		revealed.append(current_line(state))
	return {"title": TITLE, "stage": stage, "ending": str(state["ending"]),
		"objective": objective(state), "transcript": revealed,
		"complete": stage == LAST_STAGE}


## The server must check Chapter I is complete and the character is at
## a real workbench before invoking this function.
static func begin(state: Dictionary) -> Dictionary:
	if not valid_state(state):
		return {"ok": false, "reason": "invalid_story"}
	if int(state["stage"]) != 0:
		return {"ok": false, "reason": "already_started"}
	state["stage"] = 1
	return {"ok": true, "title": TITLE, "stage": 1, "line": current_line(state),
		"objective": objective(state)}


## Only called after GameServer.cmd_dungeon confirms a real bunker entrance.
static func record_descent(state: Dictionary) -> bool:
	if not valid_state(state) or int(state["stage"]) != 1:
		return false
	state["stage"] = 2
	return true


## An actually opened, reachable dungeon chest is the only valid data source.
static func record_underground_cache(state: Dictionary, crate_id: int) -> bool:
	if not valid_state(state) or int(state["stage"]) != 2 or crate_id <= 0:
		return false
	state["stage"] = 3
	return true


## Called only for server-spawned dungeon_boss elites killed by their real
## killer inside the *same* dungeon region (never ordinary elite mutants).
static func record_guardian(state: Dictionary) -> bool:
	if not valid_state(state) or int(state["stage"]) != 3:
		return false
	state["stage"] = 4
	return true


## The account's chapter-ending choice is permanent and exactly one reward
## transaction is allowed. Capacity refusal does not change any state.
static func resolve(state: Dictionary, carried, choice: String) -> Dictionary:
	if not valid_state(state):
		return {"ok": false, "reason": "invalid_story"}
	if choice != SEAL and choice != BROADCAST:
		return {"ok": false, "reason": "unknown_action"}
	if int(state["stage"]) == LAST_STAGE:
		return {"ok": false, "reason": "already_complete"}
	if int(state["stage"]) != 4:
		return {"ok": false, "reason": "incomplete"}
	var reward: Dictionary = SEAL_REWARD if choice == SEAL else BROADCAST_REWARD
	var trial = Inventory.new(carried.slots.size())
	trial.load_dict(carried.to_dict())
	for item_id in reward:
		if trial.add(str(item_id), int(reward[item_id])) != 0:
			return {"ok": false, "reason": "no_space"}
	carried.load_dict(trial.to_dict())
	state["stage"] = LAST_STAGE
	state["ending"] = choice
	return {"ok": true, "title": TITLE, "stage": LAST_STAGE, "ending": choice,
		"line": current_line(state), "objective": objective(state),
		"reward": reward.duplicate(true)}
