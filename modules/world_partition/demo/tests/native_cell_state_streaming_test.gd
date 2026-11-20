extends SceneTree

# This integration test REQUIRES the custom Cgame executable compiled with
# modules/world_partition. The stock Godot CI does not execute this script.
const CELL := Vector2i(0, 0)
const SCENE_PATH := "res://scenes/cell_detail.tscn"
const CHECKPOINT := "user://cgame_native_state_regression.dat"

func _initialize() -> void:
    call_deferred("_run")

func _wait_for_cell(world: Node3D, desired: bool) -> bool:
    for i in 240:
        world.call("update_streaming")
        if bool(world.call("is_cell_loaded", CELL)) == desired:
            return true
        await process_frame
    return false

func _run() -> void:
    if not ClassDB.class_exists("WorldPartition3D"):
        push_error("Native test requires a Cgame build with world_partition.")
        quit(2)
        return

    var observer := Node3D.new()
    observer.name = "StateTestObserver"
    get_root().add_child(observer)

    var world := ClassDB.instantiate("WorldPartition3D") as Node3D
    assert(world != null)
    world.name = "StateTestWorld"
    get_root().add_child(world)
    world.set("cell_size", 128.0)
    world.set("load_radius", 0)
    world.set("unload_radius", 1)
    world.set("observer_path", world.get_path_to(observer))
    world.call("set_cell_scene", CELL, SCENE_PATH)

    assert(await _wait_for_cell(world, true))
    var first := world.call("get_cell_instance", CELL) as Node3D
    assert(first != null)
    assert(first.call("claim_hub_reward"))
    assert(first.call("capture_streaming_state")["reward_claimed"] == true)

    # Move the observer outside the unload radius to destroy the scene.
    observer.position = Vector3(1024, 0, 0)
    assert(await _wait_for_cell(world, false))
    assert(bool(world.call("has_cell_state", CELL)))
    assert(world.call("get_cell_state", CELL)["reward_claimed"] == true)

    # A pinned cell must stream back in even while the camera is far away.
    world.call("pin_cell", CELL)
    assert(await _wait_for_cell(world, true))
    var restored := world.call("get_cell_instance", CELL) as Node3D
    assert(restored.call("capture_streaming_state")["reward_claimed"] == true)
    assert(not restored.call("claim_hub_reward"))

    # Snapshot includes the currently resident scene. Save/loading does not
    # need to reinstantiate any Node or deserialize Object references.
    var snapshot: Dictionary = world.call("snapshot_cell_states")
    assert(snapshot[CELL]["reward_claimed"] == true)
    var output := FileAccess.open(CHECKPOINT, FileAccess.WRITE)
    assert(output != null)
    output.store_var(snapshot, false)
    output.close()

    var input := FileAccess.open(CHECKPOINT, FileAccess.READ)
    assert(input != null)
    var loaded: Variant = input.get_var(false)
    input.close()
    assert(loaded is Dictionary)

    # Omitting a cell record resets an already-active scene.
    world.call("load_cell_states", {})
    assert(restored.call("capture_streaming_state")["reward_claimed"] == false)
    world.call("load_cell_states", loaded)
    assert(restored.call("capture_streaming_state")["reward_claimed"] == true)

    world.set("streaming_enabled", false)
    world.queue_free()
    observer.queue_free()
    await process_frame
    print("Native WorldPartition3D cell state streaming integration passed")
    quit(0)
