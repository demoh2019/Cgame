extends MultiMeshInstance3D
## Visual trail stones generated with the same waypoints as foliage masks.
## Cgame samples path-aligned Transform3D frames, stock Godot mirrors the math.
## Decorative only: collisions, navigation and survival state are untouched.

const SAMPLE_SPACING: float = 1.35
const MAX_SAMPLES: int = 192
const STRUCTURE_CLEARANCE: float = 0.5

var _waypoints := PackedVector3Array()
var _raw_samples := PackedVector3Array()
var _raw_frames: Array = []
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


func get_raw_frames() -> Array:
    return _raw_frames.duplicate()


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


func _sample_frames_fallback() -> Array:
    var positions: PackedVector3Array = _sample_fallback()
    var frames: Array = []
    for i in range(positions.size()):
        var previous: int = maxi(0, i - 1)
        var next: int = mini(positions.size() - 1, i + 1)
        var tangent: Vector3 = positions[next] - positions[previous]
        if tangent.length_squared() <= 1.0e-12:
            if i + 1 < positions.size():
                tangent = positions[i + 1] - positions[i]
            if tangent.length_squared() <= 1.0e-12 and i > 0:
                tangent = positions[i] - positions[i - 1]
        if tangent.length_squared() <= 1.0e-12:
            for seg in range(1, _waypoints.size()):
                tangent = _waypoints[seg] - _waypoints[seg - 1]
                if tangent.length_squared() > 1.0e-12:
                    break
        if tangent.length_squared() <= 1.0e-12:
            tangent = Vector3(0.0, 0.0, 1.0)
        tangent = tangent.normalized()
        var reference_up := Vector3(0.0, 0.0, 1.0) if absf(tangent.y) >= 0.98 else Vector3.UP
        var right: Vector3 = reference_up.cross(tangent).normalized()
        var up: Vector3 = tangent.cross(right).normalized()
        frames.push_back(Transform3D(Basis(right, up, tangent), positions[i]))
    return frames


func _sample_frames(prefer_native: bool = true) -> Array:
    if prefer_native and ClassDB.class_exists("PCGPolylineSampler3D"):
        var sampler: Object = ClassDB.instantiate("PCGPolylineSampler3D")
        if sampler != null and sampler.has_method("sample_transforms"):
            return sampler.call("sample_transforms", _waypoints,
                SAMPLE_SPACING, MAX_SAMPLES, true)
    return _sample_frames_fallback()


func verify_native_fallback_parity() -> bool:
    var positions_native: PackedVector3Array = _sample_points()
    var positions_fallback: PackedVector3Array = _sample_points(false)
    var native_frames: Array = _sample_frames()
    var fallback_frames: Array = _sample_frames_fallback()
    if (positions_native.size() != positions_fallback.size()
            or native_frames.size() != fallback_frames.size()
            or native_frames.size() != positions_native.size()):
        return false
    for i in range(native_frames.size()):
        var a: Transform3D = native_frames[i]
        var b: Transform3D = fallback_frames[i]
        if (positions_native[i].distance_to(positions_fallback[i]) > 0.001
                or a.origin.distance_to(b.origin) > 0.001
                or a.basis.x.distance_to(b.basis.x) > 0.002
                or a.basis.y.distance_to(b.basis.y) > 0.002
                or a.basis.z.distance_to(b.basis.z) > 0.002):
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
    _raw_frames = _sample_frames()
    _raw_samples.clear()
    for frame in _raw_frames:
        var point_frame: Transform3D = frame
        _raw_samples.push_back(point_frame.origin)
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
        var frame: Transform3D = _raw_frames[original_index]
        # Use native tangent orientation; offset slightly from the ground,
        # but never add physics or a scene node per marker.
        batch.set_instance_transform(i, Transform3D(
            frame.basis, frame.origin + Vector3(0.0, 0.045, 0.0)))
    multimesh = batch
    cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
