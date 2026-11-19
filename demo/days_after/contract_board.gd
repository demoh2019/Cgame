extends Area3D

## In-world PvE contract board. Collect resources, demonstrate a crafted loadout
## and clear infected. No free rewards or repeated completions.
const RULES = preload("res://contract_rules.gd")

@export var display_name: String = "Доска контрактов: [E] принять / сдать"


func _ready() -> void:
    var hitbox := CollisionShape3D.new()
    var shape := BoxShape3D.new()
    shape.size = Vector3(1.6, 2.0, 0.55)
    hitbox.shape = shape
    add_child(hitbox)

    var visual := MeshInstance3D.new()
    var mesh := BoxMesh.new()
    mesh.size = shape.size
    visual.mesh = mesh
    var material := StandardMaterial3D.new()
    material.albedo_color = Color("#907451")
    material.roughness = 0.95
    visual.material_override = material
    add_child(visual)


func _read_state(player: Node) -> Dictionary:
    var state: Variant = player.get("contract_state")
    if not RULES.validate_state(state):
        return {}
    return (state as Dictionary).duplicate(true)


func interact(player: Node) -> bool:
    if not player.has_method("get_item_count") or not player.has_method("add_item"):
        return false
    if float(player.get("health")) <= 0.0:
        return false

    var state := _read_state(player)
    if state.is_empty():
        return false

    var active: String = str(state["active"])
    if active.is_empty():
        var next := RULES.next_contract(state)
        if next.is_empty():
            player.set("last_message", "Все контракты лагеря выполнены.")
            return false
        state["active"] = next
        state["progress"] = 0
        player.set("contract_state", state)
        player.set("last_message", "Получен контракт: %s." % str(RULES.CONTRACTS[next]["title"]))
        return true

    var details: Dictionary = RULES.CONTRACTS[active]
    if not _requirements_met(player, state, details):
        player.set("last_message", "Контракт пока не выполнен: %s." % str(details["title"]))
        return false
    if not _can_deliver_and_reward(player, details):
        player.set("last_message", "Недостаточно ресурсов или переполнен рюкзак.")
        return false

    # No yield, XP or reward is granted before ALL requirements are validated.
    var delivered: Dictionary = details["deliver"]
    for item_id in delivered:
        var item: String = str(item_id)
        var old_count: int = int(player.call("get_item_count", item))
        var inventory: Dictionary = player.get("inventory")
        inventory[item] = old_count - int(delivered[item_id])

    var rewards: Dictionary = details["reward"]
    for item_id in rewards:
        player.call("add_item", str(item_id), int(rewards[item_id]))

    var completed: Array = state["completed"]
    completed.append(active)
    state["active"] = ""
    state["progress"] = 0
    player.set("contract_state", state)
    player.set("last_message", "Контракт завершён: %s. Награда выдана." % str(details["title"]))
    return true


func record_infected_kill(player: Node) -> void:
    var state := _read_state(player)
    if state.is_empty():
        return
    var active: String = str(state["active"])
    if active.is_empty():
        return
    var details: Dictionary = RULES.CONTRACTS[active]
    var required: int = int(details["kills"])
    if required <= 0 or int(state["progress"]) >= required:
        return
    state["progress"] = int(state["progress"]) + 1
    player.set("contract_state", state)
    player.set("last_message", "Контракт: устранено заражённых %d/%d." % [
        int(state["progress"]), required
    ])


func _requirements_met(player: Node, state: Dictionary, details: Dictionary) -> bool:
    if int(state["progress"]) < int(details["kills"]):
        return false
    for item_id in details["deliver"]:
        var required: int = int(details["deliver"][item_id])
        if int(player.call("get_item_count", str(item_id))) < required:
            return false
    for item_id in details["possess"]:
        var required: int = int(details["possess"][item_id])
        if int(player.call("get_item_count", str(item_id))) < required:
            return false
    return true


func _can_deliver_and_reward(player: Node, details: Dictionary) -> bool:
    var stock: Dictionary = player.get("inventory")
    var totals: Dictionary = stock.duplicate(true)

    for item_id in details["deliver"]:
        var item: String = str(item_id)
        var remain: int = int(totals.get(item, 0)) - int(details["deliver"][item_id])
        if remain < 0:
            return false
        totals[item] = remain

    for item_id in details["reward"]:
        var item: String = str(item_id)
        var value: int = int(totals.get(item, 0)) + int(details["reward"][item_id])
        if value > 1000000:
            return false
        totals[item] = value

    return true
