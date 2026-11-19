extends Node3D
## World-facing barricade construction; keep resource rules in the game and
## geometry overlap queries in the existing Cgame/Godot 3D physics API.

signal barricade_built(barricade: StaticBody3D)

const Barricade = preload("res://barricade.gd")
const BUILD_COST := {"wood_t1": 3, "stone_t1": 2}
const BUILD_DISTANCE: float = 3.0
const RAY_HEIGHT: float = 2.0
const RAY_DEPTH: float = 5.0
const GROUND_CLEARANCE: float = 0.035

var player: CharacterBody3D


func _physics_process(_delta: float) -> void:
    if Input.is_action_just_pressed("build_barricade"):
        try_build()


func active_barricades() -> int:
    var total := 0
    for child in get_children():
        if child.is_in_group("player_barricades") and not child.is_queued_for_deletion():
            total += 1
    return total


func _placement_transform() -> Dictionary:
    if player == null or not is_instance_valid(player) or player.is_queued_for_deletion():
        return {}
    var direction: Vector3 = -player.global_transform.basis.z
    direction.y = 0.0
    if direction.length_squared() < 0.000001:
        return {}
    direction = direction.normalized()
    var intended := player.global_position + direction * BUILD_DISTANCE

    # Query real world collision: no construction on empty air or steep walls.
    var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
    var ground_ray := PhysicsRayQueryParameters3D.create(
        intended + Vector3.UP * RAY_HEIGHT,
        intended - Vector3.UP * RAY_DEPTH,
        1
    )
    ground_ray.exclude = [player.get_rid()]
    ground_ray.collide_with_areas = false
    var hit: Dictionary = space.intersect_ray(ground_ray)
    if hit.is_empty():
        return {}
    var normal: Vector3 = hit.get("normal", Vector3.ZERO)
    if normal.dot(Vector3.UP) < 0.85:
        return {}

    var ground: Vector3 = hit["position"]
    # Do not treat the roof of a wall or tall prop as a valid building pad.
    # Player origin is the capsule center; its feet are approximately 0.9 m lower.
    if absf(ground.y - (player.global_position.y - 0.9)) > 0.6:
        return {}
    var center := Vector3(
        intended.x,
        ground.y + Barricade.SIZE.y * 0.5 + GROUND_CLEARANCE,
        intended.z
    )
    var transform := Transform3D(Basis(Vector3.UP, player.rotation.y), center)

    # A native shape-overlap test prevents placement inside ruins, enemies,
    # other player-built walls or the player. The small vertical clearance
    # keeps the underlying ground from registering as an overlap.
    var box := BoxShape3D.new()
    box.size = Barricade.SIZE
    var query := PhysicsShapeQueryParameters3D.new()
    query.shape = box
    query.transform = transform
    query.margin = 0.0
    query.collision_mask = 1 | 4
    query.collide_with_bodies = true
    query.collide_with_areas = false
    query.exclude = [player.get_rid()]
    if not space.intersect_shape(query, 16).is_empty():
        return {}
    return {"transform": transform}


func try_build() -> bool:
    if player == null or float(player.get("health")) <= 0.0:
        return false
    if not player.has_method("try_spend_items") or not player.has_method("get_item_count"):
        return false
    for item_id in BUILD_COST:
        if int(player.call("get_item_count", str(item_id))) < int(BUILD_COST[item_id]):
            player.set("last_message", "Баррикада: нужны древесина T1 ×3 и камень T1 ×2.")
            return false

    # Only charge resources when a complete, nonintersecting placement exists.
    var placement: Dictionary = _placement_transform()
    if placement.is_empty():
        player.set("last_message", "Здесь нельзя строить: нет опоры или мешают объекты.")
        return false
    if not bool(player.call("try_spend_items", BUILD_COST)):
        return false

    var barricade: StaticBody3D = Barricade.new()
    barricade.name = "Barricade_%d" % (get_child_count() + 1)
    barricade.transform = placement["transform"]
    add_child(barricade)
    player.set("last_message", "Укрепление построено. [E] — ремонт (1 древесина T1).")
    barricade_built.emit(barricade)
    return true
