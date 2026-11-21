extends RefCounted

# Godot 4 Compatibility-compatible HLOD blend math. Uses time and distance.
const SPAWN_FADE_SECONDS := 0.4

static func _smooth01(value: float) -> float:
    var t := clampf(value, 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)

static func detail_opacity(distance_cells: float, age_seconds: float, near_end: float, far_begin: float) -> float:
    if not is_finite(distance_cells) or not is_finite(age_seconds):
        return 1.0
    if far_begin <= near_end:
        return 1.0
    var distance_weight := 1.0 - _smooth01((distance_cells - near_end) / (far_begin - near_end))
    var spawn_weight := _smooth01(maxf(age_seconds, 0.0) / SPAWN_FADE_SECONDS)
    return clampf(distance_weight * spawn_weight, 0.0, 1.0)
