extends RefCounted
## Offline player + shelter snapshot. Multiplayer worlds need server authority.

const PLAYER_SAVE = preload("res://save_state.gd")
const STASH_SCRIPT = preload("res://stash.gd")
const VERSION := 1
const SAVE_PATH := "user://days_after_world.json"


static func snapshot(game: Node) -> Dictionary:
    var survivor := game.get_node_or_null("Player") as Node3D
    var stash := game.get_node_or_null("ShelterStash") as Area3D
    if survivor == null or stash == null:
        return {}
    return {
        "version": VERSION,
        "player": PLAYER_SAVE.snapshot(survivor),
        "stash": stash.call("snapshot")
    }


static func validate_snapshot(data: Variant) -> bool:
    return (
        data is Dictionary
        and data.get("version") == VERSION
        and PLAYER_SAVE.validate_snapshot(data.get("player"))
        and STASH_SCRIPT.validate_contents(data.get("stash"))
    )


static func apply_snapshot(game: Node, data: Variant) -> bool:
    var survivor := game.get_node_or_null("Player") as Node3D
    var stash := game.get_node_or_null("ShelterStash") as Area3D
    # Validate both parts *before* applying either one.
    if survivor == null or stash == null or not validate_snapshot(data):
        return false
    if not PLAYER_SAVE.apply_snapshot(survivor, data["player"]):
        return false
    return bool(stash.call("restore_contents", data["stash"]))


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
