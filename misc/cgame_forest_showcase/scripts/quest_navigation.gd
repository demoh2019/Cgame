extends RefCounted
## Lightweight quest navigation for the Aurora Forest vertical slice.
## The first reachable uncollected relic is selected by horizontal distance.
## Once selected, gameplay keeps the target until collection or save reload.

const SOURCE_NAME: String = "relic_objective"
const STREAMING_PRIORITY: int = 0 # Background objective prep.


static func closest_relic(relics: Array[Node3D], player_position: Vector3) -> Node3D:
    var candidate: Node3D = null
    var best_distance_sq: float = INF
    for relic in relics:
        if not is_instance_valid(relic) or relic.is_queued_for_deletion():
            continue
        var distance_sq: float = Vector2(
            relic.global_position.x - player_position.x,
            relic.global_position.z - player_position.z).length_squared()
        if distance_sq < best_distance_sq:
            best_distance_sq = distance_sq
            candidate = relic
    return candidate


static func horizontal_distance(player_position: Vector3, destination: Vector3) -> float:
    return Vector2(destination.x - player_position.x,
        destination.z - player_position.z).length()


static func heading(player: Node3D, destination: Vector3) -> String:
    var towards: Vector3 = destination - player.global_position
    towards.y = 0.0
    if towards.length_squared() < 0.25:
        return "цель рядом"
    towards = towards.normalized()
    var front: float = towards.dot(-player.global_basis.z)
    var right: float = towards.dot(player.global_basis.x)
    var angle: float = rad_to_deg(atan2(right, front))
    if absf(angle) < 25.0:
        return "прямо"
    if angle >= 155.0 or angle <= -155.0:
        return "позади"
    if angle > 0.0:
        return "справа" if angle < 110.0 else "справа-сзади"
    return "слева" if angle > -110.0 else "слева-сзади"


static func sync_streaming_source(stream: WorldPartition3D, target: Node3D) -> bool:
    if not is_instance_valid(stream):
        return false
    if not is_instance_valid(target) or target.is_queued_for_deletion():
        stream.remove_streaming_source(SOURCE_NAME)
        return true
    return stream.set_streaming_source(SOURCE_NAME, target.global_position, 0, STREAMING_PRIORITY)


static func cell_route(stream: WorldPartition3D,
        from_world: Vector3, to_world: Vector3, loaded_only: bool = false) -> Array:
    # Native bounded grid routing; this is a topology hint, not a navmesh.
    if not is_instance_valid(stream):
        return []
    var from_cell: Vector2i = stream.local_position_to_cell(stream.to_local(from_world))
    var to_cell: Vector2i = stream.local_position_to_cell(stream.to_local(to_world))
    return stream.find_cell_path(from_cell, to_cell, loaded_only)


static func next_cell_waypoint(stream: WorldPartition3D, route: Array) -> Vector3:
    # The intermediate waypoint must be inside a registered corridor cell.
    # For a last-cell hop use the actual quest target instead.
    if not is_instance_valid(stream) or route.size() < 3:
        return Vector3.ZERO
    var next_cell: Vector2i = route[1]
    var half: float = stream.cell_size * 0.5
    return stream.to_global(stream.cell_to_local_position(next_cell) + Vector3(half, 0, half))
