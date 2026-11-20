extends Node3D
## Sky, sun, light, fog, tone mapping and post effects, driven by the time of day and the weather.
## Everything degrades gracefully on the compatibility renderer (SSAO and the like are simply ignored).

var environment: Environment
var sun: DirectionalLight3D
var sky_material: ProceduralSkyMaterial
var world_environment: WorldEnvironment
var storm := 0.0 # 0..1, eased toward the target so the weather fades in and out.

const NIGHT_TOP := Color(0.01, 0.015, 0.05)
const NIGHT_HORIZON := Color(0.04, 0.05, 0.11)
const DAY_TOP := Color(0.2, 0.4, 0.78)
const DAY_HORIZON := Color(0.66, 0.78, 0.9)
const DUSK_HORIZON := Color(1.0, 0.55, 0.28)
const STORM_TOP := Color(0.24, 0.27, 0.32)
const STORM_HORIZON := Color(0.45, 0.48, 0.52)


func _ready() -> void:
	environment = Environment.new()
	environment.background_mode = Environment.BG_SKY
	sky_material = ProceduralSkyMaterial.new()
	sky_material.sky_curve = 0.18
	sky_material.ground_curve = 0.05
	sky_material.sun_angle_max = 28.0
	sky_material.sun_curve = 0.12
	var sky := Sky.new()
	sky.sky_material = sky_material
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	# Filmic look: ACES tone mapping, a little glow and slightly lifted colors.
	environment.tonemap_mode = Environment.TONE_MAPPER_ACES
	environment.tonemap_white = 6.0
	environment.tonemap_exposure = 0.82
	environment.glow_enabled = true
	environment.glow_intensity = 0.55
	environment.glow_bloom = 0.06
	environment.glow_hdr_threshold = 1.1
	environment.adjustment_enabled = true
	environment.adjustment_contrast = 1.1
	environment.adjustment_saturation = 1.1
	# Contact shadows in corners and under trees (Forward+ only).
	environment.ssao_enabled = true
	environment.ssao_radius = 1.6
	environment.ssao_intensity = 2.2
	environment.ssao_power = 1.6
	environment.ssil_enabled = false
	# Distance fog gives depth to the isometric view.
	environment.fog_enabled = true
	environment.fog_density = 0.0016
	environment.fog_aerial_perspective = 0.35
	environment.fog_sky_affect = 0.5
	environment.fog_height_density = 0.0
	world_environment = WorldEnvironment.new()
	world_environment.environment = environment
	add_child(world_environment)
	sun = DirectionalLight3D.new()
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 110.0
	sun.directional_shadow_split_1 = 0.22
	sun.shadow_bias = 0.04
	sun.shadow_normal_bias = 1.2
	sun.shadow_blur = 1.4
	sun.light_angular_distance = 0.6
	sun.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_AND_SKY
	add_child(sun)


## `daylight` 0..1 (0 night), `sun_height` -1..1, `phase` 0..1 around the day, `storming` whether it is stormy here.
func update(daylight: float, sun_height: float, phase: float, storming: bool, delta: float) -> void:
	storm = move_toward(storm, 1.0 if storming else 0.0, delta * 0.25)
	sun.rotation = Vector3(-deg_to_rad(lerpf(6.0, 62.0, clampf(sun_height, 0.0, 1.0))), deg_to_rad(35.0 + phase * 90.0), 0.0)
	# Low sun is orange, high sun is white; the moon is a weak blue light from the opposite direction.
	var low_sun := 1.0 - clampf(sun_height * 2.2, 0.0, 1.0)
	var warm := Color(1.0, 0.7, 0.45).lerp(Color(1.0, 0.97, 0.9), 1.0 - low_sun)
	if sun_height < 0.0:
		sun.light_color = Color(0.45, 0.55, 0.9)
		sun.rotation = Vector3(-deg_to_rad(lerpf(8.0, 50.0, clampf(-sun_height, 0.0, 1.0))), deg_to_rad(215.0 + phase * 90.0), 0.0)
		sun.light_energy = lerpf(0.0, 0.28, clampf(-sun_height * 2.0, 0.0, 1.0)) * (1.0 - storm * 0.6)
		sun.shadow_enabled = true
	else:
		sun.light_color = warm
		sun.light_energy = lerpf(0.05, 1.05, clampf(sun_height * 2.0, 0.0, 1.0)) * (1.0 - storm * 0.55)
	# Sky colors: night -> day, a band of dusk orange near the horizon when the sun is low, grey in a storm.
	var top := NIGHT_TOP.lerp(DAY_TOP, daylight)
	var horizon := NIGHT_HORIZON.lerp(DAY_HORIZON, daylight)
	var dusk := clampf(1.0 - absf(sun_height) * 3.0, 0.0, 1.0)
	horizon = horizon.lerp(DUSK_HORIZON, dusk * 0.7)
	top = top.lerp(STORM_TOP.darkened(1.0 - maxf(daylight, 0.15)), storm * 0.85)
	horizon = horizon.lerp(STORM_HORIZON.darkened(1.0 - maxf(daylight, 0.12)), storm * 0.8)
	sky_material.sky_top_color = top
	sky_material.sky_horizon_color = horizon
	sky_material.ground_horizon_color = horizon
	sky_material.ground_bottom_color = horizon.darkened(0.45)
	environment.ambient_light_energy = lerpf(0.35, 0.8, daylight) * (1.0 - storm * 0.25)
	environment.fog_light_color = horizon.lerp(Color(0.5, 0.52, 0.56), storm * 0.5)
	environment.fog_density = lerpf(0.0016, 0.0042, storm)
	environment.adjustment_saturation = lerpf(1.1, 0.95, storm)
