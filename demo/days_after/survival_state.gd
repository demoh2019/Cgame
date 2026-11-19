extends RefCounted
## Pure game-state logic, independent of the scene tree for headless tests.

signal changed

const MAX_STAT := 100.0
const HUNGER_DRAIN_PER_SECOND := 0.025
const THIRST_DRAIN_PER_SECOND := 0.045
const STARVATION_DAMAGE_PER_SECOND := 2.0

var health := MAX_STAT
var hunger := MAX_STAT
var thirst := MAX_STAT
var inventory: Dictionary = {}


func tick(delta: float) -> void:
    if not is_finite(delta) or delta <= 0.0 or health <= 0.0:
        return
    hunger = clampf(hunger - HUNGER_DRAIN_PER_SECOND * delta, 0.0, MAX_STAT)
    thirst = clampf(thirst - THIRST_DRAIN_PER_SECOND * delta, 0.0, MAX_STAT)
    if hunger <= 0.0 or thirst <= 0.0:
        health = maxf(health - STARVATION_DAMAGE_PER_SECOND * delta, 0.0)
    changed.emit()


func get_count(item_id: String) -> int:
    return int(inventory.get(item_id, 0))


func add_item(item_id: String, amount: int = 1) -> bool:
    if item_id.is_empty() or amount <= 0:
        return false
    inventory[item_id] = get_count(item_id) + amount
    changed.emit()
    return true


func remove_item(item_id: String, amount: int = 1) -> bool:
    if amount <= 0 or get_count(item_id) < amount:
        return false
    var remaining := get_count(item_id) - amount
    if remaining == 0:
        inventory.erase(item_id)
    else:
        inventory[item_id] = remaining
    changed.emit()
    return true


func use_item(item_id: String) -> bool:
    if item_id != "water" and item_id != "food":
        return false
    if not remove_item(item_id):
        return false
    if item_id == "water":
        thirst = minf(MAX_STAT, thirst + 35.0)
    else:
        hunger = minf(MAX_STAT, hunger + 30.0)
    changed.emit()
    return true


func is_alive() -> bool:
    return health > 0.0
