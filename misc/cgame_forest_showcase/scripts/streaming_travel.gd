extends Node
## Nonblocking travel gate: keep the player in the current safe world until
## the native WorldPartition3D has instantiated its target scene and passed
## its bounded physics-frame delay plus optional scene activation check.
## It is not a complete collision/navmesh/GPU residency guarantee.
signal travel_completed(destination: Vector3)
signal travel_failed(reason: String)

const SOURCE_NAME: String = "fast_travel"
const STREAMING_PRIORITY: int = 3 # Urgent, but still behind observer/pinned cells.
const TIMEOUT_SECONDS: float = 10.0

var streamer: WorldPartition3D
var player: CharacterBody3D
var terrain_height: Callable
var active: bool = false
var destination: Vector3 = Vector3.ZERO
var destination_name: String = ""
var elapsed: float = 0.0
var last_message: String = "Готово"


func _ready() -> void:
    set_process(false)


func configure(world: WorldPartition3D, pawn: CharacterBody3D, height_function: Callable) -> void:
    streamer = world
    player = pawn
    terrain_height = height_function


func request_travel(place: Vector3, label: String = "точка") -> bool:
    if not place.is_finite() or not is_instance_valid(streamer) or not is_instance_valid(player):
        return false
    if active:
        cancel_travel()
    if not streamer.set_streaming_source(SOURCE_NAME, place, 0, STREAMING_PRIORITY):
        last_message = "Источник перехода не зарегистрирован"
        return false

    if streamer.get_streaming_source_cell_count(SOURCE_NAME) == 0:
        # Missing/unregistered destination must never be interpreted as ready.
        streamer.remove_streaming_source(SOURCE_NAME)
        last_message = "Место назначения не зарегистрировано в мире"
        return false

    destination = place
    destination_name = label
    elapsed = 0.0
    active = true
    last_message = "Подготовка: " + destination_name
    # Keep gameplay responsive while destination scenes stream in the background.
    set_process(true)
    return true


func get_progress() -> float:
    if not active or not is_instance_valid(streamer):
        return 0.0
    return streamer.get_streaming_source_activation_progress(SOURCE_NAME)


func get_status_text() -> String:
    if not active:
        return last_message
    var completed: int = streamer.get_streaming_source_loaded_cell_count(SOURCE_NAME)
    var total: int = streamer.get_streaming_source_cell_count(SOURCE_NAME)
    var activated: int = streamer.get_streaming_source_activated_cell_count(SOURCE_NAME)
    var physics_ready: bool = streamer.is_streaming_source_physics_ready(SOURCE_NAME)
    var navigation_ready: bool = streamer.is_streaming_source_navigation_ready(SOURCE_NAME)
    return "Переход в %s: сцены %d/%d, активация %d/%d (%.0f%%), коллизии: %s, NavMesh: %s — F12: отмена" % [
        destination_name, completed, total, activated, total, get_progress() * 100.0,
        "ГОТОВО" if physics_ready else "ОЖИДАНИЕ",
        "ГОТОВО" if navigation_ready else "ОЖИДАНИЕ"]


func cancel_travel() -> void:
    if active:
        _finish(false, "Переход отменён")


func _process(delta: float) -> void:
    if not active:
        return
    if not is_instance_valid(streamer) or not is_instance_valid(player):
        _finish(false, "Переход прерван: мир или игрок удалён")
        return

    if (streamer.is_streaming_source_activation_ready(SOURCE_NAME)
            and streamer.is_streaming_source_physics_ready(SOURCE_NAME)
            and streamer.is_streaming_source_navigation_ready(SOURCE_NAME)):
        # Revalidate the destination and player on the same frame as travel.
        # The demo terrain is one persistent collision mesh (not a streamed
        # terrain system), so this places the pawn above guaranteed ground.
        if not terrain_height.is_valid():
            _finish(false, "Переход прерван: отсутствует поверхность")
            return
        var ground_y: float = float(terrain_height.call(destination.x, destination.z))
        if not is_finite(ground_y):
            _finish(false, "Переход прерван: высота вне диапазона")
            return
        var target: Vector3 = destination
        player.call("teleport_to_ground", target.x, target.z, ground_y)
        streamer.update_streaming()
        _finish(true, "Переход выполнен")
        travel_completed.emit(target)
        return

    if streamer.get_streaming_source_failed_cell_count(SOURCE_NAME) > 0:
        _finish(false, "Ошибка загрузки сцены назначения")
        return

    elapsed += maxf(delta, 0.0)
    if elapsed >= TIMEOUT_SECONDS:
        _finish(false, "Время ожидания сцены истекло")


func _finish(success: bool, message: String) -> void:
    active = false
    set_process(false)
    last_message = message
    if is_instance_valid(streamer):
        streamer.remove_streaming_source(SOURCE_NAME)
    if not success:
        travel_failed.emit(message)
