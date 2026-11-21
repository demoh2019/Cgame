extends RefCounted

## One offline save: survivor + the same world. No partial load of either.
## The existing save_state.gd remains the validator for survivor snapshots.
const SAVES = preload("res://save_state.gd")
const WORLD = preload("res://world_state.gd")
const VERSION := 1
const SAVE_PATH := "user://days_after_session.json"
const MAX_BYTES := 1024 * 1024


static func snapshot(game: Node3D) -> Dictionary:
    var player := game.get_node_or_null("Player") as Node3D
    if player == null:
        return {}
    return {
        "version": VERSION,
        "survivor": SAVES.snapshot(player),
        "world": WORLD.snapshot(game)
    }


static func validate_snapshot(game: Node3D, data: Variant) -> bool:
    if not (data is Dictionary) or data.get("version") != VERSION:
        return false
    var player := game.get_node_or_null("Player") as Node3D
    if player == null:
        return false
    return SAVES.validate_snapshot(data.get("survivor")) and WORLD.validate_snapshot(game, data.get("world"))


static func apply_snapshot(game: Node3D, data: Variant) -> bool:
    # Validation is all-or-nothing, before applying either substate.
    if not validate_snapshot(game, data):
        return false
    var player := game.get_node_or_null("Player") as Node3D
    if not SAVES.apply_snapshot(player, data["survivor"]):
        return false
    return WORLD.apply_snapshot(game, data["world"])


static func save_session(game: Node3D, path: String = SAVE_PATH) -> bool:
    var data := snapshot(game)
    if not validate_snapshot(game, data):
        return false
    var serialized := JSON.stringify(data)
    if serialized.to_utf8_buffer().size() > MAX_BYTES:
        return false

    # Write and flush a sibling file before replacing the real save.
    # Rename on the same volume avoids publishing a partial JSON document.
    var temp_path := path + ".tmp"
    var file := FileAccess.open(temp_path, FileAccess.WRITE)
    if file == null:
        return false
    file.store_string(serialized)
    file.flush()
    var wrote_ok := file.get_error() == OK
    file.close()
    if not wrote_ok:
        return false
    return DirAccess.rename_absolute(
        ProjectSettings.globalize_path(temp_path),
        ProjectSettings.globalize_path(path)) == OK


static func load_session(game: Node3D, path: String = SAVE_PATH) -> bool:
    if not FileAccess.file_exists(path):
        return false
    var file := FileAccess.open(path, FileAccess.READ)
    if file == null or file.get_length() > MAX_BYTES:
        return false
    var data: Variant = JSON.parse_string(file.get_as_text())
    return apply_snapshot(game, data)
