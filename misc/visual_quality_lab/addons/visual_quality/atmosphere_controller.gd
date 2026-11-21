extends Node
class_name AtmosphereController3D
## Low-frequency, deterministic day/night and weather for a Godot 4 sky shader.
## Set target nodes/resources before add_child() to avoid a one-frame flicker.

signal atmosphere_changed(hour: float, overcast: float)

@export_range(0.0, 24.0, 0.1) var hour: float = 14.0
@export_range(0.0, 1.0, 0.01) var overcast: float = 0.0
@export var auto_cycle: bool = false
@export_range(20.0, 2400.0, 1.0) var day_length_seconds: float = 480.0
@export_range(0.25, 10.0, 0.25) var update_interval_seconds: float = 2.0
@export var animate_clouds: bool = false
@export var restore_on_exit: bool = true

var sun: DirectionalLight3D
var environment: Environment
var sky_material: ShaderMaterial

var _elapsed: float = 0.0
var _cloud_phase: float = 0.0
var _original_rotation: Vector3
var _original_energy: float = 1.0
var _original_sun_color: Color = Color.WHITE
var _original_fog_enabled: bool = false
var _original_fog_density: float = 0.01
var _original_fog_color: Color = Color.WHITE
var _saved_shader_uniforms: Dictionary = {}
var _captured: bool = false

const SHADER_PARAMETERS = [
	"zenith_color", "horizon_color", "cloud_color", "cloud_coverage",
	"cloud_opacity", "night_amount", "night_color", "stars_intensity", "cloud_time"
]


func _ready() -> void:
	if sun == null or environment == null or sky_material == null:
		push_warning("AtmosphereController3D: assign sun, environment and sky_material before adding the node")
		set_process(false)
		return
	_original_rotation = sun.rotation_degrees
	_original_energy = sun.light_energy
	_original_sun_color = sun.light_color
	_original_fog_enabled = environment.fog_enabled
	_original_fog_density = environment.fog_density
	_original_fog_color = environment.fog_light_color
	for name in SHADER_PARAMETERS:
		_saved_shader_uniforms[name] = sky_material.get_shader_parameter(name)
	_captured = true
	apply_atmosphere()


func _process(delta: float) -> void:
	if not auto_cycle and not animate_clouds:
		return
	if delta <= 0.0 or not is_finite(delta):
		return
	if auto_cycle:
		hour = wrapf(hour + delta * 24.0 / maxf(day_length_seconds, 20.0), 0.0, 24.0)
	if animate_clouds:
		_cloud_phase = fposmod(_cloud_phase + delta * 0.005, 1024.0)
	_elapsed += delta
	if _elapsed >= maxf(update_interval_seconds, 0.25):
		_elapsed = 0.0
		apply_atmosphere()


func set_hour(value: float) -> void:
	hour = wrapf(value, 0.0, 24.0)
	_elapsed = 0.0
	apply_atmosphere()


func set_overcast(value: float) -> void:
	overcast = clampf(value, 0.0, 1.0)
	_elapsed = 0.0
	apply_atmosphere()


func set_auto_cycle(value: bool) -> void:
	auto_cycle = value


func apply_atmosphere() -> void:
	if not _captured:
		return
	var daylight: float = sunlight_factor(hour)
	var night: float = 1.0 - smoothstep(0.0, 0.24, daylight)
	var dawn: float = 1.0 - absf(daylight * 2.0 - 1.0)
	var zenith: Color = Color(0.035, 0.16, 0.36).lerp(Color(0.005, 0.011, 0.036), night)
	var horizon: Color = Color(0.60, 0.74, 0.90).lerp(Color(0.02, 0.035, 0.085), night)
	horizon = horizon.lerp(Color(1.0, 0.43, 0.24), dawn * (1.0 - night) * 0.38)
	zenith = zenith.lerp(Color(0.25, 0.28, 0.36), overcast * 0.45)
	horizon = horizon.lerp(Color(0.40, 0.45, 0.51), overcast * 0.55)

	# Light direction crosses below the horizon at night; energy becomes zero.
	# Avoid moving lights every rendered frame: radiance refresh is expensive.
	var solar_height: float = sin((wrapf(hour, 0.0, 24.0) - 6.0) * TAU / 24.0)
	sun.rotation_degrees = Vector3(-solar_height * 68.0, 25.0, 0.0)
	sun.light_energy = _original_energy * daylight * (1.0 - 0.55 * overcast)
	sun.light_color = Color(1.0, 0.96, 0.88).lerp(Color(1.0, 0.61, 0.42), dawn * 0.50)

	sky_material.set_shader_parameter("zenith_color", Vector3(zenith.r, zenith.g, zenith.b))
	sky_material.set_shader_parameter("horizon_color", Vector3(horizon.r, horizon.g, horizon.b))
	sky_material.set_shader_parameter("cloud_color", Vector3(0.94, 0.96, 1.0).lerp(Vector3(0.44, 0.47, 0.54), overcast))
	sky_material.set_shader_parameter("cloud_coverage", lerpf(0.48, 0.30, overcast))
	sky_material.set_shader_parameter("cloud_opacity", lerpf(0.40, 0.95, overcast))
	sky_material.set_shader_parameter("night_amount", night)
	sky_material.set_shader_parameter("night_color", Vector3(0.004, 0.009, 0.03))
	sky_material.set_shader_parameter("stars_intensity", (1.0 - overcast) * night)
	if animate_clouds:
		sky_material.set_shader_parameter("cloud_time", _cloud_phase)

	environment.fog_enabled = overcast > 0.08
	environment.fog_density = fog_density_for(overcast)
	environment.fog_light_color = horizon
	atmosphere_changed.emit(hour, overcast)


func _exit_tree() -> void:
	if not restore_on_exit or not _captured:
		return
	if is_instance_valid(sun):
		sun.rotation_degrees = _original_rotation
		sun.light_energy = _original_energy
		sun.light_color = _original_sun_color
	if environment != null:
		environment.fog_enabled = _original_fog_enabled
		environment.fog_density = _original_fog_density
		environment.fog_light_color = _original_fog_color
	if sky_material != null:
		for name in SHADER_PARAMETERS:
			sky_material.set_shader_parameter(name, _saved_shader_uniforms[name])


## Pure, wrapped 24-hour daylight curve for reproducible behavior and tests.
static func sunlight_factor(time_hour: float) -> float:
	if not is_finite(time_hour):
		return 0.0
	var height: float = sin((wrapf(time_hour, 0.0, 24.0) - 6.0) * TAU / 24.0)
	return smoothstep(-0.10, 0.28, height)


static func fog_density_for(cloudiness: float) -> float:
	return lerpf(0.005, 0.035, clampf(cloudiness, 0.0, 1.0))
