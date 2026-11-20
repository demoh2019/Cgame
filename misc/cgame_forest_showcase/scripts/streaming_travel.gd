extends Node
## Nonblocking travel gate: keep the player in the current safe world until
## the native WorldPartition3D has actually instantiated the target cell.
## This checks scene roots, not collision/navmesh bake or GPU residency.
signal travel_completed(destination: Vector3)
signal travel_failed(reason: String)

const SOURCE_NAME: String = "fast_travel"
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
    if not streamer.set_streaming_source(SOURCE_NAME, place, 0):
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
    player.set("movement_enabled", false)
    set_process(true)
    return true


func get_progress() -> float:
    if not active or not is_instance_valid(streamer):
        return 0.0
    return streamer.get_streaming_source_progress(SOURCE_NAME)


func get_status_text() -> String:
    if not active:
        return last_message
    var completed: int = streamer.get_streaming_source_loaded_cell_count(SOURCE_NAME)
    var total: int = streamer.get_streaming_source_cell_count(SOURCE_NAME)
    return "Переход в %s: %d/%d сцен (%.0f%%) — F12: отмена" % [
        destination_name, completed, total, get_progress() * 100.0]


func cancel_travel() -> void:
    if active:
        _finish(false, "Переход отменён")


func _process(delta: float) -> void:
    if not active:
        return
    if not is_instance_valid(streamer) or not is_instance_valid(player):
        _finish(false, "Переход прерван: мир или игрок удалён")
        return

    if streamer.is_streaming_source_ready(SOURCE_NAME):
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
    if is_instance_valid(player):
        player.set("movement_enabled", true)
    if not success:
        travel_failed.emit(message)
