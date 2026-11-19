extends Node
## Scene-level day/night clock; kept inside game logic, not the engine.

const DAY_SECONDS := 240.0
var elapsed := 0.0
var day_number := 1
var hour := 8
var minute := 0
var _sun: DirectionalLight3D
var _environment: Environment


func _ready() -> void:
    _sun = get_parent().get_node_or_null("Sun") as DirectionalLight3D
    var atmosphere := get_parent().get_node_or_null("Atmosphere") as WorldEnvironment
    if atmosphere != null:
        _environment = atmosphere.environment
    advance(0.0)


func _process(delta: float) -> void:
    advance(delta)


func advance(delta: float) -> void:
    elapsed += maxf(delta, 0.0)
    var total_hours := 8.0 + elapsed * 24.0 / DAY_SECONDS
    day_number = 1 + int(floor(total_hours / 24.0))
    var local_hours := fposmod(total_hours, 24.0)
    hour = int(floor(local_hours))
    minute = int(floor((local_hours - float(hour)) * 60.0))
    var light_factor := clampf(sin((local_hours - 6.0) * PI / 12.0), 0.0, 1.0)
    if _sun != null:
        _sun.light_energy = lerpf(0.05, 1.4, light_factor)
    if _environment != null:
        _environment.ambient_light_energy = lerpf(0.12, 0.65, light_factor)
        _environment.background_color = Color("#0b1220").lerp(Color("#65747b"), light_factor)


func get_time_label() -> String:
    return "%02d:%02d" % [hour, minute]
