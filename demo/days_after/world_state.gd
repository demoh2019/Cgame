extends RefCounted

## Versioned, validated offline world snapshot. Does not own survivor stats.
## New online worlds must persist these changes on an authoritative server.
const VERSION := 1
const MAX_WORLD_OBJECTS := 4096


static func _nodes_with_method(game: Node3D, method: String) -> Dictionary:
    var result: Dictionary = {}
    for child in game.get_children():
        if child.has_method(method):
            result[str(child.name)] = child
    return result


static func snapshot(game: Node3D) -> Dictionary:
    var pickups: Dictionary = {}
    for id in _nodes_with_method(game, "set_collected_state"):
        var pickup: Node = game.get_node(NodePath(str(id)))
        pickups[id] = bool(pickup.get("collected"))

    var resources: Dictionary = {}
    for id in _nodes_with_method(game, "persistence_snapshot"):
        var resource: Node = game.get_node(NodePath(str(id)))
        resources[id] = resource.call("persistence_snapshot")

    return {
        "version": VERSION,
        "pickups": pickups,
        "resources": resources
    }


static func _valid_remaining(value: Variant, maximum: float) -> bool:
    if not (value is int or value is float):
        return false
    var seconds := float(value)
    return is_finite(seconds) and seconds >= 0.0 and seconds <= maximum


static func validate_snapshot(game: Node3D, state: Variant) -> bool:
    if not (state is Dictionary) or state.get("version") != VERSION:
        return false
    var saved_pickups: Variant = state.get("pickups")
    var saved_resources: Variant = state.get("resources")
    if not (saved_pickups is Dictionary) or not (saved_resources is Dictionary):
        return false

    var pickups := _nodes_with_method(game, "set_collected_state")
    var resources := _nodes_with_method(game, "persistence_snapshot")
    if pickups.size() > MAX_WORLD_OBJECTS or resources.size() > MAX_WORLD_OBJECTS:
        return false
    if saved_pickups.size() != pickups.size() or saved_resources.size() != resources.size():
        return false

    # Requiring the full stable set prevents unknown objects from sneaking into
    # an older world and prevents partial saves from silently regenerating loot.
    for id in pickups:
        if not saved_pickups.has(id) or not (saved_pickups[id] is bool):
            return false
    for id in resources:
        if not saved_resources.has(id):
            return false
        var entry: Variant = saved_resources[id]
        if not (entry is Dictionary) or not (entry.get("depleted") is bool):
            return false
        var max_wait: float = float(resources[id].get("respawn_seconds"))
        var remaining: Variant = entry.get("remaining_seconds")
        if not _valid_remaining(remaining, max_wait):
            return false
        if not bool(entry["depleted"]) and float(remaining) != 0.0:
            return false
    return true


static func apply_snapshot(game: Node3D, state: Variant) -> bool:
    # Entire snapshot passes validation before changing any node.
    if not validate_snapshot(game, state):
        return false
    var saved_pickups: Dictionary = state["pickups"]
    var saved_resources: Dictionary = state["resources"]
    for id in saved_pickups:
        game.get_node(NodePath(str(id))).call("set_collected_state", bool(saved_pickups[id]))
    for id in saved_resources:
        var entry: Dictionary = saved_resources[id]
        game.get_node(NodePath(str(id))).call(
            "restore_persistence_snapshot", bool(entry["depleted"]),
            float(entry["remaining_seconds"]))
    return true
