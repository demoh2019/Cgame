extends RefCounted
## Lightweight classless crafting and gathering progression.
## Keep the recipe and inventory rules independent of the scene tree.

const XP_PER_LEVEL := 40
const RECIPES := {
    "bandage": {
        "cost": {"fiber": 2},
        "output": {"bandage": 1},
        "level": 1, "xp": 20
    },
    "hatchet": {
        "cost": {"wood": 2, "scrap": 2},
        "output": {"hatchet": 1},
        "level": 1, "xp": 25
    },
    "medkit": {
        "cost": {"fiber": 3, "scrap": 1},
        "output": {"medkit": 1},
        "level": 2, "xp": 30
    }
}

var experience: Dictionary = {"gathering": 0, "crafting": 0}


func skill_level(skill: String) -> int:
    if not experience.has(skill):
        return 0
    return 1 + floori(float(experience[skill]) / float(XP_PER_LEVEL))


func gain_experience(skill: String, amount: int) -> void:
    if amount <= 0 or not experience.has(skill):
        return
    experience[skill] = int(experience[skill]) + amount


func can_craft(inventory: Dictionary, recipe_id: String) -> bool:
    if not RECIPES.has(recipe_id):
        return false
    var recipe: Dictionary = RECIPES[recipe_id]
    if skill_level("crafting") < int(recipe["level"]):
        return false
    var cost: Dictionary = recipe["cost"]
    for item in cost:
        if int(inventory.get(item, 0)) < int(cost[item]):
            return false
    return true


func craft(inventory: Dictionary, recipe_id: String) -> bool:
    # Validate all inputs first: a failed craft must never consume materials.
    if not can_craft(inventory, recipe_id):
        return false
    var recipe: Dictionary = RECIPES[recipe_id]
    var cost: Dictionary = recipe["cost"]
    var outputs: Dictionary = recipe["output"]
    for item in cost:
        inventory[item] = int(inventory[item]) - int(cost[item])
    for item in outputs:
        inventory[item] = int(inventory.get(item, 0)) + int(outputs[item])
    gain_experience("crafting", int(recipe["xp"]))
    return true
