extends RefCounted
## Versioned local persistence for an OFFLINE prototype. Not a trusted MMO protocol.

const VERSION := 1
const DEFAULT_PATH := "user://survival_world_v1.json"
const MAX_WORLD_ENTITIES := 512
const MAX_POSITION := 500.0
const MAX_ITEMS := 1000000
const MAX_XP := 100000000
const ITEM_IDS := ["wood", "stone", "fiber", "herb", "scrap"]
const SKILL_IDS := ["logging", "mining", "foraging", "combat", "crafting"]
const WEAPON_IDS := ["hands", "spear", "reinforced_spear"]
const WEAPON_CONDITION_MAX := {"hands": 0, "spear": 60, "reinforced_spear": 100}
const GATHER_IDS := ["wood", "stone", "fiber", "herb"]


static func _number(value: Variant, minimum: float, maximum: float) -> bool:
    if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
        return false
    var n := float(value)
    return not is_nan(n) and not is_inf(n) and n >= minimum and n <= maximum


static func _integer(value: Variant, maximum: int) -> bool:
    return _number(value, 0.0, float(maximum)) and float(value) == floorf(float(value))


static func _point(value: Variant) -> bool:
    if not (value is Array) or value.size() != 3:
        return false
    for coordinate in value:
        if not _number(coordinate, -MAX_POSITION, MAX_POSITION):
            return false
    return true


static func _valid_world(world: Dictionary) -> bool:
    for key in ["resources", "infected", "barricades"]:
        if not world.has(key) or not (world[key] is Array):
            return false
        if world[key].size() > MAX_WORLD_ENTITIES:
            return false
    for entry in world["resources"]:
        if not (entry is Dictionary):
            return false
        if not (entry.get("kind") is String) or not (entry["kind"] in GATHER_IDS):
            return false
        if not _integer(entry.get("remaining"), 4) or int(entry["remaining"]) < 1:
            return false
        if not _point(entry.get("position")):
            return false
    for entry in world["infected"]:
        if not (entry is Dictionary):
            return false
        if not _number(entry.get("health"), 0.01, 36.0):
            return false
        if not _point(entry.get("position")):
            return false
    for entry in world["barricades"]:
        if not (entry is Dictionary):
            return false
        if not _point(entry.get("position")) or not _number(entry.get("yaw"), -100.0, 100.0):
            return false
        if entry.has("hp") and not _number(entry["hp"], 0.01, 100.0):
            return false
    return true


static func is_valid_snapshot(snapshot: Variant) -> bool:
    if not (snapshot is Dictionary):
        return false
    if not _integer(snapshot.get("version"), VERSION) or int(snapshot["version"]) != VERSION:
        return false
    if not _point(snapshot.get("player")):
        return false
    var stats = snapshot.get("state")
    if not (stats is Dictionary):
        return false
    if not _number(stats.get("health"), 0.0, 100.0):
        return false
    if not _number(stats.get("hunger"), 0.0, 100.0):
        return false
    if not (stats.get("weapon") is String) or not (stats["weapon"] in WEAPON_IDS):
        return false
    # v1 saves without condition are supported: restore the weapon at full health.
    if stats.has("weapon_condition"):
        var maximum: int = WEAPON_CONDITION_MAX[stats["weapon"]]
        if not _integer(stats["weapon_condition"], maximum):
            return false
        if maximum == 0 and int(stats["weapon_condition"]) != 0:
            return false
        if maximum > 0 and int(stats["weapon_condition"]) == 0:
            return false
    var items = stats.get("items")
    var experience = stats.get("experience")
    if not (items is Dictionary) or not (experience is Dictionary):
        return false
    for item in ITEM_IDS:
        if not items.has(item) or not _integer(items[item], MAX_ITEMS):
            return false
    for skill in SKILL_IDS:
        if not experience.has(skill) or not _integer(experience[skill], MAX_XP):
            return false
    var world = snapshot.get("world")
    return world is Dictionary and _valid_world(world)


static func write_snapshot(snapshot: Dictionary, path: String = DEFAULT_PATH) -> bool:
    if not is_valid_snapshot(snapshot) or path.is_empty():
        return false
    # Write a temporary copy first; never truncate the last good save.
    var temporary := path + ".tmp"
    var file := FileAccess.open(temporary, FileAccess.WRITE)
    if file == null:
        return false
    file.store_string(JSON.stringify(snapshot))
    file.flush()
    file.close()

    var dest := ProjectSettings.globalize_path(path)
    var temp_abs := ProjectSettings.globalize_path(temporary)
    var backup := path + ".bak"
    var backup_abs := ProjectSettings.globalize_path(backup)
    var had_save := FileAccess.file_exists(path)
    if had_save:
        if FileAccess.file_exists(backup):
            if DirAccess.remove_absolute(backup_abs) != OK:
                return false
        if DirAccess.rename_absolute(dest, backup_abs) != OK:
            return false
    if DirAccess.rename_absolute(temp_abs, dest) != OK:
        if had_save:
            DirAccess.rename_absolute(backup_abs, dest)
        return false
    if had_save:
        DirAccess.remove_absolute(backup_abs)
    return true


static func _read_file(path: String) -> Dictionary:
    if not FileAccess.file_exists(path):
        return {}
    var file := FileAccess.open(path, FileAccess.READ)
    if file == null:
        return {}
    var json: Variant = JSON.parse_string(file.get_as_text())
    file.close()
    if not is_valid_snapshot(json):
        return {}
    return json


static func read_snapshot(path: String = DEFAULT_PATH) -> Dictionary:
    var snapshot := _read_file(path)
    if not snapshot.is_empty():
        return snapshot
    # Recover a previous good snapshot if a save was interrupted.
    return _read_file(path + ".bak")
