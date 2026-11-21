extends Control
## North-up survival map for the Days After × Albion prototype.
## Reuses existing 3D scene nodes; no duplicated world state.

const RESOURCE_SCRIPT = preload("res://resource_node.gd")
const PICKUP_SCRIPT = preload("res://pickup.gd")
const WORLD_RADIUS_METERS := 24.0
const UPDATE_INTERVAL := 0.15

var world: Node3D
var survivor: Node3D
var _refresh_elapsed := 0.0


static func world_to_map(relative: Vector3, world_radius: float, map_size: Vector2) -> Vector2:
    if world_radius <= 0.0:
        return map_size * 0.5
    # World -Z is north, so the player's X/Z offsets map to right/down.
    return map_size * 0.5 + Vector2(relative.x, relative.z) * (minf(map_size.x, map_size.y) * 0.46 / world_radius)


static func inside_radius(relative: Vector3, world_radius: float) -> bool:
    return world_radius > 0.0 and Vector2(relative.x, relative.z).length_squared() <= world_radius * world_radius


func _ready() -> void:
    mouse_filter = Control.MOUSE_FILTER_IGNORE
    clip_contents = true
    custom_minimum_size = Vector2(204, 204)
    set_process(true)


func _process(delta: float) -> void:
    if not is_instance_valid(world):
        world = get_parent().get_parent() as Node3D
    if world != null and not is_instance_valid(survivor):
        survivor = world.get_node_or_null("Player") as Node3D

    _refresh_elapsed += maxf(0.0, delta)
    if _refresh_elapsed >= UPDATE_INTERVAL:
        _refresh_elapsed = 0.0
        queue_redraw()


func _paint_pin(node: Node3D, tint: Color, pixel_radius: float = 4.0) -> void:
    if not is_instance_valid(node) or survivor == null:
        return
    var relative := node.global_position - survivor.global_position
    if not inside_radius(relative, WORLD_RADIUS_METERS):
        return
    var position_on_map := world_to_map(relative, WORLD_RADIUS_METERS, size)
    draw_circle(position_on_map, pixel_radius, tint)


func _draw() -> void:
    draw_rect(Rect2(Vector2.ZERO, size), Color(0.065, 0.09, 0.105, 0.91), true)
    draw_rect(Rect2(Vector2.ZERO, size), Color(0.38, 0.46, 0.48), false, 1.4)
    var center := size * 0.5
    var radius_pixels := minf(size.x, size.y) * 0.46
    draw_arc(center, radius_pixels, 0.0, TAU, 64, Color(0.42, 0.52, 0.53, 0.6), 1.4)
    for index in range(-2, 3):
        var offset := float(index) / 3.0 * radius_pixels
        draw_line(Vector2(center.x + offset, 12), Vector2(center.x + offset, size.y - 12), Color(0.24, 0.30, 0.32, 0.32))
        draw_line(Vector2(12, center.y + offset), Vector2(size.x - 12, center.y + offset), Color(0.24, 0.30, 0.32, 0.32))

    draw_string(get_theme_default_font(), Vector2(center.x - 4, 16), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.86, 0.91, 0.95))

    if not is_instance_valid(survivor) or not is_instance_valid(world):
        return

    for child in world.get_children():
        var spatial := child as Node3D
        if spatial == null:
            continue
        if spatial.get_script() == RESOURCE_SCRIPT:
            if not bool(spatial.get("depleted")):
                _paint_pin(spatial, Color(0.92, 0.76, 0.30), 3.4)
        elif spatial.get_script() == PICKUP_SCRIPT:
            if not bool(spatial.get("collected")):
                _paint_pin(spatial, Color(0.32, 0.86, 0.65), 3.4)

    var shelter := world.get_node_or_null("AbandonedShelter") as Node3D
    if shelter != null:
        _paint_pin(shelter, Color(0.45, 0.69, 1.0), 6.0)

    for enemy in get_tree().get_nodes_in_group("infected"):
        var spatial_enemy := enemy as Node3D
        if spatial_enemy != null and not spatial_enemy.is_queued_for_deletion():
            _paint_pin(spatial_enemy, Color(0.98, 0.37, 0.32), 4.6)

    var forward: Vector3 = -survivor.global_transform.basis.z
    var arrow := Vector2(forward.x, forward.z).normalized()
    if arrow.length_squared() < 0.0001:
        arrow = Vector2(0, -1)
    var sideways := Vector2(-arrow.y, arrow.x)
    var triangle := PackedVector2Array([
        center + arrow * 10.0,
        center - arrow * 6.0 + sideways * 5.5,
        center - arrow * 6.0 - sideways * 5.5
    ])
    draw_colored_polygon(triangle, Color(1.0, 1.0, 0.95))
