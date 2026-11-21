extends MultiMeshInstance3D
## Visual trail stones generated with the same waypoints as foliage masks.
## Cgame uses PCGPolylineSampler3D, stock Godot uses exact GDScript parity.
## Decorative only: collisions, navigation and survival state are untouched.

const SAMPLE_SPACING: float = 1.35
const MAX_SAMPLES: int = 192
const STRUCTURE_CLEARANCE: float = 0.5

var _waypoints := PackedVector3Array()
var _raw_samples := PackedVector3Array()
var _selected_positions := PackedVector3Array()
var _exclusion_mins := PackedVector3Array()
var _exclusion_maxs := PackedVector3Array()


func configure(route: PackedVector3Array,
        box_mins: PackedVector3Array, box_maxs: PackedVector3Array) -> void:
    _waypoints = route.duplicate()
    _exclusion_mins = box_mins.duplicate()
    _exclusion_maxs = box_maxs.duplicate()


func _ready() -> void:
    regenerate()


func get_path_points() -> PackedVector3Array:
    return _waypoints.duplicate()


func get_raw_samples() -> PackedVector3Array:
    return _raw_samples.duplicate()


func get_selected_positions() -> PackedVector3Array:
    return _selected_positions.duplicate()


func _sample_fallback() -> PackedVector3Array:
    var result := PackedVector3Array()
    if _waypoints.is_empty():
        return result
    var lengths := PackedFloat64Array()
    var total: float = 0.0
    for i in range(_waypoints.size() - 1):
        var length: float = _waypoints[i].distance_to(_waypoints[i + 1])
        lengths.push_back(length)
        total += length
    if total == 0.0:
        result.push_back(_waypoints[0])
        return result
    var intervals: int = ceili(total / SAMPLE_SPACING)
    if intervals + 1 > MAX_SAMPLES:
        return result
    var segment: int = 0
    var previous_length: float = 0.0
    for i in range(intervals + 1):
        if i == intervals:
            result.push_back(_waypoints[_waypoints.size() - 1])
            continue
        var target: float = total * float(i) / float(intervals)
        while (segment < lengths.size() - 1
                and target > previous_length + lengths[segment]):
            previous_length += lengths[segment]
            segment += 1
        var t: float = 0.0
        if lengths[segment] > 0.0:
            t = clampf((target - previous_length) / lengths[segment], 0.0, 1.0)
        result.push_back(_waypoints[segment].lerp(_waypoints[segment + 1], t))
    return result


func _sample_points(prefer_native: bool = true) -> PackedVector3Array:
    if prefer_native and ClassDB.class_exists("PCGPolylineSampler3D"):
        var sampler: Object = ClassDB.instantiate("PCGPolylineSampler3D")
        if sampler != null and sampler.has_method("sample_positions"):
            return sampler.call("sample_positions", _waypoints,
                SAMPLE_SPACING, MAX_SAMPLES, true)
    return _sample_fallback()


func verify_native_fallback_parity() -> bool:
    var a: PackedVector3Array = _sample_points()
    var b: PackedVector3Array = _sample_points(false)
    if a.size() != b.size():
        return false
    for i in range(a.size()):
        if a[i].distance_to(b[i]) > 0.001:
            return false
    return true


func _inside_structure(point: Vector3) -> bool:
    for i in range(_exclusion_mins.size()):
        var lo: Vector3 = _exclusion_mins[i]
        var hi: Vector3 = _exclusion_maxs[i]
        # Reserve mesh half-extents in XZ; stones can rotate at corners.
        if (point.x >= lo.x - STRUCTURE_CLEARANCE
                and point.x <= hi.x + STRUCTURE_CLEARANCE
                and point.y >= lo.y and point.y <= hi.y
                and point.z >= lo.z - STRUCTURE_CLEARANCE
                and point.z <= hi.z + STRUCTURE_CLEARANCE):
            return true
    return false


func regenerate() -> void:
    _raw_samples = _sample_points()
    _selected_positions.clear()
    var kept_indices := PackedInt32Array()
    for i in range(_raw_samples.size()):
        if not _inside_structure(_raw_samples[i]):
            _selected_positions.push_back(_raw_samples[i])
            kept_indices.push_back(i)

    var stone := BoxMesh.new()
    stone.size = Vector3(0.52, 0.055, 0.72)
    var material := StandardMaterial3D.new()
    material.albedo_color = Color(0.50, 0.46, 0.37)
    material.roughness = 1.0
    stone.material = material

    var batch := MultiMesh.new()
    batch.transform_format = MultiMesh.TRANSFORM_3D
    batch.mesh = stone
    batch.instance_count = _selected_positions.size()
    for i in range(_selected_positions.size()):
        var original_index: int = kept_indices[i]
        var forward := Vector3.FORWARD
        if original_index + 1 < _raw_samples.size():
            forward = _raw_samples[original_index + 1] - _raw_samples[original_index]
        elif original_index > 0:
            forward = _raw_samples[original_index] - _raw_samples[original_index - 1]
        forward.y = 0.0
        if forward.length_squared() < 0.000001:
            forward = Vector3.FORWARD
        var direction: float = atan2(forward.x, forward.z)
        var basis := Basis(Vector3.UP, direction)
        batch.set_instance_transform(i, Transform3D(
            basis, _selected_positions[i] + Vector3(0.0, 0.045, 0.0)))
    multimesh = batch
    cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
