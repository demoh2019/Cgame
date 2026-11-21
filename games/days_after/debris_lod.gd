extends Node3D
## Optional visual-only LOD. No gameplay colliders, interaction or AI are culled.
## Native view-cone SignificanceBudgetPlanner on Cgame, stock Godot fallback.

const FRAGMENT_COUNT: int = 96
const VISIBLE_BUDGET: int = 18
const MAX_DISTANCE: float = 26.0
const HYSTERESIS: float = 2.0
const UPDATE_INTERVAL: float = 0.2
const VIEW_HALF_ANGLE: float = 75.0
const NEAR_KEEP_RADIUS: float = 5.5

var _viewer: Node3D
var _planner: Object
var _fragments: Array[MeshInstance3D] = []
var _positions := PackedVector3Array()
var _priorities := PackedByteArray()
var _ids := PackedInt64Array()
var _retained_ids := PackedInt64Array()
var _selected_indices := PackedInt32Array()
var _elapsed: float = 0.0


func _ready() -> void:
    if ClassDB.class_exists("SignificanceBudgetPlanner"):
        _planner = ClassDB.instantiate("SignificanceBudgetPlanner")
    var shared_mesh := BoxMesh.new()
    shared_mesh.size = Vector3(0.3, 0.17, 0.5)
    var shared_material := StandardMaterial3D.new()
    shared_material.albedo_color = Color(0.35, 0.37, 0.35)
    shared_material.roughness = 1.0

    for index in range(FRAGMENT_COUNT):
        var angle := float(index) * 2.399963229728653
        var radius := 4.0 + sqrt(float(index)) * 2.15
        var local_pos := Vector3(cos(angle) * radius, 0.09, sin(angle) * radius - 5.0)
        var fragment := MeshInstance3D.new()
        fragment.name = "Rubble%d" % index
        fragment.mesh = shared_mesh
        fragment.material_override = shared_material
        fragment.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
        fragment.rotation.y = angle
        fragment.position = local_pos
        fragment.visible = false
        add_child(fragment)
        _fragments.append(fragment)
        _positions.push_back(local_pos)
        _priorities.push_back(1 if index % 13 == 0 else 0)
        _ids.push_back(index + 1)
    force_refresh()


func set_viewer(viewer: Node3D) -> void:
    _viewer = viewer
    force_refresh()


func _process(delta: float) -> void:
    _elapsed += maxf(0.0, delta)
    if _elapsed >= UPDATE_INTERVAL:
        _elapsed = 0.0
        force_refresh()


func _get_view_state() -> Dictionary:
    var origin: Vector3 = to_local(_viewer.global_position)
    var world_forward: Vector3 = -_viewer.global_transform.basis.z
    var camera := _viewer.get_node_or_null("Camera3D") as Camera3D
    if camera != null:
        origin = to_local(camera.global_position)
        world_forward = -camera.global_transform.basis.z
    var forward: Vector3 = (
        to_local(to_global(origin) + world_forward) - origin).normalized()
    return {"origin": origin, "forward": forward}


func get_view_state() -> Dictionary:
    if not is_instance_valid(_viewer):
        return {}
    return _get_view_state()


func get_source_positions() -> PackedVector3Array:
    return _positions.duplicate()


func get_selected_indices() -> PackedInt32Array:
    return _selected_indices.duplicate()


func get_view_cone_parameters() -> Vector3:
    return Vector3(VIEW_HALF_ANGLE, NEAR_KEEP_RADIUS, MAX_DISTANCE)


func _select_native(viewer_position: Vector3, direction: Vector3) -> PackedInt32Array:
    return _planner.call("select_world_priority_stable_cone", _positions,
        viewer_position, direction, _priorities, _ids, _retained_ids,
        VISIBLE_BUDGET, MAX_DISTANCE, HYSTERESIS, VIEW_HALF_ANGLE, NEAR_KEEP_RADIUS)


func force_refresh() -> void:
    if not is_instance_valid(_viewer) or _fragments.is_empty():
        return
    var view: Dictionary = _get_view_state()
    var viewer_position: Vector3 = view["origin"]
    var direction: Vector3 = view["forward"]
    var selected := PackedInt32Array()
    if _planner != null and _planner.has_method("select_world_priority_stable_cone"):
        selected = _select_native(viewer_position, direction)
    else:
        selected = _select_fallback(viewer_position, direction)
    _selected_indices = selected.duplicate()
    var next_retained := PackedInt64Array()
    var enabled := {}
    for index in selected:
        if index >= 0 and index < _fragments.size():
            next_retained.push_back(_ids[index])
            enabled[index] = true
    _retained_ids = next_retained
    for index in range(_fragments.size()):
        _fragments[index].visible = enabled.has(index)


func _select_fallback(viewer_position: Vector3, direction: Vector3) -> PackedInt32Array:
    var ranked: Array[Dictionary] = []
    var cos_limit: float = cos(deg_to_rad(VIEW_HALF_ANGLE))
    var normalized: Vector3 = direction.normalized()
    var near_squared: float = NEAR_KEEP_RADIUS * NEAR_KEEP_RADIUS
    for index in range(_fragments.size()):
        var offset: Vector3 = _positions[index] - viewer_position
        var distance_squared: float = offset.length_squared()
        var distance: float = sqrt(distance_squared)
        if distance > MAX_DISTANCE:
            continue
        if distance_squared > near_squared and (
                offset.dot(normalized) / distance < cos_limit):
            continue
        ranked.append({
            "index": index,
            "priority": int(_priorities[index]),
            "distance": distance,
            "adjusted": maxf(0.0, distance - (HYSTERESIS if _retained_ids.has(_ids[index]) else 0.0)),
            "id": _ids[index],
        })
    ranked.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
        if a["priority"] != b["priority"]:
            return a["priority"] > b["priority"]
        if a["adjusted"] != b["adjusted"]:
            return a["adjusted"] < b["adjusted"]
        if a["distance"] != b["distance"]:
            return a["distance"] < b["distance"]
        return a["id"] < b["id"]
    )
    var output := PackedInt32Array()
    for rank in range(mini(VISIBLE_BUDGET, ranked.size())):
        output.push_back(int(ranked[rank]["index"]))
    return output


func verify_native_fallback_parity() -> bool:
    if not is_instance_valid(_viewer):
        return false
    var state: Dictionary = _get_view_state()
    var origin: Vector3 = state["origin"]
    var forward: Vector3 = state["forward"]
    var fallback: PackedInt32Array = _select_fallback(origin, forward)
    if _planner == null or not _planner.has_method("select_world_priority_stable_cone"):
        return _selected_indices == fallback
    return _select_native(origin, forward) == fallback


func get_visible_count() -> int:
    var count: int = 0
    for fragment in _fragments:
        if fragment.visible:
            count += 1
    return count
