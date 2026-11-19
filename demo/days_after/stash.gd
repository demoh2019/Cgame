extends Area3D
## Shelter storage: game-level inventory, not an engine dependency.

const MAX_QUANTITY := 1000000
const MAX_TYPES := 2048
var stacks: Dictionary = {}
@export var display_name := "Склад убежища"


func _ready() -> void:
    var collider := CollisionShape3D.new()
    var shape := BoxShape3D.new()
    shape.size = Vector3(1.2, 1.25, 1.2)
    collider.shape = shape
    add_child(collider)
    var visual := MeshInstance3D.new()
    var mesh := BoxMesh.new()
    mesh.size = Vector3(1.2, 1.25, 1.2)
    visual.mesh = mesh
    var material := StandardMaterial3D.new()
    material.albedo_color = Color("#8b7653")
    material.roughness = 0.93
    visual.material_override = material
    add_child(visual)


func interact(player: Node) -> void:
    if not player.has_method("get_item_count"):
        return
    var world := get_parent()
    if world != null and world.has_method("toggle_stash"):
        world.call("toggle_stash", self)


func get_storage_count(item_id: String) -> int:
    return int(stacks.get(item_id, 0))


func deposit(player: Node, item_id: String, amount: int) -> bool:
    if not _valid_transfer(player, item_id, amount):
        return false
    var inventory_count: int = int(player.call("get_item_count", item_id))
    var stored_count := get_storage_count(item_id)
    if inventory_count < amount or stored_count > MAX_QUANTITY - amount:
        return false
    if stored_count == 0 and not stacks.has(item_id) and stacks.size() >= MAX_TYPES:
        return false
    # Equipped gear must remain owned by the character.
    for slot in ["equipped_tool", "equipped_weapon", "equipped_armor"]:
        if str(player.get(slot)) == item_id and inventory_count - amount < 1:
            return false
    var inventory: Dictionary = player.get("inventory")
    inventory[item_id] = inventory_count - amount
    stacks[item_id] = stored_count + amount
    return true


func withdraw(player: Node, item_id: String, amount: int) -> bool:
    if not _valid_transfer(player, item_id, amount):
        return false
    var stored_count := get_storage_count(item_id)
    var inventory_count: int = int(player.call("get_item_count", item_id))
    if stored_count < amount or inventory_count > MAX_QUANTITY - amount:
        return false
    if stored_count == amount:
        stacks.erase(item_id)
    else:
        stacks[item_id] = stored_count - amount
    player.call("add_item", item_id, amount)
    return true


func _valid_transfer(player: Node, item_id: String, amount: int) -> bool:
    return (
        is_instance_valid(player) and player.has_method("get_item_count")
        and player.has_method("add_item")
        and float(player.get("health")) > 0.0 and amount > 0
        and not item_id.is_empty() and item_id.length() <= 64
    )


static func validate_contents(data: Variant) -> bool:
    if not (data is Dictionary) or data.size() > MAX_TYPES:
        return false
    for item in data:
        if not (item is String) or item.is_empty() or item.length() > 64:
            return false
        var value: Variant = data[item]
        if not (value is int or value is float):
            return false
        var count := float(value)
        if count < 0.0 or count > float(MAX_QUANTITY) or count != floor(count):
            return false
    return true


func snapshot() -> Dictionary:
    return stacks.duplicate(true)


func restore_contents(data: Variant) -> bool:
    if not validate_contents(data):
        return false
    stacks = (data as Dictionary).duplicate(true)
    return true
