extends RefCounted
## Versioned offline survivor snapshot. Game state belongs to the game layer.
## Future online servers must own authoritative progression and inventory.

# v1 stored only the survivor; v2 includes stable world pickup/deposit IDs.
const VERSION := 2
const SAVE_PATH := "user://days_after_player.json"
const MAX_ITEMS := 1000000
const MAX_XP := 100000000
const MAX_COORDINATE := 100000.0


static func snapshot(player: Node3D) -> Dictionary:
    var location := player.global_position
    var data: Dictionary = {
        "version": VERSION,
        "stats": {
            "health": float(player.get("health")),
            "hunger": float(player.get("hunger")),
            "thirst": float(player.get("thirst"))
        },
        "inventory": (player.get("inventory") as Dictionary).duplicate(true),
        "experience": {
            "gathering": (player.get("gathering_xp") as Dictionary).duplicate(true),
            "crafting": int(player.get("crafting_xp")),
            "combat": int(player.get("combat_xp"))
        },
        "equipped": {
            "tool": str(player.get("equipped_tool")),
            "weapon": str(player.get("equipped_weapon")),
            "armor": str(player.get("equipped_armor"))
        },
        "position": [location.x, location.y, location.z],
        "world": {"pickups": {}, "resources": {}}
    }
    var world_root := player.get_parent()
    if world_root != null and world_root.has_method("world_snapshot"):
        data["world"] = world_root.call("world_snapshot")
    return data


static func _valid_count(value: Variant, upper_bound: int) -> bool:
    if not (value is int or value is float):
        return false
    var number := float(value)
    return number >= 0.0 and number <= float(upper_bound) and number == floor(number)


static func _valid_stack_map(values: Variant, max_quantity: int) -> bool:
    if not (values is Dictionary):
        return false
    if values.size() > 2048:
        return false
    for item in values:
        if not (item is String) or item.is_empty() or item.length() > 64:
            return false
        if not _valid_count(values[item], max_quantity):
            return false
    return true


static func _valid_world_snapshot(world: Variant) -> bool:
    if not (world is Dictionary) or world.size() != 2:
        return false
    var pickups: Variant = world.get("pickups")
    var resources: Variant = world.get("resources")
    if not (pickups is Dictionary) or not (resources is Dictionary):
        return false
    if pickups.size() > 512 or resources.size() > 512:
        return false
    for name in pickups:
        if not (name is String) or name.is_empty() or name.length() > 128:
            return false
        if not (pickups[name] is bool):
            return false
    for name in resources:
        if not (name is String) or name.is_empty() or name.length() > 128:
            return false
        var state: Variant = resources[name]
        if not (state is Dictionary) or state.size() != 2:
            return false
        if not (state.get("depleted") is bool):
            return false
        var remaining: Variant = state.get("remaining")
        if not (remaining is int or remaining is float):
            return false
        if not (float(remaining) >= 0.0 and float(remaining) <= 600.0):
            return false
    return true


static func validate_snapshot(data: Variant) -> bool:
    if not (data is Dictionary):
        return false
    var version: Variant = data.get("version")
    if version != 1 and version != VERSION:
        return false
    if version == VERSION and not _valid_world_snapshot(data.get("world")):
        return false
    var stats: Variant = data.get("stats")
    var inventory: Variant = data.get("inventory")
    var experience: Variant = data.get("experience")
    var equipped: Variant = data.get("equipped")
    var position: Variant = data.get("position")
    if not (stats is Dictionary) or not (experience is Dictionary) or not (equipped is Dictionary):
        return false
    if not _valid_stack_map(inventory, MAX_ITEMS):
        return false
    for stat in ["health", "hunger", "thirst"]:
        var value: Variant = stats.get(stat)
        if not (value is int or value is float) or float(value) < 0.0 or float(value) > 100.0:
            return false
    if not _valid_stack_map(experience.get("gathering"), MAX_XP):
        return false
    for kind in ["wood", "stone", "fiber"]:
        if not (experience["gathering"] as Dictionary).has(kind):
            return false
    if not _valid_count(experience.get("crafting"), MAX_XP):
        return false
    if not _valid_count(experience.get("combat"), MAX_XP):
        return false
    for slot in ["tool", "weapon", "armor"]:
        var item: Variant = equipped.get(slot)
        if not (item is String):
            return false
        if not item.is_empty() and int(inventory.get(item, 0)) < 1:
            return false
    if not (position is Array) or position.size() != 3:
        return false
    for axis in position:
        if not (axis is int or axis is float):
            return false
        if not (float(axis) >= -MAX_COORDINATE and float(axis) <= MAX_COORDINATE):
            return false
    return true


static func apply_snapshot(player: Node3D, data: Variant) -> bool:
    # Validate the *whole* snapshot before making a single player change.
    if not validate_snapshot(data):
        return false
    # Reject unknown world object IDs BEFORE touching the survivor or the world.
    var world_root := player.get_parent()
    var has_world: bool = int(data["version"]) == VERSION
    if has_world:
        var world: Dictionary = data["world"]
        var has_objects: bool = not world["pickups"].is_empty() or not world["resources"].is_empty()
        if has_objects and (world_root == null or not world_root.has_method("can_apply_world_snapshot")
                or not bool(world_root.call("can_apply_world_snapshot", world))):
            return false
    var stats: Dictionary = data["stats"]
    var experience: Dictionary = data["experience"]
    var equipped: Dictionary = data["equipped"]
    var coordinates: Array = data["position"]
    player.set("health", float(stats["health"]))
    player.set("hunger", float(stats["hunger"]))
    player.set("thirst", float(stats["thirst"]))
    player.set("inventory", (data["inventory"] as Dictionary).duplicate(true))
    player.set("gathering_xp", (experience["gathering"] as Dictionary).duplicate(true))
    player.set("crafting_xp", int(experience["crafting"]))
    player.set("combat_xp", int(experience["combat"]))
    player.set("equipped_tool", str(equipped["tool"]))
    player.set("equipped_weapon", str(equipped["weapon"]))
    player.set("equipped_armor", str(equipped["armor"]))
    player.global_position = Vector3(float(coordinates[0]), float(coordinates[1]), float(coordinates[2]))
    if has_world and world_root != null and world_root.has_method("apply_world_snapshot"):
        world_root.call("apply_world_snapshot", data["world"])
    return true


static func save_player(player: Node3D, path: String = SAVE_PATH) -> bool:
    var data := snapshot(player)
    if not validate_snapshot(data):
        return false
    var file := FileAccess.open(path, FileAccess.WRITE)
    if file == null:
        return false
    file.store_string(JSON.stringify(data))
    file.flush()
    return file.get_error() == OK


static func load_player(player: Node3D, path: String = SAVE_PATH) -> bool:
    if not FileAccess.file_exists(path):
        return false
    var file := FileAccess.open(path, FileAccess.READ)
    if file == null:
        return false
    var data: Variant = JSON.parse_string(file.get_as_text())
    return apply_snapshot(player, data)
