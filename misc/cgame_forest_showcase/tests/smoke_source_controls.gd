extends SceneTree
## Full Aurora Forest integration for two independently toggleable remote sources.
## cgame --headless --path misc/cgame_forest_showcase --script res://tests/smoke_source_controls.gd
## Reads but never writes the user's savegame.

const SURVEY_NAME: String = "survey_drone"
const TOWER_NAME: String = "watchtower"
const SURVEY: Vector2i = Vector2i(-5, 4)
const TOWER: Vector2i = Vector2i(3, -7)
const MAX_FRAMES: int = 1100


func _initialize() -> void:
    call_deferred("_run")


func _fail(message: String) -> void:
    push_error("Aurora Forest source controls smoke FAILED: " + message)
    quit(1)


func _wait_source(stream: WorldPartition3D, name: String) -> bool:
    for i in range(MAX_FRAMES):
        if stream.is_streaming_source_ready(name):
            return true
        await process_frame
    return false


func _run() -> void:
    var scene: PackedScene = load("res://world.tscn")
    if scene == null:
        _fail("playable world scene does not exist")
        return
    var world := scene.instantiate() as Node3D
    if world == null:
        _fail("playable scene is not a 3D world")
        return
    root.add_child(world)
    var stream := world.get_node_or_null("WorldPartition_32m") as WorldPartition3D
    var player := world.get_node_or_null("ExplorerBody") as CharacterBody3D
    if stream == null or player == null:
        _fail("world streamer or explorer is missing")
        return
    if stream.get_configured_cell_count() != 1024:
        _fail("bulk world-grid registration did not configure all 1024 cells")
        return
    if world.get_node_or_null("SurveyDroneBeacon") == null \
            or world.get_node_or_null("WatchtowerBeacon") == null:
        _fail("remote source markers did not integrate into the game")
        return

    # A savegame may load a distant player position: always normalize the
    # observer to the home clearing without writing that save back to disk.
    player.call("teleport_to_ground", 0.0, 9.0,
        world.call("height_at", 0.0, 9.0))
    stream.update_streaming()

    world.call("_toggle_streaming_source", SURVEY_NAME)
    world.call("_toggle_streaming_source", TOWER_NAME)
    if stream.get_streaming_source_count() != 2:
        _fail("F8/F10 did not activate two named engine streaming sources")
        return
    var survey: Dictionary = stream.get_streaming_source(SURVEY_NAME)
    var tower: Dictionary = stream.get_streaming_source(TOWER_NAME)
    if survey.get("center") != SURVEY or survey.get("load_radius") != 1 \
            or survey.get("priority") != 80:
        _fail("survey source config does not match the game controls")
        return
    if tower.get("center") != TOWER or tower.get("load_radius") != 0 \
            or tower.get("priority") != 25:
        _fail("tower source config does not match the game controls")
        return

    if not await _wait_source(stream, SURVEY_NAME):
        _fail("survey source did not load all nine forest cells")
        return
    if not await _wait_source(stream, TOWER_NAME):
        _fail("tower source did not load its separate location")
        return
    if not stream.is_cell_loaded(SURVEY) or not stream.is_cell_loaded(TOWER):
        _fail("independent distant areas are missing")
        return

    # Renderer/game HUD is updated on the normal game update frequency.
    for i in range(3):
        await process_frame
    var hud := world.get_node_or_null("GameHUD") as CanvasLayer
    if hud == null:
        _fail("game HUD does not exist")
        return
    var label := hud.get_node_or_null("Label") as Label
    if label == null:
        _fail("streaming HUD label is missing")
        return
    world.call("_refresh_hud")
    if not label.text.contains("Источники: 2/8") \
            or not label.text.contains("разведка: ГОТОВ") \
            or not label.text.contains("башня: ГОТОВ"):
        _fail("HUD did not report both ready remote streaming sources")
        return
    if int(world.get("source_ready_events")) < 2:
        _fail("source completion signals were not handled by gameplay")
        return

    world.call("_toggle_streaming_source", SURVEY_NAME)
    stream.update_streaming()
    if stream.get_streaming_source_count() != 1 or stream.is_cell_loaded(SURVEY):
        _fail("disabling survey source did not unload its remote area")
        return
    if not stream.is_cell_loaded(TOWER):
        _fail("releasing one source incorrectly removed the other location")
        return

    world.call("_toggle_streaming_source", TOWER_NAME)
    stream.update_streaming()
    if stream.get_streaming_source_count() != 0 or stream.is_cell_loaded(TOWER):
        _fail("tower source did not unload after being disabled")
        return
    if int(world.get("source_unready_events")) < 2:
        _fail("source-loss signals were not handled by gameplay")
        return

    print("Aurora Forest source controls smoke PASSED: F8/F10 regions, readiness and loss events, HUD and independent unload")
    quit(0)
