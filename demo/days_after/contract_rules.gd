extends RefCounted

## The contract catalog is game data. Rewards never depend on client-supplied
## prices, quantities or item IDs. Online authoritative servers must repeat
## all checks and commits server-side.

const ORDER := ["supply_run", "smith_training", "infected_patrol"]

const CONTRACTS := {
    "supply_run": {
        "title": "Припасы для лагеря",
        "deliver": {"wood_t1": 2, "fiber_t1": 2},
        "possess": {},
        "kills": 0,
        "reward": {"food": 1, "water": 2}
    },
    "smith_training": {
        "title": "Испытание оружейника",
        "deliver": {},
        "possess": {"rusty_spear": 1},
        "kills": 0,
        "reward": {"field_bandage": 2, "water": 1}
    },
    "infected_patrol": {
        "title": "Зачистка окрестностей",
        "deliver": {},
        "possess": {},
        "kills": 2,
        "reward": {"fiber_t2": 2, "food": 2}
    }
}

const MAX_PROGRESS := 1000000


static func empty_state() -> Dictionary:
    return {"active": "", "progress": 0, "completed": []}


static func validate_state(data: Variant) -> bool:
    if not (data is Dictionary):
        return false
    var active: Variant = data.get("active")
    var progress: Variant = data.get("progress")
    var completed: Variant = data.get("completed")
    if not (active is String) or not (progress is int) or not (completed is Array):
        return false
    if not active.is_empty() and not CONTRACTS.has(active):
        return false
    if progress < 0 or progress > MAX_PROGRESS:
        return false
    if completed.size() > ORDER.size():
        return false
    var seen: Dictionary = {}
    for id in completed:
        if not (id is String) or not CONTRACTS.has(id) or seen.has(id):
            return false
        seen[id] = true
    if not active.is_empty() and seen.has(active):
        return false
    if active.is_empty() and progress != 0:
        return false
    if not active.is_empty():
        var kills: int = int(CONTRACTS[active]["kills"])
        if kills == 0 and progress != 0:
            return false
        if progress > kills and kills != 0:
            return false
    return true


static func next_contract(state: Dictionary) -> String:
    var completed: Array = state.get("completed", [])
    for id in ORDER:
        if not completed.has(id):
            return id
    return ""
