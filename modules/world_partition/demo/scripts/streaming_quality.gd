extends RefCounted

# Lightweight, renderer-independent quality controller for streaming distance
# and scene instantiation budgets. Uses a time-weighted FPS average, cooldown,
# and a deadband so changing LOD does not oscillate every few frames.
const SAMPLE_SECONDS := 3.0
const COOLDOWN_SECONDS := 10.0
const LOW_FPS := 48.0
const RECOVERY_FPS := 58.0

const PROFILES := [
    {"name": "Performance", "detail_load": 1, "detail_unload": 2, "proxy_load": 2, "proxy_unload": 3, "detail_budget": 1, "proxy_budget": 1, "unload_budget": 8},
    {"name": "Balanced", "detail_load": 1, "detail_unload": 2, "proxy_load": 4, "proxy_unload": 5, "detail_budget": 2, "proxy_budget": 1, "unload_budget": 16},
    {"name": "Cinematic", "detail_load": 2, "detail_unload": 3, "proxy_load": 5, "proxy_unload": 6, "detail_budget": 3, "proxy_budget": 2, "unload_budget": 32},
]

var level: int = 1
var automatic: bool = true
var _sample_time := 0.0
var _weighted_fps := 0.0
var _cooldown_left := 0.0

func get_profile() -> Dictionary:
    return PROFILES[level].duplicate()

func set_level(new_level: int) -> bool:
    var target: int = clampi(new_level, 0, PROFILES.size() - 1)
    if target == level:
        return false
    level = target
    _sample_time = 0.0
    _weighted_fps = 0.0
    _cooldown_left = COOLDOWN_SECONDS
    return true

func reset_sampling() -> void:
    _sample_time = 0.0
    _weighted_fps = 0.0
    _cooldown_left = 0.0

func sample(delta: float, fps: float) -> bool:
    if not automatic or not is_finite(delta) or delta <= 0.0 or not is_finite(fps) or fps < 0.0:
        return false
    if _cooldown_left > 0.0:
        _cooldown_left = maxf(_cooldown_left - delta, 0.0)
        return false

    _sample_time += delta
    _weighted_fps += fps * delta
    if _sample_time < SAMPLE_SECONDS:
        return false

    var average := _weighted_fps / _sample_time
    _sample_time = 0.0
    _weighted_fps = 0.0
    if average < LOW_FPS:
        return set_level(level - 1)
    if average >= RECOVERY_FPS:
        return set_level(level + 1)
    return false
