extends RefCounted
## Shared simulation rules. Keep changes validated here before server authority.

signal changed

const RECIPES := {
    "spear": {"wood": 2, "stone": 1},
    "reinforced_spear": {"wood": 1, "stone": 2, "scrap": 2},
    "bandage": {"fiber": 2, "herb": 1},
    "barricade": {"wood": 3, "stone": 2},
    "weapon_repair": {"wood": 1, "scrap": 1},
    "barricade_repair": {"wood": 1, "stone": 1},
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
const MAX_WEAPON_CONDITION := {"hands": 0, "spear": 60, "reinforced_spear": 100}

var items: Dictionary = {"wood": 0, "stone": 0, "fiber": 0, "herb": 0, "scrap": 0}
var experience: Dictionary = {
    "logging": 0, "mining": 0, "foraging": 0, "combat": 0, "crafting": 0
}
var health := MAX_HEALTH
var hunger := MAX_HUNGER
var equipped_weapon := "hands"
var weapon_condition := 0


func add_item(kind: String, amount: int = 1) -> void:
    if amount <= 0 or not items.has(kind):
        return
    items[kind] = int(items[kind]) + amount
    changed.emit()


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
    var amount := 2 if get_level(skill) >= 3 else 1
    add_item(kind, amount)
    award_experience(skill, 5)
    return amount


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
    weapon_condition = int(MAX_WEAPON_CONDITION[recipe])
    award_experience("crafting", 12)
    changed.emit()
    return true


func craft_spear() -> bool:
    return craft_weapon("spear")


func damage_weapon(amount: int = 1) -> bool:
    # A successful hit wears the equipped weapon. Returns true only if it breaks.
    if equipped_weapon == "hands" or amount <= 0:
        return false
    weapon_condition = maxi(0, weapon_condition - amount)
    var broken := weapon_condition == 0
    if broken:
        equipped_weapon = "hands"
    changed.emit()
    return broken


func repair_weapon() -> bool:
    if equipped_weapon == "hands":
        return false
    var maximum: int = MAX_WEAPON_CONDITION[equipped_weapon]
    if weapon_condition >= maximum or not spend_recipe("weapon_repair"):
        return false
    weapon_condition = mini(maximum, weapon_condition + 25)
    award_experience("crafting", 5)
    changed.emit()
    return true


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
