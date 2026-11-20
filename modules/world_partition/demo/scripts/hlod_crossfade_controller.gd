extends Node

# Owns visual HLOD transitions, not scene residency. Both streamers keep their
# own budgets and lifetimes, and the camera decides which loaded tier is visible.
const Blend = preload("res://scripts/hlod_blend.gd")
const CELL_SIZE := 128.0
const UPDATE_INTERVAL := 1.0 / 30.0

var near_streamer: Node3D
var far_streamer: Node3D
var target_camera: Camera3D
var enabled := true
var _elapsed := 0.0
var _cell_ages: Dictionary = {}
var _last_weights: Dictionary = {}

func _ready() -> void:
    if near_streamer == null or far_streamer == null or target_camera == null:
        push_error("HLOD crossfade requires detail, proxy and camera references.")
        set_process(false)
        return
    near_streamer.connect("cell_loaded", Callable(self, "_on_near_loaded"))
    near_streamer.connect("cell_unloaded", Callable(self, "_on_near_unloaded"))
    far_streamer.connect("cell_loaded", Callable(self, "_on_far_loaded"))
    far_streamer.connect("cell_unloaded", Callable(self, "_on_far_unloaded"))

func set_transition_enabled(value: bool) -> void:
    if enabled == value:
        return
    enabled = value
    _last_weights.clear()
    _synchronize(0.0)

func _on_near_loaded(cell: Vector2i) -> void:
    _cell_ages[cell] = 0.0
    _last_weights.erase(cell)
    _sync_cell(cell)

func _on_near_unloaded(cell: Vector2i) -> void:
    _cell_ages.erase(cell)
    _last_weights.erase(cell)
    # If the camera teleported past the fade margin, restore the proxy
    # immediately rather than showing empty space.
    _sync_cell(cell)

func _on_far_loaded(cell: Vector2i) -> void:
    _last_weights.erase(cell)
    _sync_cell(cell)

func _on_far_unloaded(cell: Vector2i) -> void:
    _last_weights.erase(cell)
    _sync_cell(cell)

func _process(delta: float) -> void:
    _elapsed += delta
    if _elapsed < UPDATE_INTERVAL:
        return
    _synchronize(_elapsed)
    _elapsed = 0.0

func _synchronize(delta: float) -> void:
    if near_streamer == null:
        return
    var cells: Array = near_streamer.call("get_loaded_cells")
    for entry in cells:
        var cell: Vector2i = entry
        var age: float = float(_cell_ages.get(cell, Blend.SPAWN_FADE_SECONDS))
        _cell_ages[cell] = minf(age + delta, Blend.SPAWN_FADE_SECONDS)
        _sync_cell(cell)

func _camera_distance_in_cells(cell: Vector2i) -> float:
    var camera_pos: Vector3 = near_streamer.to_local(target_camera.global_position)
    var x: float = camera_pos.x / CELL_SIZE
    var z: float = camera_pos.z / CELL_SIZE
    # Continuous Chebyshev distance to cell center avoids snapping to grid.
    return maxf(absf(float(cell.x) + 0.5 - x), absf(float(cell.y) + 0.5 - z))

func _set_scene_opacity(root: Node3D, opacity: float) -> void:
    var transparency := 1.0 - clampf(opacity, 0.0, 1.0)
    var queue: Array[Node] = [root]
    while not queue.is_empty():
        var item: Node = queue.pop_back()
        if item is GeometryInstance3D:
            (item as GeometryInstance3D).transparency = transparency
        for child in item.get_children():
            queue.push_back(child)

func _sync_cell(cell: Vector2i) -> void:
    if near_streamer == null or far_streamer == null:
        return
    var near := near_streamer.call("get_cell_instance", cell) as Node3D
    var far := far_streamer.call("get_cell_instance", cell) as Node3D
    var has_near := is_instance_valid(near)
    var has_far := is_instance_valid(far)
    if not has_near and not has_far:
        _last_weights.erase(cell)
        return
    if not has_near:
        _last_weights.erase(cell)
        far.visible = true
        _set_scene_opacity(far, 1.0)
        return
    if not has_far:
        _last_weights.erase(cell)
        near.visible = true
        _set_scene_opacity(near, 1.0)
        return

    var weight := 1.0
    if enabled:
        var near_end: float = float(near_streamer.get("load_radius")) + 0.25
        var far_begin: float = float(near_streamer.get("unload_radius")) + 0.25
        var age: float = float(_cell_ages.get(cell, Blend.SPAWN_FADE_SECONDS))
        weight = Blend.detail_opacity(_camera_distance_in_cells(cell), age, near_end, far_begin)

    # Static cells incur no repeated transparency writes.
    if _last_weights.has(cell) and is_equal_approx(float(_last_weights[cell]), weight):
        return
    _last_weights[cell] = weight
    near.visible = weight > 0.001
    far.visible = weight < 0.999
    if near.visible:
        _set_scene_opacity(near, weight)
    if far.visible:
        _set_scene_opacity(far, 1.0 - weight)
