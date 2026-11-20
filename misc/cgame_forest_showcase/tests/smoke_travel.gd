extends SceneTree
## Headless fast-travel integration: no position change until destination scene
## is instantiated, plus cancellation, missing scenes and timeout behavior.
## cgame --headless --path misc/cgame_forest_showcase --script res://tests/smoke_travel.gd

const Explorer = preload("res://scripts/explorer_character.gd")
const Travel = preload("res://scripts/streaming_travel.gd")
const FOREST = "res://cells/forest_cell.tscn"
const MAX_FRAMES = 360

var completed_count: int = 0
var failed_count: int = 0


func _initialize() -> void:
    call_deferred("_run")


func _height(_x: float, _z: float) -> float:
    return 0.0


func _on_complete(_where: Vector3) -> void:
    completed_count += 1


func _on_failed(_reason: String) -> void:
    failed_count += 1


func _fail(reason: String) -> void:
    push_error("Forest streaming travel smoke FAILED: " + reason)
    quit(1)


func _wait_loaded(stream: WorldPartition3D, cell: Vector2i) -> bool:
    for i in range(MAX_FRAMES):
        if stream.get_cell_instance(cell) != null:
            return true
        await process_frame
    return false


func _wait_travel(travel: Node) -> bool:
    for i in range(MAX_FRAMES):
        if not travel.active:
            return true
        await process_frame
    return false


func _run() -> void:
    if not ResourceLoader.exists(FOREST):
        _fail("forest cell resource missing")
        return

    var pawn := CharacterBody3D.new()
    pawn.set_script(Explorer)
    root.add_child(pawn)
    pawn.call("teleport_to_ground", 0.0, 9.0, 0.0)

    var world := WorldPartition3D.new()
    world.cell_size = 32.0
    world.load_radius = 0
    world.unload_radius = 0
    world.max_new_requests_per_frame = 1
    world.max_instances_per_frame = 1
    root.add_child(world)
    world.observer_path = world.get_path_to(pawn)
    world.set_cell_scene(Vector2i(0, 0), FOREST)
    world.set_cell_scene(Vector2i(3, 0), FOREST)
    if not await _wait_loaded(world, Vector2i.ZERO):
        _fail("initial observer cell not loaded")
        return

    var travel := Travel.new()
    root.add_child(travel)
    travel.configure(world, pawn, Callable(self, "_height"))
    travel.travel_completed.connect(_on_complete)
    travel.travel_failed.connect(_on_failed)
    if not travel.request_travel(Vector3(96.0, 0.0, 0.0), "восточная опушка"):
        _fail("valid destination was rejected")
        return
    if completed_count != 0 or not travel.active or absf(pawn.global_position.x) > 0.01:
        _fail("teleported before remote scene became ready")
        return
    if world.get_streaming_source_cell_count(Travel.SOURCE_NAME) != 1:
        _fail("travel source did not register its destination scene")
        return
    if not await _wait_travel(travel):
        _fail("travel did not complete under streaming budgets")
        return
    if completed_count != 1 or absf(pawn.global_position.x - 96.0) > 0.01:
        _fail("ready destination did not trigger exact teleport")
        return
    if world.has_streaming_source(Travel.SOURCE_NAME):
        _fail("travel source was not removed after arrival")
        return

    # A cancellation must leave the pawn at its existing location.
    world.set_cell_scene(Vector2i(-3, 0), FOREST)
    if not travel.request_travel(Vector3(-96.0, 0.0, 0.0), "запад"):
        _fail("second destination failed to stage")
        return
    travel.cancel_travel()
    if travel.active or world.has_streaming_source(Travel.SOURCE_NAME):
        _fail("canceled travel retained active source")
        return
    if absf(pawn.global_position.x - 96.0) > 0.01:
        _fail("cancel unexpectedly moved the player")
        return
    if failed_count != 1:
        _fail("cancel did not emit failure signal")
        return

    if travel.request_travel(Vector3(256.0, 0.0, 0.0), "неизвестное место"):
        _fail("unregistered destination must be rejected synchronously")
        return
    if world.has_streaming_source(Travel.SOURCE_NAME) or absf(pawn.global_position.x - 96.0) > 0.01:
        _fail("invalid destination affected position or retained source")
        return

    # A corrupt/missing PackedScene is a valid registered address but must
    # never trigger teleport. Timeout is simulated deterministically.
    world.set_cell_scene(Vector2i(-3, 0), "res://cells/no_such_scene.tscn")
    if not travel.request_travel(Vector3(-96.0, 0.0, 0.0), "ошибка"):
        _fail("registered source should enter pending state")
        return
    travel._process(Travel.TIMEOUT_SECONDS + 1.0)
    if travel.active or completed_count != 1 or failed_count != 2:
        _fail("failed/expired travel did not settle exactly once")
        return
    if world.has_streaming_source(Travel.SOURCE_NAME) or absf(pawn.global_position.x - 96.0) > 0.01:
        _fail("failed travel moved player or leaked streaming source")
        return

    print("Forest streaming travel smoke PASSED: async readiness, completed jump, cancellation, invalid destination and timeout")
    quit(0)
