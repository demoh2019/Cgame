extends SceneTree
## Headless world-streamed NPC encounter lifecycle: loaded root accessor,
## bounded spawn, scene unload cleanup, defeat persistence and no respawn.
## cgame --headless --path misc/cgame_forest_showcase --script res://tests/smoke_encounters.gd

const Director = preload("res://scripts/forest_encounters.gd")
const FOREST = "res://cells/forest_cell.tscn"
const CELL: Vector2i = Vector2i(-1, 0)
const MAX_FRAMES: int = 360


func _initialize() -> void:
    call_deferred("_run")


func _height(_x: float, _z: float) -> float:
    return 0.0


func _fail(message: String) -> void:
    push_error("Forest encounters smoke FAILED: " + message)
    quit(1)


func _wait_for_cell(stream: WorldPartition3D, present: bool) -> bool:
    for i in range(MAX_FRAMES):
        if stream.is_cell_loaded(CELL) == present:
            return true
        await process_frame
    return false


func _run() -> void:
    if not ResourceLoader.exists(FOREST):
        _fail("forest cell resource missing")
        return

    var player := Node3D.new()
    root.add_child(player)
    player.global_position = Vector3(-16.0, 1.0, 16.0)
    var stream := WorldPartition3D.new()
    stream.cell_size = 32.0
    stream.load_radius = 0
    stream.unload_radius = 0
    root.add_child(stream)
    stream.observer_path = stream.get_path_to(player)
    stream.set_cell_scene(CELL, FOREST)
    if not await _wait_for_cell(stream, true):
        _fail("forest cell never loaded")
        return

    var cell_root: Node3D = stream.get_cell_instance(CELL)
    if cell_root == null or cell_root.is_queued_for_deletion():
        _fail("native get_cell_instance did not return a live scene root")
        return
    if stream.get_cell_instance(Vector2i(19, 19)) != null:
        _fail("native get_cell_instance returned an unregistered scene")
        return

    var director := Node3D.new()
    director.set_script(Director)
    root.add_child(director)
    director.call("configure", stream, player, Callable(self, "_height"))
    if director.call("get_alive_count") != 1:
        _fail("loaded near cell did not create one deterministic encounter")
        return

    player.global_position.x = 100.0
    stream.update_streaming()
    if not await _wait_for_cell(stream, false):
        _fail("old cell was not unloaded")
        return
    if stream.get_cell_instance(CELL) != null or director.call("get_alive_count") != 0:
        _fail("unloaded cell retained its scene or combat NPC")
        return

    player.global_position.x = -16.0
    if not await _wait_for_cell(stream, true):
        _fail("returning to the cell did not reload it")
        return
    director.call("refresh_encounters")
    if director.call("get_alive_count") != 1:
        _fail("returned cell did not restore its undefeated stalker")
        return
    var enemy: Node = director.get_child(0)
    if enemy == null or enemy.get("encounter_id") != "-1:0":
        _fail("NPC encounter ID is not stable across streaming")
        return

    enemy.call("take_damage", 1)
    enemy.call("take_damage", 1)
    enemy.call("take_damage", 1)
    if director.call("get_alive_count") != 0 or not director.call("is_defeated", CELL):
        _fail("defeated encounter did not update persistent state")
        return
    await process_frame
    director.call("refresh_encounters")
    if director.call("get_alive_count") != 0:
        _fail("defeated stalker respawned after refreshing loaded cells")
        return

    var history: Array = director.call("get_defeated_ids")
    if history.size() != 1 or history[0] != "-1:0":
        _fail("defeat state cannot be serialized reliably")
        return
    director.call("restore_defeated", history)
    if director.call("get_alive_count") != 0:
        _fail("restored defeat history unexpectedly created an enemy")
        return

    print("Forest encounters smoke PASSED: native scene lookup, deterministic spawn, cleanup and persisted victories")
    quit(0)
