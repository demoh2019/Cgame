extends RefCounted
## Shared durability per equipment type. This vertical slice treats each type
## as one equipment stack; individual instances will require unique item IDs.

const MAX_CONDITION := 100
const REPAIR_COSTS := {
    "scavenger_tool": {"wood_t1": 1, "stone_t1": 1},
    "rusty_spear": {"wood_t1": 1, "stone_t1": 1},
    "reinforced_spear": {"wood_t2": 1, "stone_t2": 1},
    "scrap_vest": {"fiber_t1": 2, "stone_t1": 1}
}


static func is_equipment(item_id: String) -> bool:
    return REPAIR_COSTS.has(item_id)


static func condition_of(conditions: Dictionary, item_id: String) -> int:
    if not is_equipment(item_id):
        return 0
    return int(conditions.get(item_id, MAX_CONDITION))


static func wear(conditions: Dictionary, item_id: String, amount: int) -> bool:
    if not is_equipment(item_id) or amount <= 0:
        return false
    var before := condition_of(conditions, item_id)
    if before <= 0:
        return false
    conditions[item_id] = maxi(0, before - amount)
    return true


static func can_repair(conditions: Dictionary, inventory: Dictionary, item_id: String) -> bool:
    if not is_equipment(item_id) or int(inventory.get(item_id, 0)) < 1:
        return false
    if condition_of(conditions, item_id) >= MAX_CONDITION:
        return false
    var costs: Dictionary = REPAIR_COSTS[item_id]
    for material in costs:
        if int(inventory.get(material, 0)) < int(costs[material]):
            return false
    return true


static func repair(conditions: Dictionary, inventory: Dictionary, item_id: String) -> bool:
    # Validate the entire recipe before consuming any resources.
    if not can_repair(conditions, inventory, item_id):
        return false
    var costs: Dictionary = REPAIR_COSTS[item_id]
    for material in costs:
        inventory[material] = int(inventory[material]) - int(costs[material])
    conditions[item_id] = MAX_CONDITION
    return true


static func valid_map(value: Variant, inventory: Dictionary) -> bool:
    if not (value is Dictionary):
        return false
    for item_id in value:
        if not (item_id is String) or not is_equipment(item_id):
            return false
        var points: Variant = value[item_id]
        if not (points is int or points is float):
            return false
        var number := float(points)
        if number < 0.0 or number > MAX_CONDITION or floor(number) != number:
            return false
        if int(inventory.get(item_id, 0)) < 1:
            return false
    return true
