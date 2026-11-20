extends SceneTree
## End-to-end fast-travel demonstration: game -> native pins -> terrain -> game.
## cgame --headless --path misc/cgame_forest_showcase --script res://tests/smoke_fast_travel.gd
## No savegame writes; preserves real user:// saves.

const OUTPOST_CELL: Vector2i = Vector2i(6, 6)
const HOME_CELL: Vector2i = Vector2i.ZERO
const OUTPOST_POS: Vector2 = Vector2(208.0, 208.0)
const HOME_POS: Vector2 = Vector2(0.0, 9.0)
const MAX_FRAMES: int = 750


func _initialize() -> void:
    call_deferred("_run")


func _fail(reason: String) -> void:
    push_error("Fast-travel smoke FAILED: " + reason)
    quit(1)


func _wait_loaded(stream: WorldPartition3D, cell: Vector2i) -> bool:
    for i in range(MAX_FRAMES):
        if stream.is_cell_loaded(cell):
            return true
        await process_frame
    return false


func _run() -> void:
    var packed: PackedScene = load("res://world.tscn")
    if packed == null:
        _fail("playable world scene is unavailable")
        return
    var world := packed.instantiate() as Node3D
    if world == null:
        _fail("playable world root is not 3D")
        return
    root.add_child(world)
    var stream := world.get_node_or_null("WorldPartition_32m") as WorldPartition3D
    var player := world.get_node_or_null("ExplorerBody") as CharacterBody3D
    if stream == null or player == null or world.get_node_or_null("FastTravelOutpost") == null:
        _fail("game lacks native streamer, physics explorer or outpost marker")
        return

    # Start at home regardless of an existing, unrelated user savegame.
    var home_height: float = world.call("height_at", HOME_POS.x, HOME_POS.y)
    player.call("teleport_to_ground", HOME_POS.x, HOME_POS.y, home_height)
    stream.update_streaming()
    if not await _wait_loaded(stream, HOME_CELL):
        _fail("home terrain could not load")
        return

    # F6 should toggle residency of a far destination without teleporting.
    world.call("_toggle_outpost_pin")
    if not stream.is_cell_pinned(OUTPOST_CELL) or stream.get_pinned_cell_count() != 1:
        _fail("F6 did not pin distant outpost")
        return
    world.call("_toggle_outpost_pin")
    if stream.is_cell_pinned(OUTPOST_CELL) or stream.get_pinned_cell_count() != 0:
        _fail("second F6 did not release distant outpost")
        return

    # First F7 requests a remote destination, but must never move the player
    # into an unloaded collider or a visual-only HLOD proxy.
    world.call("_fast_travel")
    if not stream.is_cell_pinned(OUTPOST_CELL):
        _fail("F7 did not pin its missing destination")
        return
    var before := Vector2(player.global_position.x, player.global_position.z)
    if before.distance_to(HOME_POS) > 0.1:
        _fail("F7 teleported before full terrain was loaded")
        return
    if not await _wait_loaded(stream, OUTPOST_CELL):
        _fail("distant outpost could not load from its manual pin")
        return
    for i in range(3):
        await physics_frame

    world.call("_fast_travel")
    var at_outpost := Vector2(player.global_position.x, player.global_position.z)
    if at_outpost.distance_to(OUTPOST_POS) > 0.1:
        _fail("F7 did not teleport to the fully loaded outpost")
        return
    if stream.is_cell_pinned(OUTPOST_CELL):
        _fail("completed travel did not release the destination pin")
        return
    if not stream.is_cell_loaded(OUTPOST_CELL):
        _fail("outpost terrain unloaded during the teleport")
        return

    # The same control can prepare and travel home again without keeping a
    # second permanent streaming radius active in the distant region.
    world.call("_fast_travel")
    if not stream.is_cell_pinned(HOME_CELL):
        _fail("return journey did not pin the home destination")
        return
    if not await _wait_loaded(stream, HOME_CELL):
        _fail("home terrain was not prepared for return")
        return
    for i in range(3):
        await physics_frame
    world.call("_fast_travel")
    var returned := Vector2(player.global_position.x, player.global_position.z)
    if returned.distance_to(HOME_POS) > 0.1:
        _fail("return fast travel did not restore home position")
        return
    if stream.get_pinned_cell_count() != 0:
        _fail("fast travel leaked destination residency pins")
        return

    print("Fast-travel smoke PASSED: F6 pin/release, F7 safe remote destination staging, terrain residency and return")
    quit(0)
