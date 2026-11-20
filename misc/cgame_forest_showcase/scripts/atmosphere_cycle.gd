extends Node
## Small deterministic day/night + weather controller for Aurora Forest.
## Evaluates atmosphere only twice per second: sky shader uniforms changing
## every render frame would repeatedly invalidate the sky radiance texture.
## This deliberately doesn't use TIME in the sky shader.

const WEATHER_CLEAR: int = 0
const WEATHER_CLOUDY: int = 1
const WEATHER_MIST: int = 2
const WEATHER_NAMES = ["Ясно", "Облачно", "Туман"]
const REFRESH_INTERVAL: float = 0.50

@export_range(1.0, 120.0, 1.0) var cycle_minutes: float = 16.0
var day_hours: float = 17.25
var weather_mode: int = WEATHER_CLEAR
var paused: bool = false

var _sun: DirectionalLight3D
var _environment: Environment
var _sky_material: ShaderMaterial
var _elapsed_since_update: float = 0.0
var _update_count: int = 0


func _init() -> void:
    set_process(false)


func configure(sun: DirectionalLight3D, environment: Environment,
        sky_material: ShaderMaterial) -> void:
    _sun = sun
    _environment = environment
    _sky_material = sky_material
    apply_now()
    set_process(true)


func _process(delta: float) -> void:
    if paused or not is_finite(delta) or delta <= 0.0:
        return
    day_hours = fposmod(day_hours + delta * 24.0 / (cycle_minutes * 60.0), 24.0)
    _elapsed_since_update += delta
    if _elapsed_since_update >= REFRESH_INTERVAL:
        # Do not attempt to replay missed renders after an application stall.
        _elapsed_since_update = 0.0
        apply_now()


func set_clock(hours: float) -> void:
    if not is_finite(hours):
        return
    day_hours = fposmod(hours, 24.0)
    _elapsed_since_update = 0.0
    apply_now()


func skip_hours(hours: float) -> void:
    if is_finite(hours):
        set_clock(day_hours + hours)


func set_weather(mode: int) -> void:
    weather_mode = clampi(mode, WEATHER_CLEAR, WEATHER_MIST)
    apply_now()


func cycle_weather() -> void:
    set_weather((weather_mode + 1) % 3)


func get_weather_name() -> String:
    return WEATHER_NAMES[weather_mode]


func get_update_count() -> int:
    return _update_count


func sample_state(hours: float, weather: int) -> Dictionary:
    # Pure deterministic calculation suitable for headless smoke testing.
    # Sun is above horizon from 06:00 to 18:00.
    var hour: float = fposmod(hours, 24.0)
    var sun_height: float = sin((hour - 6.0) * TAU / 24.0)
    var day: float = smoothstep(-0.20, 0.25, sun_height)
    var twilight: float = 1.0 - smoothstep(0.03, 0.50, absf(sun_height))
    var warmth: float = twilight * day
    var cloudy: float = 1.0 if weather == WEATHER_CLOUDY else 0.0
    var mist: float = 1.0 if weather == WEATHER_MIST else 0.0
    var dampening: float = 1.0 - cloudy * 0.43 - mist * 0.32

    var night_top := Color(0.007, 0.016, 0.050)
    var day_top := Color(0.055, 0.15, 0.34)
    var night_mid := Color(0.018, 0.034, 0.080)
    var day_mid := Color(0.18, 0.38, 0.56)
    var night_horizon := Color(0.04, 0.06, 0.11)
    var day_horizon := Color(0.58, 0.70, 0.78)
    var top: Color = night_top.lerp(day_top, day)
    var middle: Color = night_mid.lerp(day_mid, day)
    var horizon: Color = night_horizon.lerp(day_horizon, day)
    horizon = horizon.lerp(Color(0.98, 0.42, 0.16), warmth * 0.80)

    var overcast_tint := Color(0.22, 0.27, 0.32)
    top = top.lerp(overcast_tint, cloudy * 0.55 + mist * 0.40)
    middle = middle.lerp(overcast_tint, cloudy * 0.60 + mist * 0.50)
    horizon = horizon.lerp(Color(0.34, 0.37, 0.39), cloudy * 0.40 + mist * 0.65)

    return {
        "sun_height": sun_height,
        "sun_energy": (0.04 + 1.40 * day) * dampening if sun_height > -0.17 else 0.0,
        "sun_color": Color(1.0, 0.92, 0.77).lerp(Color(1.0, 0.52, 0.27), warmth * 0.75),
        "top": top,
        "middle": middle,
        "horizon": horizon,
        "clouds": 0.22 + cloudy * 0.60 + mist * 0.48,
        "aurora": pow(1.0 - day, 1.7) * (1.0 - cloudy * 0.75 - mist * 0.85),
        "ambient": 0.19 + day * (0.68 - cloudy * 0.18 - mist * 0.24),
        "fog": 0.004 + cloudy * 0.009 + mist * 0.030,
        "volumetric": 0.009 + cloudy * 0.012 + mist * 0.023,
        "fog_color": Color(0.12, 0.19, 0.27).lerp(Color(0.58, 0.64, 0.67), day)
    }


func apply_now() -> void:
    if _sun == null or _environment == null or _sky_material == null:
        return
    var state: Dictionary = sample_state(day_hours, weather_mode)
    var elevation: float = float(state["sun_height"])
    # A negative X rotation aims sunlight down during daytime.
    _sun.rotation_degrees = Vector3(-rad_to_deg(asin(elevation)), -43.0, 0.0)
    _sun.light_energy = state["sun_energy"]
    _sun.light_color = state["sun_color"]
    _sun.shadow_enabled = elevation > 0.12

    _environment.ambient_light_energy = state["ambient"]
    _environment.fog_density = state["fog"]
    _environment.volumetric_fog_density = state["volumetric"]
    _environment.fog_light_color = state["fog_color"]

    _sky_material.set_shader_parameter("zenith_color", state["top"])
    _sky_material.set_shader_parameter("mid_color", state["middle"])
    _sky_material.set_shader_parameter("horizon_color", state["horizon"])
    _sky_material.set_shader_parameter("cloud_coverage", state["clouds"])
    _sky_material.set_shader_parameter("aurora_intensity", state["aurora"])
    _update_count += 1
