extends RefCounted
## Versioned local demo savegame: data stays on the player's device (user://).
## Never execute or instantiate user-provided saved contents.

const SAVE_PATH: String = "user://aurora_forest_save_v1.json"
const FORMAT_VERSION: int = 1
const MAX_WORLD_COORDINATE: float = 510.0


static func save_state(state: Dictionary, path: String = SAVE_PATH) -> bool:
    var payload: Dictionary = {
        "version": FORMAT_VERSION,
        "relics": state.get("relics", []),
        "position_xz": state.get("position_xz", [0.0, 9.0]),
        "look": state.get("look", [0.0, 0.0]),
        "quality": state.get("quality", true)
    }
    var file := FileAccess.open(path, FileAccess.WRITE)
    if file == null:
        push_error("Aurora Forest: failed to open local save file")
        return false
    file.store_string(JSON.stringify(payload))
    file.close()
    return true


static func load_state(max_relics: int, path: String = SAVE_PATH) -> Dictionary:
    if not FileAccess.file_exists(path):
        return {}
    var file := FileAccess.open(path, FileAccess.READ)
    if file == null:
        return {}
    var parsed: Variant = JSON.parse_string(file.get_as_text())
    file.close()
    if typeof(parsed) != TYPE_DICTIONARY:
        return {}
    var raw: Dictionary = parsed
    if raw.get("version", 0) != FORMAT_VERSION:
        return {}

    var ids: Array[int] = []
    var raw_ids: Variant = raw.get("relics", [])
    if raw_ids is Array:
        for value in raw_ids:
            if typeof(value) == TYPE_FLOAT or typeof(value) == TYPE_INT:
                var id: int = int(value)
                if id >= 0 and id < max_relics and not ids.has(id):
                    ids.append(id)

    var position := Vector2(0.0, 9.0)
    var xy: Variant = raw.get("position_xz", [])
    if xy is Array and xy.size() == 2:
        if (typeof(xy[0]) == TYPE_FLOAT or typeof(xy[0]) == TYPE_INT) \
                and (typeof(xy[1]) == TYPE_FLOAT or typeof(xy[1]) == TYPE_INT):
            position.x = clampf(float(xy[0]), -MAX_WORLD_COORDINATE, MAX_WORLD_COORDINATE)
            position.y = clampf(float(xy[1]), -MAX_WORLD_COORDINATE, MAX_WORLD_COORDINATE)

    var look := Vector2.ZERO
    var angles: Variant = raw.get("look", [])
    if angles is Array and angles.size() == 2:
        if (typeof(angles[0]) == TYPE_FLOAT or typeof(angles[0]) == TYPE_INT) \
                and (typeof(angles[1]) == TYPE_FLOAT or typeof(angles[1]) == TYPE_INT):
            look.x = clampf(float(angles[0]), -1.42, 1.42)
            look.y = clampf(float(angles[1]), -PI * 2.0, PI * 2.0)

    return {
        "relics": ids,
        "position_xz": position,
        "look": look,
        "quality": raw.get("quality", true) == true
    }
