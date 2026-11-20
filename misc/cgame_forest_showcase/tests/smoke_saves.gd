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
        "quality": false,
        "time_of_day": 22.75,
        "weather": 2,
        "defeated_enemies": ["-1:1", "1:-2", "-1:1", "0:0", "2:0", "fake"]
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
    if not is_equal_approx(float(loaded.get("time_of_day", 0.0)), 22.75):
        _fail("time-of-day was not restored")
        return
    if loaded.get("weather", -1) != 2:
        _fail("saved weather was not restored")
        return
    var defeated: Array = loaded.get("defeated_enemies", [])
    if defeated.size() != 2 or not defeated.has("-1:1") or not defeated.has("1:-2"):
        _fail("defeated enemies did not persist or were not sanitized")
        return

    # Original v1 saves predate the weather and clock. They must still load.
    var legacy := FileAccess.open(TEMP_PATH, FileAccess.WRITE)
    if legacy == null:
        _fail("could not write legacy state")
        return
    legacy.store_string('{"version":1,"relics":[2],"quality":true,"position_xz":[0.0,9.0],"look":[0.0,0.0]}')
    legacy.close()
    var legacy_state: Dictionary = GameSave.load_state(8, TEMP_PATH)
    if legacy_state.get("weather", -1) != 0 or not is_equal_approx(float(legacy_state.get("time_of_day", 0.0)), 17.25):
        _fail("older v1 saves lost backwards compatibility")
        return
    if not legacy_state.get("defeated_enemies", []).is_empty():
        _fail("legacy v1 save must load without encounter history")
        return

    # External JSON cannot force invalid state into dynamic lighting.
    legacy = FileAccess.open(TEMP_PATH, FileAccess.WRITE)
    legacy.store_string('{"version":1,"time_of_day":"bad","weather":999,"defeated_enemies":[3,"bad","0:0","1:1","-2:-2","1:1"]}')
    legacy.close()
    var bad_atmosphere: Dictionary = GameSave.load_state(8, TEMP_PATH)
    if bad_atmosphere.get("weather", -1) != 0 or not is_equal_approx(float(bad_atmosphere.get("time_of_day", 0.0)), 17.25):
        _fail("invalid atmosphere state was not sanitized")
        return
    if bad_atmosphere.get("defeated_enemies", []).size() != 2:
        _fail("invalid or repeated encounter IDs were not rejected")
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
    print("Forest save smoke PASSED: v1 relics, weather, defeated enemies, legacy data, sanitization and bad JSON")
    quit(0)
