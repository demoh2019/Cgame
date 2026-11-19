extends RefCounted
## Versioned, validated offline checkpoints. Never deserialize arbitrary objects.
## The game owns its rules; Cgame's FileAccess/DirAccess already provide the needed IO.

const VERSION: int = 1
const DEFAULT_PATH: String = "user://days_after_save_v1.json"
const MAX_BYTES: int = 65536
const MAX_STACK: int = 100000
const MAX_EXPERIENCE: int = 10000000
const MAX_POSITION: float = 10000.0
const GEAR_RULES = preload("res://survival_state.gd")


static func _number(value: Variant, low: float, high: float) -> bool:
    if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
        return false
    var number := float(value)
    return not is_nan(number) and not is_inf(number) and number >= low and number <= high


static func _integer(value: Variant, low: int, high: int) -> bool:
    return _number(value, float(low), float(high)) and float(value) == float(int(value))


static func _position_valid(value: Variant) -> bool:
    if typeof(value) != TYPE_ARRAY or value.size() != 3:
        return false
    for component in value:
        if not _number(component, -MAX_POSITION, MAX_POSITION):
            return false
    return true


static func _position_to_array(value: Vector3) -> Array:
    return [value.x, value.y, value.z]


static func _array_to_position(value: Array) -> Vector3:
    return Vector3(float(value[0]), float(value[1]), float(value[2]))


static func capture(game: Node3D) -> Dictionary:
    var state = game.get("state")
    var survivor := game.get_node("Survivor") as Node3D
    var result: Dictionary = {
        "version": VERSION,
        "position": _position_to_array(survivor.global_position),
        "state": {
            "health": state.health,
            "hunger": state.hunger,
            "thirst": state.thirst,
            "stamina": state.stamina,
            "dead": state.dead,
            "inventory": state.inventory.duplicate(true),
            "equipped": state.equipped.duplicate(true),
            "experience": state.experience.duplicate(true),
        },
        "pickups": {},
        "resources": {},
        "enemies": {},
    }
    for child in game.get_children():
        var entity := child as Node3D
        if entity == null:
            continue
        var key := str(entity.name)
        if entity.is_in_group("days_after_pickup"):
            result["pickups"][key] = bool(entity.get("_collected"))
        elif entity.is_in_group("days_after_resource"):
            result["resources"][key] = int(entity.get("charges"))
        elif entity.is_in_group("days_after_enemy"):
            result["enemies"][key] = {
                "health": float(entity.get("health")),
                "position": _position_to_array(entity.global_position),
            }
    return result


## Validate the WHOLE document before changing a single gameplay value.
## Return an empty dictionary on invalid, unknown, stale or untrusted saves.
static func validate(document: Variant, game: Node3D) -> Dictionary:
    if typeof(document) != TYPE_DICTIONARY or document.size() != 6:
        return {}
    if not _integer(document.get("version"), VERSION, VERSION):
        return {}
    if not _position_valid(document.get("position")):
        return {}
    for field in ["state", "pickups", "resources", "enemies"]:
        if typeof(document.get(field)) != TYPE_DICTIONARY:
            return {}
    var state = game.get("state")
    var saved_state: Dictionary = document["state"]
    if saved_state.size() != 8:
        return {}
    var cleaned_state: Dictionary = {}
    for field in ["health", "hunger", "thirst", "stamina"]:
        var number: Variant = saved_state.get(field)
        if not _number(number, 0.0, 100.0):
            return {}
        cleaned_state[field] = float(number)
    if typeof(saved_state.get("dead")) != TYPE_BOOL:
        return {}
    if bool(saved_state["dead"]) != (float(cleaned_state["health"]) <= 0.0):
        return {}
    cleaned_state["dead"] = saved_state["dead"]

    var inventory: Variant = saved_state.get("inventory")
    var experience: Variant = saved_state.get("experience")
    var equipped: Variant = saved_state.get("equipped")
    if typeof(inventory) != TYPE_DICTIONARY or inventory.size() != state.inventory.size():
        return {}
    if typeof(experience) != TYPE_DICTIONARY or experience.size() != state.experience.size():
        return {}
    if typeof(equipped) != TYPE_DICTIONARY or equipped.size() != state.equipped.size():
        return {}

    var cleaned_inventory: Dictionary = {}
    for kind in state.inventory.keys():
        if not inventory.has(kind) or not _integer(inventory[kind], 0, MAX_STACK):
            return {}
        cleaned_inventory[kind] = int(inventory[kind])
    var cleaned_experience: Dictionary = {}
    for skill in state.experience.keys():
        if not experience.has(skill) or not _integer(experience[skill], 0, MAX_EXPERIENCE):
            return {}
        cleaned_experience[skill] = int(experience[skill])
    var cleaned_equipped: Dictionary = {}
    for slot in state.equipped.keys():
        var gear: Variant = equipped.get(slot)
        if typeof(gear) != TYPE_STRING:
            return {}
        if gear != "":
            if not GEAR_RULES.GEAR.has(gear):
                return {}
            if str(GEAR_RULES.GEAR[gear]["slot"]) != str(slot) or int(cleaned_inventory.get(gear, 0)) < 1:
                return {}
        cleaned_equipped[slot] = gear
    cleaned_state["inventory"] = cleaned_inventory
    cleaned_state["experience"] = cleaned_experience
    cleaned_state["equipped"] = cleaned_equipped

    var raw_pickups: Dictionary = document["pickups"]
    var raw_resources: Dictionary = document["resources"]
    var raw_enemies: Dictionary = document["enemies"]
    var cleaned_pickups: Dictionary = {}
    var cleaned_resources: Dictionary = {}
    var cleaned_enemies: Dictionary = {}
    for child in game.get_children():
        var entity := child as Node3D
        if entity == null:
            continue
        var key := str(entity.name)
        if entity.is_in_group("days_after_pickup"):
            if typeof(raw_pickups.get(key)) != TYPE_BOOL:
                return {}
            cleaned_pickups[key] = raw_pickups[key]
        elif entity.is_in_group("days_after_resource"):
            var charges: Variant = raw_resources.get(key)
            if not _integer(charges, 0, int(entity.get("max_charges"))):
                return {}
            cleaned_resources[key] = int(charges)
        elif entity.is_in_group("days_after_enemy"):
            var enemy_data: Variant = raw_enemies.get(key)
            if typeof(enemy_data) != TYPE_DICTIONARY or enemy_data.size() != 2:
                return {}
            if not _number(enemy_data.get("health"), 0.0, float(entity.get("max_health"))):
                return {}
            if not _position_valid(enemy_data.get("position")):
                return {}
            cleaned_enemies[key] = {
                "health": float(enemy_data["health"]),
                "position": enemy_data["position"].duplicate(),
            }
    if cleaned_pickups.size() != raw_pickups.size():
        return {}
    if cleaned_resources.size() != raw_resources.size():
        return {}
    if cleaned_enemies.size() != raw_enemies.size():
        return {}
    return {
        "version": VERSION,
        "position": document["position"].duplicate(),
        "state": cleaned_state,
        "pickups": cleaned_pickups,
        "resources": cleaned_resources,
        "enemies": cleaned_enemies,
    }


static func apply_validated(game: Node3D, valid: Dictionary) -> void:
    var state = game.get("state")
    var stats: Dictionary = valid["state"]
    state.health = stats["health"]
    state.hunger = stats["hunger"]
    state.thirst = stats["thirst"]
    state.stamina = stats["stamina"]
    state.dead = stats["dead"]
    state.inventory = stats["inventory"].duplicate(true)
    state.experience = stats["experience"].duplicate(true)
    state.equipped = stats["equipped"].duplicate(true)

    var survivor := game.get_node("Survivor") as CharacterBody3D
    survivor.global_position = _array_to_position(valid["position"])
    survivor.velocity = Vector3.ZERO
    for child in game.get_children():
        var entity := child as Node3D
        if entity == null:
            continue
        var key := str(entity.name)
        if entity.is_in_group("days_after_pickup"):
            entity.call("restore_collected", valid["pickups"][key])
        elif entity.is_in_group("days_after_resource"):
            entity.call("restore_charges", valid["resources"][key])
        elif entity.is_in_group("days_after_enemy"):
            var record: Dictionary = valid["enemies"][key]
            entity.call("restore_health", record["health"])
            entity.global_position = _array_to_position(record["position"])
            var enemy_body := entity as CharacterBody3D
            enemy_body.velocity = Vector3.ZERO


static func save(game: Node3D, path: String = DEFAULT_PATH) -> bool:
    var snapshot := capture(game)
    if validate(snapshot, game).is_empty():
        return false
    var payload := JSON.stringify(snapshot)
    if payload.to_utf8_buffer().size() > MAX_BYTES:
        return false
    var pending := path + ".tmp"
    var file := FileAccess.open(pending, FileAccess.WRITE)
    if file == null:
        return false
    file.store_string(payload)
    file.flush()
    var error := file.get_error()
    file.close()
    if error != OK:
        return false
    # A failed rename preserves the previous save rather than truncating it.
    return DirAccess.rename_absolute(
        ProjectSettings.globalize_path(pending),
        ProjectSettings.globalize_path(path)) == OK


static func load(game: Node3D, path: String = DEFAULT_PATH) -> bool:
    var file := FileAccess.open(path, FileAccess.READ)
    if file == null:
        return false
    if file.get_length() > MAX_BYTES:
        file.close()
        return false
    var decoded: Variant = JSON.parse_string(file.get_as_text())
    file.close()
    var valid := validate(decoded, game)
    if valid.is_empty():
        return false
    apply_validated(game, valid)
    return true
