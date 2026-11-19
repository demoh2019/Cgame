extends Node3D
## Three predefined pads keep the first construction slice deterministic.
## All rules and prices live in the game; Cgame needs no new engine API.

const BARRICADE = preload("res://barricade.gd")
const WOOD_COST := 2
const STONE_COST := 1
const REPAIR_WOOD_COST := 1
const MAX_RANGE := 4.0
const REPAIR_AMOUNT := 35.0
const SLOT_POSITIONS := [
    Vector3(-2.5, 0.8, 8.5),
    Vector3(0.5, 0.8, 12.5),
    Vector3(4.0, 0.8, 8.5)
]

var defenses: Dictionary = {}


func _ready() -> void:
    name = "Construction"
    for i in range(SLOT_POSITIONS.size()):
        var marker := MeshInstance3D.new()
        marker.name = "Pad%d" % i
        var mesh := BoxMesh.new()
        mesh.size = Vector3(2.0, 0.08, 0.5)
        marker.mesh = mesh
        marker.position = SLOT_POSITIONS[i] - Vector3(0.0, 0.78, 0.0)
        var mat := StandardMaterial3D.new()
        mat.albedo_color = Color("#555a50")
        marker.material_override = mat
        add_child(marker)


func _nearest_slot(player: Node3D, require_empty: bool) -> int:
    if player == null:
        return -1
    var best := MAX_RANGE
    var best_slot := -1
    for i in range(SLOT_POSITIONS.size()):
        if require_empty and defenses.has(i):
            continue
        if not require_empty and not defenses.has(i):
            continue
        var position_2d := Vector2(SLOT_POSITIONS[i].x, SLOT_POSITIONS[i].z)
        var player_2d := Vector2(player.global_position.x, player.global_position.z)
        var distance := position_2d.distance_to(player_2d)
        if distance < best:
            best = distance
            best_slot = i
    return best_slot


func build_nearest(player: Node3D) -> bool:
    if player == null or float(player.get("health")) <= 0.0:
        return false
    var slot := _nearest_slot(player, true)
    if slot < 0:
        return false
    if player.global_position.distance_to(
        Vector3(SLOT_POSITIONS[slot].x, player.global_position.y, SLOT_POSITIONS[slot].z)
    ) < 1.35:
        return false
    if int(player.call("get_item_count", "wood_t1")) < WOOD_COST:
        return false
    if int(player.call("get_item_count", "stone_t1")) < STONE_COST:
        return false
    var inventory: Dictionary = player.get("inventory")
    inventory["wood_t1"] = int(inventory["wood_t1"]) - WOOD_COST
    inventory["stone_t1"] = int(inventory["stone_t1"]) - STONE_COST
    _spawn(slot, BARRICADE.MAX_HEALTH)
    return true


func repair_nearest(player: Node3D) -> bool:
    if player == null or float(player.get("health")) <= 0.0:
        return false
    var slot := _nearest_slot(player, false)
    if slot < 0 or int(player.call("get_item_count", "wood_t1")) < REPAIR_WOOD_COST:
        return false
    var barrier = defenses[slot]
    if not is_instance_valid(barrier) or barrier.health >= BARRICADE.MAX_HEALTH:
        return false
    var inventory: Dictionary = player.get("inventory")
    inventory["wood_t1"] = int(inventory["wood_t1"]) - REPAIR_WOOD_COST
    barrier.health = minf(BARRICADE.MAX_HEALTH, barrier.health + REPAIR_AMOUNT)
    return true


func _spawn(slot: int, life: float) -> void:
    var barrier = BARRICADE.new()
    barrier.name = "Barricade%d" % slot
    barrier.slot_index = slot
    barrier.health = life
    barrier.position = SLOT_POSITIONS[slot]
    barrier.destroyed.connect(_on_destroyed)
    add_child(barrier)
    defenses[slot] = barrier


func _on_destroyed(slot: int) -> void:
    defenses.erase(slot)


func get_built_count() -> int:
    return defenses.size()


func snapshot() -> Array:
    var result := []
    for slot in range(SLOT_POSITIONS.size()):
        if defenses.has(slot):
            var barrier = defenses[slot]
            if is_instance_valid(barrier) and barrier.health > 0.0:
                result.append({"slot": slot, "health": barrier.health})
    return result


static func validate_snapshot(data: Variant) -> bool:
    if not (data is Array) or data.size() > SLOT_POSITIONS.size():
        return false
    var seen := {}
    for entry in data:
        if not (entry is Dictionary):
            return false
        var slot: Variant = entry.get("slot")
        var health: Variant = entry.get("health")
        if not (slot is int or slot is float) or float(slot) != floor(float(slot)) or int(slot) < 0 or int(slot) >= SLOT_POSITIONS.size():
            return false
        if seen.has(slot):
            return false
        seen[slot] = true
        if not (health is int or health is float):
            return false
        var hp := float(health)
        if is_nan(hp) or is_inf(hp) or hp <= 0.0 or hp > BARRICADE.MAX_HEALTH:
            return false
    return true


func restore_snapshot(data: Variant) -> bool:
    if not validate_snapshot(data):
        return false
    for old in defenses.values():
        if is_instance_valid(old):
            remove_child(old)
            old.queue_free()
    defenses.clear()
    for entry in data:
        _spawn(int(entry["slot"]), float(entry["health"]))
    return true
