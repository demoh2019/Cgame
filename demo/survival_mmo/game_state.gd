extends RefCounted
## Shared simulation rules. Keep changes validated here before server authority.

signal changed

const RECIPES := {
    "spear": {"wood": 2, "stone": 1},
    "reinforced_spear": {"wood": 1, "stone": 2, "scrap": 2},
    "bandage": {"fiber": 2, "herb": 1},
    "barricade": {"wood": 3, "stone": 2},
}
const RESOURCE_SKILLS := {
    "wood": "logging",
    "stone": "mining",
    "fiber": "foraging",
    "herb": "foraging",
}
const LEVEL_XP_STEP := 20
const MAX_SKILL_LEVEL := 10
const MAX_HEALTH := 100.0
const MAX_HUNGER := 100.0
## Weight is gameplay state, not CharacterBody physics mass. Units: kilograms.
const ITEM_WEIGHTS := {
    "wood": 2.0, "stone": 3.0, "fiber": 0.5, "herb": 0.25, "scrap": 1.5,
}
const WEAPON_WEIGHTS := {"hands": 0.0, "spear": 2.5, "reinforced_spear": 3.5}
const COMFORT_LOAD_KG := 25.0
const MAX_LOAD_KG := 50.0
const MIN_MOVE_FACTOR := 0.5

var items: Dictionary = {"wood": 0, "stone": 0, "fiber": 0, "herb": 0, "scrap": 0}
var experience: Dictionary = {
    "logging": 0, "mining": 0, "foraging": 0, "combat": 0, "crafting": 0
}
var health := MAX_HEALTH
var hunger := MAX_HUNGER
var equipped_weapon := "hands"


func get_carry_weight() -> float:
    var weight := float(WEAPON_WEIGHTS.get(equipped_weapon, 0.0))
    for kind in ITEM_WEIGHTS:
        weight += float(int(items.get(kind, 0))) * float(ITEM_WEIGHTS[kind])
    return weight


func get_free_weight() -> float:
    return maxf(0.0, MAX_LOAD_KG - get_carry_weight())


func item_capacity(kind: String) -> int:
    if not items.has(kind) or not ITEM_WEIGHTS.has(kind):
        return 0
    # All resource weights are strictly positive; use an epsilon for float boundaries.
    return maxi(0, floori((get_free_weight() + 0.0001) / float(ITEM_WEIGHTS[kind])))


func add_item(kind: String, amount: int = 1) -> int:
    ## Returns accepted count, allowing world pickup logic to avoid losing loot.
    if amount <= 0 or not items.has(kind):
        return 0
    var accepted := mini(amount, item_capacity(kind))
    if accepted == 0:
        return 0
    items[kind] = int(items[kind]) + accepted
    changed.emit()
    return accepted


func is_encumbered() -> bool:
    return get_carry_weight() > COMFORT_LOAD_KG + 0.0001


func can_sprint() -> bool:
    return not is_encumbered()


func move_speed_factor() -> float:
    if not is_encumbered():
        return 1.0
    var load_fraction := (get_carry_weight() - COMFORT_LOAD_KG) / (MAX_LOAD_KG - COMFORT_LOAD_KG)
    return lerpf(1.0, MIN_MOVE_FACTOR, clampf(load_fraction, 0.0, 1.0))


func get_level(skill: String) -> int:
    if not experience.has(skill):
        return 0
    return mini(MAX_SKILL_LEVEL, 1 + int(float(experience[skill]) / float(LEVEL_XP_STEP)))


func award_experience(skill: String, amount: int) -> void:
    if amount <= 0 or not experience.has(skill):
        return
    experience[skill] = int(experience[skill]) + amount
    changed.emit()


func collect_resource(kind: String) -> int:
    if not RESOURCE_SKILLS.has(kind):
        return 0
    var skill: String = RESOURCE_SKILLS[kind]
    # Experienced gatherers extract more from each node charge.
    var requested := 2 if get_level(skill) >= 3 else 1
    var accepted: int = add_item(kind, requested)
    if accepted > 0:
        award_experience(skill, 5)
    return accepted


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


func craft_weapon(recipe: String) -> bool:
    if recipe == "spear":
        if equipped_weapon != "hands":
            return false
    elif recipe == "reinforced_spear":
        if equipped_weapon != "spear" or get_level("combat") < 2:
            return false
    else:
        return false
    if not spend_recipe(recipe):
        return false
    equipped_weapon = recipe
    award_experience("crafting", 12)
    changed.emit()
    return true


func craft_spear() -> bool:
    return craft_weapon("spear")


func weapon_damage() -> float:
    var base := 10.0
    match equipped_weapon:
        "spear":
            base = 26.0
        "reinforced_spear":
            base = 40.0
    return base + 2.0 * float(get_level("combat") - 1)


func report_attack(killed: bool) -> void:
    award_experience("combat", 20 if killed else 3)


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
    hunger = maxf(0.0, hunger - 0.11 * maxf(delta, 0.0))
    if hunger <= 0.0:
        apply_damage(2.0 * maxf(delta, 0.0))
