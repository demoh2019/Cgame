extends RefCounted
## Stateless native/stock-Godot bridge for two geometry LOD tiers.
## 0 = detailed mesh, 1 = cheap proxy; all visual instances are retained.
## Native planner and GDScript fallback use the same strict boundaries.

const MAX_POINTS := 16384
const MAX_VARIANTS := 32
const MAX_COORD := 10000000.0
const MAX_DISTANCE := 1000000.0

static var _native_checked := false
static var _native: Object = null


static func _engine() -> Object:
    if not _native_checked:
        _native_checked = true
        if ClassDB.class_exists("PCGFoliageScalability3D"):
            var candidate: Object = ClassDB.instantiate("PCGFoliageScalability3D")
            if candidate != null and candidate.has_method("plan_instance_lods") and \
                    candidate.has_method("partition_variant_lods"):
                _native = candidate
    return _native


static func _finite_point(value: Vector3) -> bool:
    return value.is_finite() and absf(value.x) <= MAX_COORD and \
        absf(value.y) <= MAX_COORD and absf(value.z) <= MAX_COORD


static func _plan_fallback(positions: PackedVector3Array, viewer: Vector3,
        previous_tiers: PackedInt32Array, switch_distance: float,
        hysteresis: float) -> PackedInt32Array:
    var result := PackedInt32Array()
    if positions.size() > MAX_POINTS or not _finite_point(viewer) or \
            (not previous_tiers.is_empty() and \
            previous_tiers.size() != positions.size()) or \
            not is_finite(switch_distance) or not is_finite(hysteresis) or \
            switch_distance < 0.1 or switch_distance > MAX_DISTANCE or \
            hysteresis < 0.0 or hysteresis >= switch_distance or \
            switch_distance + hysteresis > MAX_DISTANCE:
        return result
    for i in positions.size():
        if not _finite_point(positions[i]) or (not previous_tiers.is_empty() and \
                previous_tiers[i] != 0 and previous_tiers[i] != 1):
            return result
    var switch_squared: float = switch_distance * switch_distance
    var to_far_squared: float = (switch_distance + hysteresis) * (switch_distance + hysteresis)
    var to_near_squared: float = (switch_distance - hysteresis) * (switch_distance - hysteresis)
    result.resize(positions.size())
    for i in positions.size():
        var distance_squared: float = positions[i].distance_squared_to(viewer)
        var tier: int = previous_tiers[i] if not previous_tiers.is_empty() else \
            (1 if distance_squared > switch_squared else 0)
        if tier == 0 and distance_squared > to_far_squared:
            tier = 1
        elif tier == 1 and distance_squared < to_near_squared:
            tier = 0
        result[i] = tier
    return result


static func plan_instance_lods(positions: PackedVector3Array, viewer: Vector3,
        previous_tiers: PackedInt32Array,
        switch_distance: float = 24.0, hysteresis: float = 3.0,
        prefer_native: bool = true) -> PackedInt32Array:
    if prefer_native:
        var native: Object = _engine()
        if native != null:
            return native.call("plan_instance_lods", positions, viewer,
                previous_tiers, switch_distance, hysteresis)
    return _plan_fallback(positions, viewer, previous_tiers,
        switch_distance, hysteresis)


static func _partition_fallback(variants: PackedInt32Array,
        lod_tiers: PackedInt32Array, variant_count: int) -> Array:
    var result: Array = []
    if variants.size() != lod_tiers.size() or variants.size() > MAX_POINTS or \
            variant_count < 1 or variant_count > MAX_VARIANTS:
        return result
    for i in variants.size():
        if variants[i] < 0 or variants[i] >= variant_count or \
                lod_tiers[i] < 0 or lod_tiers[i] > 1:
            return result
    for i in range(variant_count * 2):
        result.append(PackedInt32Array())
    for source_index in variants.size():
        var group_index: int = variants[source_index] * 2 + lod_tiers[source_index]
        var group: PackedInt32Array = result[group_index]
        group.append(source_index)
        result[group_index] = group
    return result


static func partition_variant_lods(variants: PackedInt32Array,
        lod_tiers: PackedInt32Array, variant_count: int,
        prefer_native: bool = true) -> Array:
    if prefer_native:
        var native: Object = _engine()
        if native != null:
            return native.call("partition_variant_lods", variants, lod_tiers, variant_count)
    return _partition_fallback(variants, lod_tiers, variant_count)


## Returns one byte per [variant*2 + LOD] group: 1 only if at least
## one source point enters/leaves that GPU batch, 0 if membership unchanged.
## Valid no-change inputs return an array of zeros, not an empty array.
static func plan_dirty_variant_lod_groups(variants: PackedInt32Array,
        previous_tiers: PackedInt32Array, next_tiers: PackedInt32Array,
        variant_count: int, prefer_native: bool = true) -> PackedByteArray:
    var result := PackedByteArray()
    if variants.size() != previous_tiers.size() or \
            variants.size() != next_tiers.size() or \
            variants.size() > MAX_POINTS or \
            variant_count < 1 or variant_count > MAX_VARIANTS:
        return result
    # Validate all input before returning any update flags.
    for i in variants.size():
        if variants[i] < 0 or variants[i] >= variant_count or \
                previous_tiers[i] < 0 or previous_tiers[i] > 1 or \
                next_tiers[i] < 0 or next_tiers[i] > 1:
            return result
    if prefer_native:
        var native: Object = _engine()
        if native != null and native.has_method("plan_dirty_variant_lod_groups"):
            return native.call("plan_dirty_variant_lod_groups", variants,
                previous_tiers, next_tiers, variant_count)
    result.resize(variant_count * 2)
    result.fill(0)
    for i in variants.size():
        if previous_tiers[i] == next_tiers[i]:
            continue
        var offset: int = variants[i] * 2
        result[offset + previous_tiers[i]] = 1
        result[offset + next_tiers[i]] = 1
    return result
