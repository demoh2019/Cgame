extends RefCounted
## Optional native AI stimulus memory used by server-authoritative infected.
## The existing sight, hearing, wind, cover, safe-zone, and threat rules decide
## whether a stimulus is valid. This adapter records only accepted signals.
## It also works on stock Godot, which lacks the custom Cgame native classes.

const DEFAULT_SIGHT_MEMORY := 6.0
const DEFAULT_SOUND_MEMORY := 3.5

var _vision: Variant = null
var _hearing: Variant = null
var _history: Variant = null
var _ranked_hearing_available: bool = false


func _init() -> void:
    if ClassDB.class_exists("AIVisualSensor2D"):
        _vision = ClassDB.instantiate("AIVisualSensor2D")
        if _vision != null:
            _vision.set_field_of_view_degrees(360.0)
            _vision.set_memory_duration(DEFAULT_SIGHT_MEMORY)
    if ClassDB.class_exists("AIStimulusHistory2D"):
        _history = ClassDB.instantiate("AIStimulusHistory2D")
    if ClassDB.class_exists("AIHearingSensor2D"):
        _hearing = ClassDB.instantiate("AIHearingSensor2D")
        if _hearing != null:
            _hearing.set_memory_duration(DEFAULT_SOUND_MEMORY)
            _ranked_hearing_available = _hearing.has_method("report_noise_ranked")


func has_native_vision() -> bool:
    return _vision != null


func has_native_hearing() -> bool:
    return _hearing != null


func has_ranked_hearing() -> bool:
    return _ranked_hearing_available


func has_native_history() -> bool:
    return _history != null


func record_confirmed_sight(observer: Vector2, position: Vector2, radius: float,
        visible: bool, delta: float, source_id: int = -1) -> void:
    if _vision == null or not observer.is_finite() or not position.is_finite():
        return
    if not is_finite(radius) or radius <= 0.0:
        return
    _vision.set_sight_radius(radius)
    _vision.set_lose_sight_radius(radius)
    # Already authoritative cover/visibility is passed in by infected_sight.gd.
    _vision.observe(observer, Vector2.RIGHT, position, visible, maxf(delta, 0.0))
    # Do not record a new position while the target is hidden or outside
    # the already-validated native sight radius.
    if visible and _vision.is_target_visible() and _history != null:
        _history.record_stimulus(0, position, 1.0, DEFAULT_SIGHT_MEMORY, source_id)


func record_confirmed_sound(listener: Vector2, source: Vector2, radius: float,
        source_id: int = -1) -> bool:
    if _hearing == null or not listener.is_finite() or not source.is_finite():
        return false
    if not is_finite(radius) or radius <= 0.0:
        return false
    _hearing.set_hearing_radius(radius)
    # InfectedHearing.audible() has already checked occlusion, wind, and noise.
    # A weaker but valid sound must not erase a louder/closer remembered
    # source merely because another player's dictionary entry was visited.
    var accepted: bool
    if _ranked_hearing_available:
        accepted = bool(_hearing.report_noise_ranked(listener, source, 1.0))
    else:
        accepted = bool(_hearing.report_noise(listener, source, 1.0))
    if accepted and _history != null:
        # The 2D history receives ONLY already-audible world events.
        var strength := clampf(1.0 - listener.distance_to(source) / radius, 0.001, 1.0)
        _history.record_stimulus(1, source, strength, DEFAULT_SOUND_MEMORY, source_id)
    return accepted


func advance_time(delta: float) -> void:
    if _vision != null:
        _vision.advance_time(maxf(delta, 0.0))
    if _hearing != null:
        _hearing.advance_time(maxf(delta, 0.0))
    if _history != null:
        _history.advance_time(maxf(delta, 0.0))


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


func best_confirmed_stimulus(sense: int) -> Dictionary:
    if _history == null:
        return {}
    return _history.get_best(sense)


## Unreal-style perception range query over *previously approved* stimuli.
## This filters stale remote locations during chase recovery without sensing
## any new player, changing target selection, or exposing server-only memory.
func best_confirmed_stimulus_in_radius(sense: int, center: Vector2, radius: float) -> Dictionary:
    if _history == null or not center.is_finite() or not is_finite(radius) or radius < 0.0:
        return {}
    if _history.has_method("get_best_in_radius"):
        return _history.get_best_in_radius(sense, center, radius)
    # Older Cgame binaries: preserve correct filtering with a bounded, rare
    # GDScript fallback. Stock Godot still returns an empty Dictionary.
    var selected: Dictionary = {}
    var best_score := -1.0
    for entry_data in _history.get_recent(64):
        var entry: Dictionary = entry_data
        if int(entry.get("sense", -1)) != sense:
            continue
        var position: Vector2 = entry.get("position", Vector2.INF)
        if not position.is_finite() or position.distance_squared_to(center) > radius * radius:
            continue
        var score: float = float(entry.get("score", -1.0))
        if score > best_score:
            best_score = score
            selected = entry
        elif score == best_score and not selected.is_empty():
            var source_id: int = int(entry.get("source_id", -1))
            var previous_id: int = int(selected.get("source_id", -1))
            var previous_position: Vector2 = selected.get("position", Vector2.INF)
            if source_id < previous_id or (source_id == previous_id and (
                    position.x < previous_position.x or (
                    position.x == previous_position.x and position.y < previous_position.y))):
                selected = entry
    return selected


func get_recent_confirmed_stimuli(limit: int = 8) -> Array:
    if _history == null:
        return []
    return _history.get_recent(limit)


func get_debug_snapshot() -> Dictionary:
    # An on-demand diagnostic view. Do not replicate to ordinary clients:
    # target-memory positions belong to the authoritative server.
    return {
        "native_vision": has_native_vision(),
        "native_hearing": has_native_hearing(),
        "native_stimulus_history": has_native_history(),
        "stimulus_count": int(_history.get_event_count()) if _history != null else 0,
        "best_sight_stimulus": best_confirmed_stimulus(0),
        "best_sound_stimulus": best_confirmed_stimulus(1),
        "recent_stimuli": get_recent_confirmed_stimuli(),
        "ranked_hearing": has_ranked_hearing(),
        "remembers_sight": remembers_sight(),
        "remembers_sound": remembers_sound(),
        "last_seen_position": last_seen_position(),
        "last_heard_position": last_heard_position(),
        "sight_memory_seconds": float(_vision.get_memory_remaining()) if _vision != null else 0.0,
        "sound_memory_seconds": float(_hearing.get_memory_remaining()) if _hearing != null else 0.0,
        "sound_strength": float(_hearing.get_last_heard_strength()) if _ranked_hearing_available else 0.0,
    }


func reset() -> void:
    if _vision != null:
        _vision.reset()
    if _hearing != null:
        _hearing.reset()
    if _history != null:
        _history.reset()
