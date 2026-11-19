extends RefCounted
## Offline player + shelter snapshot. Multiplayer worlds need server authority.

const PLAYER_SAVE = preload("res://save_state.gd")
const STASH_SCRIPT = preload("res://stash.gd")
const CONSTRUCTION_SCRIPT = preload("res://construction.gd")
const VERSION := 2
const SAVE_PATH := "user://days_after_world.json"


static func snapshot(game: Node) -> Dictionary:
    var survivor := game.get_node_or_null("Player") as Node3D
    var stash := game.get_node_or_null("ShelterStash") as Area3D
    var construction := game.get_node_or_null("Construction") as Node3D
    if survivor == null or stash == null or construction == null:
        return {}
    return {
        "version": VERSION,
        "player": PLAYER_SAVE.snapshot(survivor),
        "stash": stash.call("snapshot"),
        "structures": construction.call("snapshot")
    }


static func validate_snapshot(data: Variant) -> bool:
    if not (data is Dictionary):
        return false
    var version: Variant = data.get("version")
    if not (version is int or version is float) or (version != 1 and version != VERSION):
        return false
    if not PLAYER_SAVE.validate_snapshot(data.get("player")):
        return false
    if not STASH_SCRIPT.validate_contents(data.get("stash")):
        return false
    # Version 1 had no structures: migrate to an empty shelter defense layout.
    if version == 1:
        return true
    return CONSTRUCTION_SCRIPT.validate_snapshot(data.get("structures"))


static func apply_snapshot(game: Node, data: Variant) -> bool:
    var survivor := game.get_node_or_null("Player") as Node3D
    var stash := game.get_node_or_null("ShelterStash") as Area3D
    var construction := game.get_node_or_null("Construction") as Node3D
    # Validate the entire input before mutating any live game state.
    if survivor == null or stash == null or construction == null:
        return false
    if not validate_snapshot(data):
        return false
    var structures: Array = data.get("structures", []) if data["version"] == VERSION else []
    # Once prevalidated, the child restorers cannot fail for valid payloads.
    if not PLAYER_SAVE.apply_snapshot(survivor, data["player"]):
        return false
    if not bool(stash.call("restore_contents", data["stash"])):
        return false
    return bool(construction.call("restore_snapshot", structures))


static func save_world(game: Node, path: String = SAVE_PATH) -> bool:
    var data := snapshot(game)
    if not validate_snapshot(data):
        return false
    var file := FileAccess.open(path, FileAccess.WRITE)
    if file == null:
        return false
    file.store_string(JSON.stringify(data))
    file.flush()
    return file.get_error() == OK


static func load_world(game: Node, path: String = SAVE_PATH) -> bool:
    if not FileAccess.file_exists(path):
        return false
    var file := FileAccess.open(path, FileAccess.READ)
    if file == null:
        return false
    var data: Variant = JSON.parse_string(file.get_as_text())
    return apply_snapshot(game, data)
