extends RefCounted
## Optional native AI stimulus memory used by server-authoritative infected.
## The existing sight, hearing, wind, cover, safe-zone, and threat rules decide
## whether a stimulus is valid. This adapter records only accepted signals.
## It also works on stock Godot, which lacks the custom Cgame native classes.

const DEFAULT_SIGHT_MEMORY := 6.0
const DEFAULT_SOUND_MEMORY := 3.5

var _vision: Variant = null
var _hearing: Variant = null


func _init() -> void:
    if ClassDB.class_exists("AIVisualSensor2D"):
        _vision = ClassDB.instantiate("AIVisualSensor2D")
        if _vision != null:
            _vision.set_field_of_view_degrees(360.0)
            _vision.set_memory_duration(DEFAULT_SIGHT_MEMORY)
    if ClassDB.class_exists("AIHearingSensor2D"):
        _hearing = ClassDB.instantiate("AIHearingSensor2D")
        if _hearing != null:
            _hearing.set_memory_duration(DEFAULT_SOUND_MEMORY)


func has_native_vision() -> bool:
    return _vision != null


func has_native_hearing() -> bool:
    return _hearing != null


func record_confirmed_sight(observer: Vector2, position: Vector2, radius: float,
        visible: bool, delta: float) -> void:
    if _vision == null or not observer.is_finite() or not position.is_finite():
        return
    if not is_finite(radius) or radius <= 0.0:
        return
    _vision.set_sight_radius(radius)
    _vision.set_lose_sight_radius(radius)
    # Already authoritative cover/visibility is passed in by infected_sight.gd.
    _vision.observe(observer, Vector2.RIGHT, position, visible, maxf(delta, 0.0))


func record_confirmed_sound(listener: Vector2, source: Vector2, radius: float) -> bool:
    if _hearing == null or not listener.is_finite() or not source.is_finite():
        return false
    if not is_finite(radius) or radius <= 0.0:
        return false
    _hearing.set_hearing_radius(radius)
    # InfectedHearing.audible() has already checked occlusion, wind, and noise.
    return bool(_hearing.report_noise(listener, source, 1.0))


func advance_time(delta: float) -> void:
    if _vision != null:
        _vision.advance_time(maxf(delta, 0.0))
    if _hearing != null:
        _hearing.advance_time(maxf(delta, 0.0))


func remembers_sight() -> bool:
    return _vision != null and bool(_vision.has_target_memory())


func last_seen_position() -> Vector2:
    if _vision != null and _vision.has_target_memory():
        return _vision.get_last_known_position()
    return Vector2.ZERO


func remembers_sound() -> bool:
    return _hearing != null and bool(_hearing.has_sound_memory())


func last_heard_position() -> Vector2:
    if _hearing != null and _hearing.has_sound_memory():
        return _hearing.get_last_heard_position()
    return Vector2.ZERO


func get_debug_snapshot() -> Dictionary:
    # An on-demand diagnostic view. Do not replicate to ordinary clients:
    # target-memory positions belong to the authoritative server.
    return {
        "native_vision": has_native_vision(),
        "native_hearing": has_native_hearing(),
        "remembers_sight": remembers_sight(),
        "remembers_sound": remembers_sound(),
        "last_seen_position": last_seen_position(),
        "last_heard_position": last_heard_position(),
        "sight_memory_seconds": float(_vision.get_memory_remaining()) if _vision != null else 0.0,
        "sound_memory_seconds": float(_hearing.get_memory_remaining()) if _hearing != null else 0.0,
    }


func reset() -> void:
    if _vision != null:
        _vision.reset()
    if _hearing != null:
        _hearing.reset()
