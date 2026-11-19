extends RefCounted
## Pure gameplay rules. Kept separate from rendering/physics for future server authority.

signal changed

const RECIPES := {
    "spear": {"wood": 2, "stone": 1},
    "bandage": {"fiber": 2, "herb": 1},
    "barricade": {"wood": 3, "stone": 2},
}
const MAX_HEALTH := 100.0
const MAX_HUNGER := 100.0

var items: Dictionary = {"wood": 0, "stone": 0, "fiber": 0, "herb": 0, "scrap": 0}
var health := MAX_HEALTH
var hunger := MAX_HUNGER
var has_spear := false


func add_item(kind: String, amount: int = 1) -> void:
    if amount <= 0 or not items.has(kind):
        return
    items[kind] = int(items[kind]) + amount
    changed.emit()


func has_cost(recipe: String) -> bool:
    if not RECIPES.has(recipe):
        return false
    var cost: Dictionary = RECIPES[recipe]
    for kind in cost:
        if int(items.get(kind, 0)) < int(cost[kind]):
            return false
    return true


func spend_recipe(recipe: String) -> bool:
    if not has_cost(recipe):
        return false
    var cost: Dictionary = RECIPES[recipe]
    for kind in cost:
        items[kind] = int(items[kind]) - int(cost[kind])
    changed.emit()
    return true


func craft_spear() -> bool:
    if has_spear or not spend_recipe("spear"):
        return false
    has_spear = true
    changed.emit()
    return true


func apply_damage(amount: float) -> void:
    health = maxf(0.0, health - maxf(amount, 0.0))
    changed.emit()


func heal(amount: float) -> void:
    health = minf(MAX_HEALTH, health + maxf(amount, 0.0))
    changed.emit()


func eat_herb() -> bool:
    if int(items["herb"]) <= 0 or hunger >= MAX_HUNGER:
        return false
    items["herb"] = int(items["herb"]) - 1
    hunger = minf(MAX_HUNGER, hunger + 22.0)
    changed.emit()
    return true


func tick(delta: float) -> void:
    if health <= 0.0:
        return
    hunger = maxf(0.0, hunger - 0.11 * delta)
    if hunger <= 0.0:
        apply_damage(2.0 * delta)
