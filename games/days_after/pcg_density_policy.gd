extends RefCounted
## Portable twin of native PCGDensitySelector.
## Stable cell IDs, not iteration order, decide whether individual points
## survive a density mask. No RNG stream or gameplay object is modified.

const MAX_POINTS := 16384
const MAX_SELECTED := 4096
const MAX_STABLE_ID := 2147483647
const HASH_MASK := 0xffffffff
const HASH_SCALE := 4294967296.0

static var _native: Object = null
static var _native_checked := false


static func _remap_fallback(densities: PackedFloat32Array, input_min: float,
        input_max: float, output_min: float, output_max: float,
        clamp_input: bool) -> PackedFloat32Array:
    var result := PackedFloat32Array()
    if densities.size() > MAX_POINTS or not is_finite(input_min) or \
            not is_finite(input_max) or not is_finite(output_min) or \
            not is_finite(output_max) or input_min < 0.0 or input_max > 1.0 or \
            input_min >= input_max or output_min < 0.0 or output_min > 1.0 or \
            output_max < 0.0 or output_max > 1.0:
        return result
    for density in densities:
        if not is_finite(density) or density < 0.0 or density > 1.0:
            return result
    var scale: float = (output_max - output_min) / (input_max - input_min)
    result.resize(densities.size())
    for index in range(densities.size()):
        var raw: float = densities[index]
        if clamp_input:
            raw = clampf(raw, input_min, input_max)
        result[index] = clampf(output_min + (raw - input_min) * scale, 0.0, 1.0)
    return result


static func _select_fallback(densities: PackedFloat32Array,
        stable_ids: PackedInt64Array, seed: int, max_selected: int) -> PackedInt32Array:
    var result := PackedInt32Array()
    if densities.size() != stable_ids.size() or densities.size() > MAX_POINTS or \
            seed < 0 or seed > MAX_STABLE_ID or max_selected < 1 or \
            max_selected > MAX_SELECTED:
        return result
    # Validate the entire array before accepting any point (fail-closed).
    for i in range(densities.size()):
        if not is_finite(densities[i]) or densities[i] < 0.0 or \
                densities[i] > 1.0 or stable_ids[i] < 0 or stable_ids[i] > MAX_STABLE_ID:
            return result
    for i in range(densities.size()):
        var density: float = densities[i]
        if density == 0.0:
            continue
        # 32-bit avalanche mixing, with each multiplication masked to
        # uint32. The largest intermediate fits safely into signed int64.
        var value: int = (int(stable_ids[i]) ^ seed ^ 0x9E3779B9) & HASH_MASK
        value = ((value ^ (value >> 16)) * 0x45d9f3b) & HASH_MASK
        value = ((value ^ (value >> 16)) * 0x45d9f3b) & HASH_MASK
        value = (value ^ (value >> 16)) & HASH_MASK
        if density == 1.0 or float(value) < density * HASH_SCALE:
            result.append(i)
            if result.size() >= max_selected:
                break
    return result


static func _get_native() -> Object:
    if not _native_checked:
        _native_checked = true
        if ClassDB.class_exists("PCGDensitySelector"):
            var candidate: Object = ClassDB.instantiate("PCGDensitySelector")
            if candidate != null and candidate.has_method("select_indices") and \
                    candidate.has_method("remap_densities"):
                _native = candidate
    return _native


static func remap_densities(densities: PackedFloat32Array,
        input_min: float = 0.0, input_max: float = 1.0,
        output_min: float = 0.0, output_max: float = 1.0,
        clamp_input: bool = true, prefer_native: bool = true) -> PackedFloat32Array:
    var native: Object = _get_native() if prefer_native else null
    if native != null:
        return native.call("remap_densities", densities, input_min, input_max,
            output_min, output_max, clamp_input)
    return _remap_fallback(densities, input_min, input_max,
        output_min, output_max, clamp_input)


static func select_indices(densities: PackedFloat32Array,
        stable_ids: PackedInt64Array, seed: int = 0,
        max_selected: int = MAX_SELECTED, prefer_native: bool = true) -> PackedInt32Array:
    if seed < 0 or seed > MAX_STABLE_ID:
        return PackedInt32Array()
    var native: Object = _get_native() if prefer_native else null
    if native != null:
        return native.call("select_indices", densities, stable_ids, seed, max_selected)
    return _select_fallback(densities, stable_ids, seed, max_selected)
