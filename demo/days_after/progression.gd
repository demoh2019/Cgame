extends RefCounted
## Original survival/RPG gathering and crafting rules, independent of SceneTree.
## Tiered resource gates are game rules, not Cgame engine responsibilities.

const GATHERING_XP_PER_LEVEL := 50
const CRAFTING_XP_PER_LEVEL := 50
const RESOURCES := {
    "wood": {"tier": 1, "yield": 2, "xp": 12},
    "fiber": {"tier": 1, "yield": 2, "xp": 12},
    "scrap": {"tier": 1, "yield": 2, "xp": 12},
    "ore": {"tier": 2, "yield": 2, "xp": 30, "tool": "pickaxe"}
}
const RECIPES := {
    "bandage": {"ingredients": {"fiber": 2}, "yield": 1, "xp": 15},
    "pickaxe": {"ingredients": {"wood": 2, "scrap": 2}, "yield": 1, "xp": 25},
    "reinforced_vest": {"ingredients": {"ore": 2, "scrap": 2}, "yield": 1, "xp": 35}
}

var gathering_xp := 0
var crafting_xp := 0
var _survival: RefCounted


func _init(survival: RefCounted) -> void:
    _survival = survival


func skill_level(skill: String) -> int:
    if skill == "gathering":
        return 1 + int(floor(float(gathering_xp) / float(GATHERING_XP_PER_LEVEL)))
    if skill == "crafting":
        return 1 + int(floor(float(crafting_xp) / float(CRAFTING_XP_PER_LEVEL)))
    return 0


func gather(resource_id: String, tier: int) -> Dictionary:
    if not RESOURCES.has(resource_id):
        return {"ok": false, "message": "Неизвестный ресурс."}
    var resource: Dictionary = RESOURCES[resource_id]
    if tier != int(resource["tier"]):
        return {"ok": false, "message": "Несовместимый уровень ресурса."}
    if skill_level("gathering") < tier:
        return {"ok": false, "message": "Нужен уровень добычи %d." % tier}
    var required_tool := String(resource.get("tool", ""))
    if not required_tool.is_empty() and _survival.get_count(required_tool) <= 0:
        return {"ok": false, "message": "Для добычи нужен инструмент: %s." % required_tool}
    var amount := int(resource["yield"])
    if not _survival.add_item(resource_id, amount):
        return {"ok": false, "message": "Не удалось добавить ресурс."}
    gathering_xp += int(resource["xp"])
    return {"ok": true, "message": "+%d %s | опыт добычи +%d" % [amount, resource_id, int(resource["xp"])]}


func craft(recipe_id: String) -> Dictionary:
    if not RECIPES.has(recipe_id):
        return {"ok": false, "message": "Неизвестный рецепт."}
    var recipe: Dictionary = RECIPES[recipe_id]
    var ingredients: Dictionary = recipe["ingredients"]
    for item_id in ingredients:
        if _survival.get_count(String(item_id)) < int(ingredients[item_id]):
            return {"ok": false, "message": "Недостаточно ресурсов для %s." % recipe_id}
    # All requirements are checked before any resources are consumed.
    for item_id in ingredients:
        _survival.remove_item(String(item_id), int(ingredients[item_id]))
    var output_amount := int(recipe["yield"])
    _survival.add_item(recipe_id, output_amount)
    crafting_xp += int(recipe["xp"])
    return {"ok": true, "message": "Создано: %s x%d | опыт ремесла +%d" % [recipe_id, output_amount, int(recipe["xp"])]}
