extends RefCounted
## Data-only survival, gathering, crafting, inventory and equipment.

const RECIPES: Dictionary = {
    "makeshift_spear": {"ingredients": {"wood": 2, "scrap": 1}, "result": 1, "experience": 15},
    "padded_coat": {"ingredients": {"fiber": 3, "scrap": 2}, "result": 1, "experience": 20},
    "bandage": {"ingredients": {"fiber": 2}, "result": 1, "experience": 8},
}
const GEAR: Dictionary = {
    "makeshift_spear": {"slot": "weapon", "damage": 24.0},
    "padded_coat": {"slot": "armor", "damage_reduction": 0.25},
}
const BASE_DAMAGE: float = 6.0

var health: float = 100.0
var hunger: float = 100.0
var thirst: float = 100.0
var stamina: float = 100.0
var dead: bool = false
var inventory: Dictionary = {
    "food": 0, "water": 0, "scrap": 0, "wood": 0, "stone": 0, "fiber": 0,
    "makeshift_spear": 0, "padded_coat": 0, "bandage": 0,
}
var equipped: Dictionary = {"weapon": "", "armor": ""}
var experience: Dictionary = {"gathering": 0, "crafting": 0}


func tick(delta: float, sprinting: bool) -> void:
    if dead or delta <= 0.0:
        return
    hunger = maxf(0.0, hunger - 0.045 * delta)
    thirst = maxf(0.0, thirst - 0.075 * delta)
    if sprinting:
        stamina = maxf(0.0, stamina - 16.0 * delta)
    else:
        stamina = minf(100.0, stamina + 11.0 * delta)
    if hunger <= 0.0 or thirst <= 0.0:
        apply_damage(3.0 * delta)


func add_resource(kind: String, amount: int) -> bool:
    if not inventory.has(kind) or amount <= 0 or dead:
        return false
    inventory[kind] = int(inventory[kind]) + amount
    return true


func gather(kind: String, amount: int) -> bool:
    if not add_resource(kind, amount):
        return false
    experience["gathering"] = int(experience["gathering"]) + amount * 5
    return true


func craft(recipe_id: String) -> bool:
    if dead or not RECIPES.has(recipe_id):
        return false
    var recipe: Dictionary = RECIPES[recipe_id]
    var ingredients: Dictionary = recipe["ingredients"]
    # A recipe is all-or-nothing: validate before spending anything.
    for kind in ingredients:
        if not inventory.has(kind) or int(inventory[kind]) < int(ingredients[kind]):
            return false
    for kind in ingredients:
        inventory[kind] = int(inventory[kind]) - int(ingredients[kind])
    inventory[recipe_id] = int(inventory[recipe_id]) + int(recipe["result"])
    experience["crafting"] = int(experience["crafting"]) + int(recipe["experience"])
    return true


func equip(item_id: String) -> bool:
    if dead or not GEAR.has(item_id) or int(inventory.get(item_id, 0)) < 1:
        return false
    var slot: String = GEAR[item_id]["slot"]
    equipped[slot] = item_id
    return true


func get_attack_damage() -> float:
    var weapon: String = equipped["weapon"]
    return float(GEAR[weapon]["damage"]) if GEAR.has(weapon) else BASE_DAMAGE


func get_damage_reduction() -> float:
    var armor: String = equipped["armor"]
    return float(GEAR[armor]["damage_reduction"]) if GEAR.has(armor) else 0.0


func apply_damage(raw_damage: float) -> void:
    if dead or raw_damage <= 0.0:
        return
    health = maxf(0.0, health - raw_damage * (1.0 - get_damage_reduction()))
    if health <= 0.0:
        dead = true


func skill_level(skill_name: String) -> int:
    if not experience.has(skill_name):
        return 0
    return 1 + int(floor(float(experience[skill_name]) / 25.0))


func use_resource(kind: String) -> bool:
    if dead or not inventory.has(kind) or int(inventory[kind]) < 1:
        return false
    match kind:
        "food":
            hunger = minf(100.0, hunger + 35.0)
        "water":
            thirst = minf(100.0, thirst + 45.0)
        "bandage":
            health = minf(100.0, health + 30.0)
        _:
            return false
    inventory[kind] = int(inventory[kind]) - 1
    return true
