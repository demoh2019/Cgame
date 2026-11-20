extends SceneTree
## End-to-end dynamic streaming source regression with a moving scene Node3D.
## cgame --headless --path misc/cgame_forest_showcase --script res://tests/smoke_moving_sources.gd
##
## Tests source binding, cell transitions, old-region unload, missing-target
## suspension, resolution after reattachment, and visible gameplay telemetry.

const NAME: String = "survey_drone"
const START_CELL: Vector2i = Vector2i(-5, 4)
const MAX_FRAMES: int = 1100


func _initialize() -> void:
    call_deferred("_run")


func _fail(reason: String) -> void:
    push_error("Moving streaming source smoke FAILED: " + reason)
    quit(1)


func _wait_ready(stream: WorldPartition3D) -> bool:
    for i in range(MAX_FRAMES):
        if stream.is_streaming_source_ready(NAME):
            return true
        await process_frame
    return false


func _run() -> void:
    var packed: PackedScene = load("res://world.tscn")
    if packed == null:
        _fail("main playable scene could not be loaded")
        return
    var world := packed.instantiate() as Node3D
    if world == null:
        _fail("playable scene root must be Node3D")
        return
    root.add_child(world)
    var stream := world.get_node_or_null("WorldPartition_32m") as WorldPartition3D
    var actor := world.get_node_or_null("SurveyDroneBeacon") as Node3D
    var player := world.get_node_or_null("ExplorerBody") as CharacterBody3D
    if stream == null or actor == null or player == null:
        _fail("missing native streamer, drone marker or player")
        return

    # Stabilize the actor independently of any existing player savegame.
    world.set("survey_drone_paused", true)
    actor.position.x = -144.0
    actor.position.z = 144.0
    player.call("teleport_to_ground", 0.0, 9.0,
        world.call("height_at", 0.0, 9.0))
    stream.update_streaming()

    world.call("_toggle_streaming_source", NAME)
    var initial: Dictionary = stream.get_streaming_source(NAME)
    if initial.is_empty() or initial.get("center") != START_CELL:
        _fail("Node3D-bound source did not resolve its first position")
        return
    if initial.get("node_path") != stream.get_path_to(actor):
        _fail("dynamic source is not bound to the actual drone NodePath")
        return
    if not bool(initial.get("active", false)):
        _fail("valid drone source was marked inactive")
        return
    if not await _wait_ready(stream):
        _fail("first drone region did not fully stream")
        return
    if absf(stream.get_streaming_source_progress(NAME) - 1.0) > 0.00001:
        _fail("moving drone region did not report full scene readiness")
        return

    # Move across one grid boundary with NO call to set_streaming_source:
    # the engine itself must derive the new cell from actor global position.
    actor.position.x += 40.0
    stream.update_streaming()
    if stream.get_streaming_source(NAME).get("center") != Vector2i(-4, 4):
        _fail("native streamer failed to follow the moving actor")
        return
    if not await _wait_ready(stream):
        _fail("moving drone's next 3x3 region did not become ready")
        return

    # Leave the original unload_radius by a wide margin. The old remote
    # region should not survive after the drone moves elsewhere.
    actor.position.x += 128.0
    stream.update_streaming()
    if stream.get_streaming_source(NAME).get("center") != Vector2i(0, 4):
        _fail("moving drone's large position jump did not update center")
        return
    if stream.is_cell_loaded(START_CELL):
        _fail("obsolete original drone region did not unload")
        return
    if not await _wait_ready(stream):
        _fail("new drone region did not load after large movement")
        return

    var unready_before: int = int(world.get("source_unready_events"))
    world.remove_child(actor)
    stream.update_streaming()
    var missing: Dictionary = stream.get_streaming_source(NAME)
    if bool(missing.get("active", true)):
        _fail("missing Node3D did not deactivate dynamic source")
        return
    if stream.is_streaming_source_ready(NAME) \
            or stream.get_streaming_source_progress(NAME) != 0.0:
        _fail("missing actor still reports an available region")
        return
    if int(world.get("source_unready_events")) <= unready_before:
        _fail("missing actor did not emit the source-unready event")
        return
    if stream.is_cell_loaded(Vector2i(0, 4)):
        _fail("missing source did not unload its stale region")
        return

    # A re-added actor with the same NodePath automatically reactivates the
    # configured source without a new registration call.
    world.add_child(actor)
    stream.update_streaming()
    if not bool(stream.get_streaming_source(NAME).get("active", false)):
        _fail("reattached drone source did not resume")
        return
    if not await _wait_ready(stream):
        _fail("reattached drone failed to stream its region")
        return

    world.call("_refresh_hud")
    var hud := world.get_node_or_null("GameHUD/Label") as Label
    if hud == null or not hud.text.contains("Дрон X=0 Z=4"):
        _fail("playable HUD failed to show tracked dynamic source center")
        return

    world.call("_toggle_streaming_source", NAME)
    stream.update_streaming()
    if stream.get_streaming_source_count() != 0:
        _fail("F8 did not deregister dynamic source")
        return
    if stream.is_cell_loaded(Vector2i(0, 4)):
        _fail("removed moving source retained remote cells")
        return

    print("Moving streaming source smoke PASSED: Node3D follow, transitions, old-cell unload, missing actor recovery, HUD and teardown")
    quit(0)
