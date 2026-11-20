extends SceneTree
## Run with a Cgame/Godot 4.8 binary:
## godot --headless --path misc/cgame_forest_showcase -s res://tests/smoke_saves.gd
## This uses a separate test file, never the player's real savegame.

const GameSave = preload("res://scripts/game_save.gd")
const TEMP_PATH: String = "user://aurora_forest_smoke_test.json"


func _initialize() -> void:
    call_deferred("_run")


func _fail(reason: String) -> void:
    push_error("Forest save smoke FAILED: " + reason)
    _cleanup()
    quit(1)


func _cleanup() -> void:
    if FileAccess.file_exists(TEMP_PATH):
        DirAccess.remove_absolute(ProjectSettings.globalize_path(TEMP_PATH))


func _run() -> void:
    var saved: bool = GameSave.save_state({
        "relics": [0, 3, 3, -5, 99],
        "position_xz": [10.5, -20.25],
        "look": [0.3, 0.5],
        "quality": false
    }, TEMP_PATH)
    if not saved:
        _fail("could not write file")
        return

    var loaded: Dictionary = GameSave.load_state(8, TEMP_PATH)
    var ids: Array = loaded.get("relics", [])
    if ids.size() != 2 or not ids.has(0) or not ids.has(3):
        _fail("invalid or duplicate relic IDs were not sanitized")
        return
    var position: Vector2 = loaded.get("position_xz", Vector2.ZERO)
    if not position.is_equal_approx(Vector2(10.5, -20.25)):
        _fail("camera position was not restored")
        return
    if loaded.get("quality", true) != false:
        _fail("graphics quality was not restored")
        return

    # The expanded 1km world accepts valid remote positions and clamps
    # out-of-bounds saves to safe coordinates just inside perimeter walls.
    if not GameSave.save_state({"position_xz": [600.0, -600.0]}, TEMP_PATH):
        _fail("could not write boundary test save")
        return
    var clamped: Dictionary = GameSave.load_state(8, TEMP_PATH)
    var clamped_position: Vector2 = clamped.get("position_xz", Vector2.ZERO)
    if clamped_position.distance_to(Vector2(510.0, -510.0)) > 0.001:
        _fail("1km world save positions were not clamped correctly")
        return

    var file := FileAccess.open(TEMP_PATH, FileAccess.WRITE)
    if file == null:
        _fail("could not write tampered test data")
        return
    file.store_string("{invalid json}")
    file.close()
    if not GameSave.load_state(8, TEMP_PATH).is_empty():
        _fail("malformed JSON was incorrectly accepted")
        return

    file = FileAccess.open(TEMP_PATH, FileAccess.WRITE)
    file.store_string('{"version":999,"relics":[0]}')
    file.close()
    if not GameSave.load_state(8, TEMP_PATH).is_empty():
        _fail("incompatible save format was incorrectly accepted")
        return

    _cleanup()
    print("Forest save smoke PASSED: round trip, deduplication, bounds checks, invalid JSON and version rejection")
    quit(0)
