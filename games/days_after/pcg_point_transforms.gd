extends RefCounted
## Portable parity twin for native PCGPointTransform3D. Independent stable-ID
## streams provide yaw, horizontal and vertical scale without touching RNG.

const MAX_POINTS := 16384
const MAX_STABLE_ID := 2147483647
const MAX_COORD := 10000000.0
const HASH_MASK := 0xffffffff
const HASH_DENOM := 4294967296.0
const MAX_YAW := 6.283185307179586

static var _native_checked := false
static var _native: Object = null


static func _engine() -> Object:
    if not _native_checked:
        _native_checked = true
        if ClassDB.class_exists("PCGPointTransform3D"):
            var candidate: Object = ClassDB.instantiate("PCGPointTransform3D")
            if candidate != null and candidate.has_method("generate_transforms"):
                _native = candidate
    return _native


static func _unit(stable_id: int, seed: int, salt: int) -> float:
    var h: int = (stable_id ^ seed ^ salt) & HASH_MASK
    h = ((h ^ (h >> 16)) * 0x045d9f3b) & HASH_MASK
    h = ((h ^ (h >> 16)) * 0x045d9f3b) & HASH_MASK
    h = (h ^ (h >> 16)) & HASH_MASK
    return (float(h) + 0.5) / HASH_DENOM


static func _fallback(positions: PackedVector3Array, stable_ids: PackedInt64Array,
        seed: int, max_yaw: float, horizontal_min: float, horizontal_max: float,
        vertical_min: float, vertical_max: float) -> Array:
    var result: Array = []
    if positions.size() != stable_ids.size() or positions.size() > MAX_POINTS or \
            seed < 0 or seed > MAX_STABLE_ID or \
            not is_finite(max_yaw) or max_yaw < 0.0 or max_yaw > MAX_YAW or \
            not is_finite(horizontal_min) or not is_finite(horizontal_max) or \
            not is_finite(vertical_min) or not is_finite(vertical_max) or \
            horizontal_min < 0.01 or horizontal_max > 10.0 or \
            vertical_min < 0.01 or vertical_max > 10.0 or \
            horizontal_min > horizontal_max or vertical_min > vertical_max:
        return result
    for i in positions.size():
        var point: Vector3 = positions[i]
        if not point.is_finite() or absf(point.x) > MAX_COORD or \
                absf(point.y) > MAX_COORD or absf(point.z) > MAX_COORD or \
                stable_ids[i] < 0 or stable_ids[i] > MAX_STABLE_ID:
            return []
    for i in positions.size():
        var stable_id: int = int(stable_ids[i])
        var yaw: float = (_unit(stable_id, seed, 0x9e3779b9) - 0.5) * max_yaw
        var horizontal: float = horizontal_min + \
            _unit(stable_id, seed, 0x7f4a7c15) * (horizontal_max - horizontal_min)
        var vertical: float = vertical_min + \
            _unit(stable_id, seed, 0x94d049bb) * (vertical_max - vertical_min)
        var orientation: Basis = Basis(Vector3.UP, yaw).scaled(
            Vector3(horizontal, vertical, horizontal))
        result.append(Transform3D(orientation, positions[i]))
    return result


static func generate_transforms(positions: PackedVector3Array,
        stable_ids: PackedInt64Array, seed: int = 0,
        max_yaw: float = MAX_YAW, horizontal_min: float = 0.85,
        horizontal_max: float = 1.15, vertical_min: float = 0.85,
        vertical_max: float = 1.15, prefer_native: bool = true) -> Array:
    # Native int is 32-bit; reject rather than wrap a 64-bit script seed.
    if seed < 0 or seed > MAX_STABLE_ID:
        return []
    if prefer_native:
        var native: Object = _engine()
        if native != null:
            return native.call("generate_transforms", positions, stable_ids, seed,
                max_yaw, horizontal_min, horizontal_max, vertical_min, vertical_max)
    return _fallback(positions, stable_ids, seed, max_yaw, horizontal_min,
        horizontal_max, vertical_min, vertical_max)
