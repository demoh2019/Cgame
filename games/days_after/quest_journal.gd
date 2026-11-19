extends RefCounted
## Original onboarding objectives. Event counters are capped and kept even for
## later missions, so crafting or defeating infected early never soft-locks a run.

const STACK_LIMIT: int = 100000
const EVENT_LIMITS: Dictionary = {
    "pickup.food": 1,
    "pickup.water": 1,
    "gather.wood": 2,
    "gather.fiber": 2,
    "gather.stone": 1,
    "craft.makeshift_spear": 1,
    "equip.makeshift_spear": 1,
    "kill.infected": 1,
}
const EVENT_NAMES: Dictionary = {
    "pickup.food": "Scavenge a food ration",
    "pickup.water": "Scavenge clean water",
    "gather.wood": "Harvest wood",
    "gather.fiber": "Harvest fiber",
    "gather.stone": "Harvest stone",
    "craft.makeshift_spear": "Craft a makeshift spear",
    "equip.makeshift_spear": "Equip the spear",
    "kill.infected": "Defeat an infected",
}
const MISSIONS: Array = [
    {
        "id": "first_supplies",
        "title": "First Supplies",
        "objectives": {"pickup.food": 1, "pickup.water": 1},
        "reward_item": "scrap",
        "reward_amount": 1,
    },
    {
        "id": "fieldcraft",
        "title": "Fieldcraft",
        "objectives": {"gather.wood": 2, "gather.fiber": 2, "gather.stone": 1},
        "reward_item": "food",
        "reward_amount": 1,
    },
    {
        "id": "first_defense",
        "title": "First Defense",
        "objectives": {
            "craft.makeshift_spear": 1,
            "equip.makeshift_spear": 1,
            "kill.infected": 1,
        },
        "reward_item": "water",
        "reward_amount": 1,
    },
]

var counts: Dictionary = {}
var completed: int = 0


func _init() -> void:
    for event_id in EVENT_LIMITS:
        counts[event_id] = 0


## JSON decoders can represent integer-valued numbers as floating point.
## Reject non-integral, non-finite and out-of-range values regardless of type.
static func _bounded_int(value: Variant, maximum: int) -> bool:
    if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
        return false
    var number: float = float(value)
    return not is_nan(number) and not is_inf(number) and number >= 0.0 and number <= float(maximum) and number == float(int(number))


static func empty_snapshot() -> Dictionary:
    var progress: Dictionary = {}
    for event_id in EVENT_LIMITS:
        progress[event_id] = 0
    return {"counts": progress, "completed": 0}


func snapshot() -> Dictionary:
    return {"counts": counts.duplicate(true), "completed": completed}


## Return a normalized snapshot or {} when a saved journal is inconsistent.
static func validate_snapshot(data: Variant) -> Dictionary:
    if typeof(data) != TYPE_DICTIONARY or data.size() != 2:
        return {}
    if typeof(data.get("counts")) != TYPE_DICTIONARY:
        return {}
    var raw_counts: Dictionary = data["counts"]
    if raw_counts.size() != EVENT_LIMITS.size():
        return {}
    var finished: Variant = data.get("completed")
    if not _bounded_int(finished, MISSIONS.size()):
        return {}
    var clean_counts: Dictionary = {}
    for event_id in EVENT_LIMITS:
        var count: Variant = raw_counts.get(event_id)
        if not _bounded_int(count, int(EVENT_LIMITS[event_id])):
            return {}
        clean_counts[event_id] = int(count)
    for index in range(int(finished)):
        var mission: Dictionary = MISSIONS[index]
        var objectives: Dictionary = mission["objectives"]
        for event_id in objectives:
            if int(clean_counts[event_id]) < int(objectives[event_id]):
                return {}
    return {"counts": clean_counts, "completed": int(finished)}


func restore_validated(valid: Dictionary) -> void:
    counts = valid["counts"].duplicate(true)
    completed = int(valid["completed"])


func record_event(event_id: String, state: RefCounted, amount: int = 1) -> int:
    if not EVENT_LIMITS.has(event_id) or amount <= 0 or bool(state.get("dead")):
        return 0
    counts[event_id] = mini(int(EVENT_LIMITS[event_id]), int(counts[event_id]) + mini(amount, 100))
    return _complete_ready_missions(state)


func _complete_ready_missions(state: RefCounted) -> int:
    var new_completions: int = 0
    while completed < MISSIONS.size():
        var mission: Dictionary = MISSIONS[completed]
        var objectives: Dictionary = mission["objectives"]
        var ready: bool = true
        for event_id in objectives:
            if int(counts[event_id]) < int(objectives[event_id]):
                ready = false
                break
        if not ready:
            break
        var reward_id: String = mission["reward_item"]
        var reward_amount: int = int(mission["reward_amount"])
        var inventory: Dictionary = state.get("inventory")
        var stock: int = int(inventory.get(reward_id, -1))
        if stock < 0 or stock > STACK_LIMIT - reward_amount:
            break
        if not bool(state.call("add_resource", reward_id, reward_amount)):
            break
        completed += 1
        new_completions += 1
    return new_completions


func objective_count(event_id: String) -> int:
    return int(counts.get(event_id, 0))


func summary() -> String:
    if completed >= MISSIONS.size():
        return "SURVIVOR JOURNAL: All 3 introduction missions completed"
    var mission: Dictionary = MISSIONS[completed]
    var entries: PackedStringArray = []
    var objectives: Dictionary = mission["objectives"]
    for event_id in objectives:
        entries.append("%s %d/%d" % [
            str(EVENT_NAMES[event_id]),
            int(counts[event_id]),
            int(objectives[event_id]),
        ])
    return "MISSION %d/%d | %s\n%s\nReward: %s x%d" % [
        completed + 1,
        MISSIONS.size(),
        str(mission["title"]),
        " | ".join(entries),
        str(mission["reward_item"]).capitalize(),
        int(mission["reward_amount"]),
    ]
