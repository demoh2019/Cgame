extends Node
## Lightweight XZ navigation for this procedural survival map.
## Uses Cgame/Godot's built-in AStarGrid2D rather than custom native code.
## No NavMesh baking or external assets required for this small vertical slice.

const GRID_REGION := Rect2i(-19, -19, 39, 39)
const CLEARANCE := 0.65
const NO_CELL := Vector2i(100000, 100000)

var revision := 0
var _grid: AStarGrid2D


func _ready() -> void:
    _grid = AStarGrid2D.new()
    _grid.region = GRID_REGION
    _grid.cell_size = Vector2.ONE
    _grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
    # update() clears blocked cells; call it only once when configuring the grid.
    _grid.update()
    refresh()


func refresh() -> void:
    if _grid == null:
        return
    var footprints: Array[Rect2] = []
    for node in get_tree().get_nodes_in_group("nav_static_obstacle"):
        var body := node as StaticBody3D
        if body == null or body.is_queued_for_deletion():
            continue
        var size: Vector2 = body.get_meta("nav_footprint_size", Vector2.ZERO)
        footprints.append(_footprint(body.global_position, size))

    for node in get_tree().get_nodes_in_group("shelter_barricades"):
        var body := node as StaticBody3D
        if body == null or body.is_queued_for_deletion():
            continue
        if float(body.get("health")) <= 0.0:
            continue
        footprints.append(_footprint(body.global_position, Vector2(2.0, 0.45)))

    # Recompute solidity, not AStarGrid2D.update(): update resets these flags.
    for z in range(GRID_REGION.position.y, GRID_REGION.end.y):
        for x in range(GRID_REGION.position.x, GRID_REGION.end.x):
            var test_point := Vector2(float(x), float(z))
            var solid := false
            for box in footprints:
                if box.has_point(test_point):
                    solid = true
                    break
            _grid.set_point_solid(Vector2i(x, z), solid)
    revision += 1


func _footprint(position: Vector3, size: Vector2) -> Rect2:
    var half := size * 0.5 + Vector2.ONE * CLEARANCE
    return Rect2(Vector2(position.x, position.z) - half, half * 2.0)


func is_blocked(cell: Vector2i) -> bool:
    if _grid == null or not GRID_REGION.has_point(cell):
        return true
    return _grid.is_point_solid(cell)


func _nearest_open(id: Vector2i) -> Vector2i:
    var best := NO_CELL
    var best_dist := 1000000
    for dz in range(-4, 5):
        for dx in range(-4, 5):
            var next := id + Vector2i(dx, dz)
            if is_blocked(next):
                continue
            var dist := dx * dx + dz * dz
            if dist < best_dist:
                best = next
                best_dist = dist
    return best


func get_path(from_position: Vector3, destination: Vector3) -> Array[Vector3]:
    var waypoints: Array[Vector3] = []
    if _grid == null:
        return waypoints
    var start_cell := _nearest_open(Vector2i(roundi(from_position.x), roundi(from_position.z)))
    var goal_cell := _nearest_open(Vector2i(roundi(destination.x), roundi(destination.z)))
    if start_cell == NO_CELL or goal_cell == NO_CELL:
        return waypoints
    var cells: Array[Vector2i] = _grid.get_id_path(start_cell, goal_cell)
    for id in cells:
        waypoints.append(Vector3(float(id.x), 0.0, float(id.y)))
    return waypoints
