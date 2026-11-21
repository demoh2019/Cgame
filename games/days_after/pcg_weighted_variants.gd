extends RefCounted
## Data-only weighted procedural variant selection for collision-free plants.
## Portable twin of native PCGWeightedVariantSelector, using exactly the same
## unsigned 32-bit avalanche mixer and float32 weight arithmetic.

const MAX_POINTS := 16384
const MAX_VARIANTS := 32
const MAX_STABLE_ID := 2147483647
const HASH_MASK := 0xffffffff
const HASH_DENOM := 4294967296.0

static var _native_checked: bool = false
static var _native: Object = null


static func _choose_fallback(stable_ids: PackedInt64Array,
        weights: PackedFloat32Array, seed: int) -> PackedInt32Array:
    var result := PackedInt32Array()
    if stable_ids.size() > MAX_POINTS or weights.is_empty() or \
            weights.size() > MAX_VARIANTS or seed < 0 or seed > MAX_STABLE_ID:
        return result

    var total: float = 0.0
    var last_positive: int = -1
    for j in weights.size():
        var weight: float = weights[j]
        if not is_finite(weight) or weight < 0.0 or weight > 1000000.0:
            return result
        total += weight
        if weight > 0.0:
            last_positive = j
    if last_positive < 0:
        return result
    for stable_id in stable_ids:
        if stable_id < 0 or stable_id > MAX_STABLE_ID:
            return result

    result.resize(stable_ids.size())
    for i in stable_ids.size():
        var h: int = (int(stable_ids[i]) ^ seed ^ 0x9e3779b9) & HASH_MASK
        # 32-bit multiply and mask exactly emulate the native uint32_t.
        # Each product is less than signed 64-bit max.
        h = ((h ^ (h >> 16)) * 0x045d9f3b) & HASH_MASK
        h = ((h ^ (h >> 16)) * 0x045d9f3b) & HASH_MASK
        h = (h ^ (h >> 16)) & HASH_MASK
        var draw: float = (float(h) + 0.5) * (total / HASH_DENOM)
        var cumulative: float = 0.0
        var variant: int = last_positive
        for j in weights.size():
            cumulative += weights[j]
            if draw < cumulative:
                variant = j
                break
        result[i] = variant
    return result


static func choose_variants(stable_ids: PackedInt64Array,
        weights: PackedFloat32Array, seed: int = 0,
        prefer_native: bool = true) -> PackedInt32Array:
    if seed < 0 or seed > MAX_STABLE_ID:
        return PackedInt32Array()
    if prefer_native:
        if not _native_checked:
            _native_checked = true
            if ClassDB.class_exists("PCGWeightedVariantSelector"):
                var selector: Object = ClassDB.instantiate("PCGWeightedVariantSelector")
                if selector != null and selector.has_method("choose_variants"):
                    _native = selector
        if _native != null:
            return _native.call("choose_variants", stable_ids, weights, seed)
    return _choose_fallback(stable_ids, weights, seed)


## Partition one variant assignment per source point into exact per-mesh
## source-index groups. Empty variants still produce an empty group; invalid
## tail values reject the entire request rather than dropping some meshes.
static func partition_indices(variants: PackedInt32Array,
        variant_count: int, prefer_native: bool = true) -> Array:
    var result: Array = []
    if variant_count < 1 or variant_count > MAX_VARIANTS or \
            variants.size() > MAX_POINTS:
        return result
    for variant in variants:
        if variant < 0 or variant >= variant_count:
            return result
    if prefer_native:
        if not _native_checked:
            # Initializes the same optional native selector already used by
            # choose_variants() without constructing new native objects.
            choose_variants(PackedInt64Array(), PackedFloat32Array([1.0]))
        if _native != null and _native.has_method("partition_indices"):
            return _native.call("partition_indices", variants, variant_count)
    for variant in variant_count:
        result.append(PackedInt32Array())
    for i in variants.size():
        var variant: int = variants[i]
        var indices: PackedInt32Array = result[variant]
        indices.append(i)
        result[variant] = indices
    return result
