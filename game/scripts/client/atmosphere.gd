extends Node3D

const CloudShadowLut = preload("res://scripts/client/cloud_shadow_lut.gd")
const WaterCaustics = preload("res://scripts/client/water_caustics.gd")
const CinematicColorGrade = preload("res://scripts/client/cinematic_color_grade.gd")
const VegetationWind = preload("res://scripts/client/vegetation_wind.gd")
const CinematicFog = preload("res://scripts/client/cinematic_fog.gd")
const SunShadowQuality = preload("res://scripts/client/sun_shadow_quality.gd")
const BiomeAtmosphere = preload("res://scripts/client/biome_atmosphere.gd")
const SunShadowAtmosphere = preload("res://scripts/client/sun_shadow_atmosphere.gd")
const MoonVisuals = preload("res://scripts/client/moon_visuals.gd")
const LightningFlash = preload("res://scripts/client/graphics_lightning_flash.gd")
const GraphicsEyeAdaptation = preload("res://scripts/client/graphics_eye_adaptation.gd")
## Sky, sun, light, fog, tone mapping and post effects, driven by the time of day and the weather.
## Everything degrades gracefully on the compatibility renderer (SSAO and the like are simply ignored).

var environment: Environment
var sun: DirectionalLight3D
var sky_material: ShaderMaterial
var world_environment: WorldEnvironment
var sky: Sky
var _atmospheric_lut: Texture2D
var _shadows_allowed := true
var _cloud_shadows_allowed := true
var _shadow_elapsed := 0.20 # At most five shadow-opacity updates per second.
var _last_sun_height := 0.7
var _fog_profile: Dictionary = CinematicFog.profile(1, "gl_compatibility")
## Slow-moving sky lighting is cached separately from per-frame directional light and fog.
var _sky_refresh_interval := 0.4
var _sky_refresh_elapsed := 2.0 # Force the first material upload.
var _sky_seconds := 0.0
var _vegetation_wind := Vector3.ZERO
var _cloud_offset := Vector2.ZERO # Wrapped 1024 m high-cloud motion, shared by all surface materials.
var _wind_publish_seconds := 0.1
var _caustic_publish_seconds := 1.0 / WaterCaustics.UPDATES_PER_SECOND
# Conservative 4 Hz native light update; profile switches force a refresh.
var _shadow_filter_level := 1
var _shadow_filter_seconds := 0.25
const SHADOW_FILTER_INTERVAL := 0.25
var _visual_biome_settings: Dictionary = {}
var light_level := 1.0 # The daylight of the last update, 0 at night and 1 at noon.
var storm := 0.0 # 0..1, eased toward the target so the weather fades in and out.
var _lightning_elapsed := LightningFlash.DURATION
var _lightning_weight := 0.0
var _lightning_quality := 1

const NIGHT_TOP := Color(0.01, 0.015, 0.05)
const NIGHT_HORIZON := Color(0.04, 0.05, 0.11)
const DAY_TOP := Color(0.2, 0.4, 0.78)
const DAY_HORIZON := Color(0.66, 0.78, 0.9)
const DUSK_HORIZON := Color(1.0, 0.55, 0.28)
const STORM_TOP := Color(0.24, 0.27, 0.32)
const STORM_HORIZON := Color(0.45, 0.48, 0.52)


func _ready() -> void:
	# One cached 128x128 R8 texture drives ALL tree/grass/terrain shadow fields.
	# Initialize before the first streamed chunk compiles its materials.
	RenderingServer.global_shader_parameter_set(&"aa_cloud_shadow_map", CloudShadowLut.texture())
	RenderingServer.global_shader_parameter_set(&"aa_cloud_shadow_strength", 0.0)
	RenderingServer.global_shader_parameter_set(&"aa_water_caustics_sun", 0.0)
	RenderingServer.global_shader_parameter_set(&"aa_cloud_shadow_offset", Vector2.ZERO)
	environment = Environment.new()
	environment.background_mode = Environment.BG_SKY
	sky_material = ShaderMaterial.new()
	sky_material.shader = load("res://assets/shaders/sky.gdshader")
	# Reuse the same R8 LUT already bound to terrain and vegetation shadows.
	sky_material.set_shader_parameter("cirrus_lut", CloudShadowLut.texture())
	var panorama := load("res://assets/textures/sky/day_sky.jpg") as Texture2D
	sky_material.set_shader_parameter("has_panorama", panorama != null)
	if panorama != null:
		sky_material.set_shader_parameter("day_panorama", panorama)
	sky = Sky.new()
	sky.radiance_size = Sky.RADIANCE_SIZE_64
	# Avoid realtime sky cubemap updates: uniforms are now refreshed at a lower cadence.
	sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL
	sky.sky_material = sky_material
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	# Native renderer filmic default. High/Ultra will select the engine's AgX
	# curve through GraphicsQuality, with no extra fullscreen postprocess.
	environment.tonemap_mode = Environment.TONE_MAPPER_ACES
	environment.tonemap_white = 6.0
	environment.tonemap_exposure = 0.82
	environment.glow_enabled = true
	environment.glow_intensity = 0.55
	environment.glow_bloom = 0.06
	environment.glow_hdr_threshold = 1.1
	environment.adjustment_enabled = true
	environment.adjustment_contrast = 1.1
	environment.adjustment_saturation = 1.0
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
	environment.volumetric_fog_enabled = false
	world_environment = WorldEnvironment.new()
	world_environment.environment = environment
	# Initialize the camera resource disabled; the first graphics preset
	# enables it only when the active backend really supports exposure.
	GraphicsEyeAdaptation.apply(world_environment, 1, "gl_compatibility")
	add_child(world_environment)
	sun = DirectionalLight3D.new()
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 110.0
	sun.directional_shadow_split_1 = 0.22
	sun.shadow_bias = 0.04
	sun.shadow_normal_bias = 1.2
	sun.shadow_blur = 1.4
	# Quality selection enables PCSS only for High/Ultra on Forward+.
	# The startup value must never allocate expensive PCSS by default.
	sun.light_angular_distance = 0.0
	sun.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_AND_SKY
	sun.light_volumetric_fog_energy = 0.0
	add_child(sun)


## `daylight` 0..1 (0 night), `sun_height` -1..1, `phase` 0..1 around the day, `storming` whether it is stormy here.
func update(daylight: float, sun_height: float, phase: float, storming: bool, delta: float,
		wind: Vector2 = Vector2.ZERO, biome: String = "plains", moon_phase: float = 0.5) -> void:
	light_level = daylight
	_last_sun_height = sun_height
	storm = move_toward(storm, 1.0 if storming else 0.0, delta * 0.25)
	# Clouds and the solar altitude change directional contrast. The native
	# shadow opacity updates sparingly, independent of the existing cascades.
	if _shadows_allowed:
		_shadow_elapsed += maxf(delta, 0.0)
		if _shadow_elapsed >= 0.20:
			_shadow_elapsed = fmod(_shadow_elapsed, 0.20)
			SunShadowQuality.update_opacity(sun, daylight, sun_height, storm)
	RenderingServer.global_shader_parameter_set(&"aa_cloud_shadow_strength",
		CloudShadowLut.shadow_strength(daylight, storm, _cloud_shadows_allowed))
	# One GPU global updates every terrain material, without iterating streamed chunks.
	RenderingServer.global_shader_parameter_set(&"aa_weather_wetness", storm)
	# Sunlight focused through waves is a 5Hz scalar shared by every ground
	# material. Night, severe overcast and invalid weather suppress it.
	_caustic_publish_seconds += maxf(0.0, delta)
	if _caustic_publish_seconds >= 1.0 / WaterCaustics.UPDATES_PER_SECOND:
		_caustic_publish_seconds = fmod(_caustic_publish_seconds,
			1.0 / WaterCaustics.UPDATES_PER_SECOND)
		RenderingServer.global_shader_parameter_set(&"aa_water_caustics_sun",
			WaterCaustics.light_factor(daylight, sun_height, storm))
	_shadow_filter_seconds += maxf(delta, 0.0)
	if _shadow_filter_seconds >= SHADOW_FILTER_INTERVAL:
		_shadow_filter_seconds = fmod(_shadow_filter_seconds, SHADOW_FILTER_INTERVAL)
		SunShadowAtmosphere.apply(sun, _shadow_filter_level, daylight, sun_height, storm)
	# Weather-synchronised GPU foliage: one packed upload, maximum 10 times a second.
	_vegetation_wind = VegetationWind.smooth(
		_vegetation_wind, VegetationWind.target(wind), delta)
	# Integrate rather than multiply current wind by total scene time: the
	# cloud field never jumps when regional gusts change direction.
	_cloud_offset = CloudShadowLut.advance_offset(_cloud_offset, _vegetation_wind, delta)
	_wind_publish_seconds += maxf(0.0, delta)
	if _wind_publish_seconds >= 0.1:
		_wind_publish_seconds = fmod(_wind_publish_seconds, 0.1)
		RenderingServer.global_shader_parameter_set(&"aa_vegetation_wind", _vegetation_wind)
		# One extra global at 10 Hz; every forest/field/road still shares
		# a single cached R8 cloud shadow texture and one shader tap.
		RenderingServer.global_shader_parameter_set(&"aa_cloud_shadow_offset", _cloud_offset)
	sun.rotation = Vector3(-deg_to_rad(lerpf(6.0, 62.0, clampf(sun_height, 0.0, 1.0))), deg_to_rad(35.0 + phase * 90.0), 0.0)
	# Low sun is orange, high sun is white; the moon is a weak blue light from the opposite direction.
	var low_sun := 1.0 - clampf(sun_height * 2.2, 0.0, 1.0)
	var warm := Color(1.0, 0.7, 0.45).lerp(Color(1.0, 0.97, 0.9), 1.0 - low_sun)
	if sun_height < 0.0:
		sun.light_color = Color(0.55, 0.66, 1.0)
		sun.rotation = Vector3(-deg_to_rad(lerpf(8.0, 50.0, clampf(-sun_height, 0.0, 1.0))), deg_to_rad(215.0 + phase * 90.0), 0.0)
		sun.light_energy = lerpf(0.12, 0.5, clampf(-sun_height * 2.0, 0.0, 1.0)) * (1.0 - storm * 0.6)
		# Vary visual moonlight gently; keep the shared night ambient readable.
		sun.light_energy *= MoonVisuals.directional_fill(moon_phase)
		sun.shadow_enabled = _shadows_allowed
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
	# Sky illumination changes slowly relative to screen refresh. Only refresh its
	# radiance map at an explicit cadence; actual light, shadows and fog still run every frame.
	_sky_seconds += maxf(delta, 0.0)
	_sky_refresh_elapsed += maxf(delta, 0.0)
	if _sky_refresh_elapsed >= _sky_refresh_interval:
		_sky_refresh_elapsed = fmod(_sky_refresh_elapsed, _sky_refresh_interval)
		sky_material.set_shader_parameter("solar_elevation", clampf(sun_height, -0.15, 1.0))
		sky_material.set_shader_parameter("daylight", daylight)
		sky_material.set_shader_parameter("dusk", dusk)
		sky_material.set_shader_parameter("storm", storm)
		sky_material.set_shader_parameter("sky_time", _sky_seconds)
		sky_material.set_shader_parameter("moon_phase", moon_phase)
		# The sky panorama and sunlit terrain clouds follow the same wind.
		# Each wrapped 1024 m axis equals a full repeat of the panorama U.
		sky_material.set_shader_parameter("cloud_wind_rotation",
			(_cloud_offset.x + _cloud_offset.y) / CloudShadowLut.TILE_METERS)
		# Sky cloud detail and terrain clouds share the same integrated wind.
		sky_material.set_shader_parameter("cirrus_wind_offset", _cloud_offset)
		# DirectionalLight3D emits along -Z. Cache the world-space vector
		# TOWARD the sun, then reuse it in the shallow-water light transport.
		var to_sun: Vector3 = sun.global_transform.basis.z.normalized()
		sky_material.set_shader_parameter("sun_direction", to_sun)
		var light_color: Color = sun.light_color
		var solar_radiance := Vector3(light_color.r, light_color.g, light_color.b) * sun.light_energy
		sky_material.set_shader_parameter("sun_color", solar_radiance)
		# Water uses this shared solar state, refreshed with the sky cache.
		# At night, moon fill must not masquerade as direct solar scattering.
		RenderingServer.global_shader_parameter_set(&"aa_sun_to_light", to_sun)
		RenderingServer.global_shader_parameter_set(&"aa_sun_radiance",
			solar_radiance * smoothstep(0.02, 0.28, daylight))
	# Moonlit nights: the black night sky gives no ambient light, so a cool blue fill takes over as the light goes, and the
	# world stays readable in deep blue instead of turning to pitch black.
	environment.ambient_light_color = Color(0.3, 0.38, 0.62)
	environment.ambient_light_sky_contribution = lerpf(0.1, 1.0, smoothstep(0.0, 0.45, daylight))
	environment.ambient_light_energy = lerpf(0.75, 0.8, daylight) * (1.0 - storm * 0.25)
	environment.fog_light_color = horizon.lerp(Color(0.5, 0.52, 0.56), storm * 0.5)
	environment.fog_density = lerpf(0.0016, 0.0042, storm)
	_visual_biome_settings = BiomeAtmosphere.advance(_visual_biome_settings, biome, delta)
	CinematicFog.apply_weather(environment, daylight, sun_height, storm,
		_fog_profile, horizon, _visual_biome_settings)
	# Run the ACES-grade after atmospheric weather/fog, without replacing fog state.
	CinematicColorGrade.apply(environment, daylight, sun_height, storm)
	# Render only: two short flashes from the real lightning_struck event.
	# We only modify the existing sun, ambient and fog after their normal update.
	var amount: float = LightningFlash.sample(_lightning_elapsed,
		_lightning_weight * LightningFlash.strength(_lightning_quality))
	LightningFlash.apply(environment, sun, amount)
	_lightning_elapsed = minf(LightningFlash.DURATION,
		_lightning_elapsed + maxf(0.0, delta))


## Called only for an authenticated lightning_struck event from the server
## (or the same authoritative local simulation), never every rain frame.
func trigger_lightning(distance_m: float) -> void:
	var weight: float = LightningFlash.attenuation(distance_m)
	if weight <= 0.0:
		return
	_lightning_weight = weight
	_lightning_elapsed = 0.0


## Render-only switches; weather and the shared day/night clock are unaffected.
func apply_graphics_profile(settings: Dictionary) -> void:
	_shadows_allowed = bool(settings["shadows"])
	_cloud_shadows_allowed = bool(settings.get("cloud_shadows", true))
	_shadow_filter_level = clampi(int(settings.get("quality_level", 1)), 0, 3)
	_lightning_quality = _shadow_filter_level
	_shadow_filter_seconds = SHADOW_FILTER_INTERVAL
	GraphicsEyeAdaptation.apply(world_environment, _shadow_filter_level,
		str(settings.get("rendering_method", "gl_compatibility")))
	_fog_profile = CinematicFog.profile(
		int(settings.get("quality_level", 1)), str(settings.get("rendering_method", "gl_compatibility")))
	CinematicFog.apply_profile(environment, sun, _fog_profile)
	RenderingServer.global_shader_parameter_set(&"aa_cloud_shadow_strength",
		CloudShadowLut.shadow_strength(light_level, storm, _cloud_shadows_allowed))
	_sky_refresh_interval = clampf(float(settings.get("sky_refresh_interval", 0.4)), 0.12, 2.0)
	# The cubemap has always been refreshed at a bounded cadence. Reuse it
	# for the visible low-end sky instead of recomputing panorama and stars
	# for every background pixel each frame.
	sky_material.set_shader_parameter("use_cached_radiance",
		bool(settings.get("sky_use_cached_radiance", false)))
	# Sky haze is cached with the radiance map; no per-frame shader updates.
	sky_material.set_shader_parameter("aerosol_scattering_strength",
		clampf(float(settings.get("sky_scattering_strength", 0.0)), 0.0, 1.0))
	# Native HDR Rayleigh/Mie-inspired LUT is created once, only on High/Ultra.
	# Stock Godot and Compatibility retain the original panoramic sky.
	var lut_strength: float = clampf(float(settings.get("atmospheric_lut_strength", 0.0)), 0.0, 1.0)
	if lut_strength > 0.001 and _atmospheric_lut == null and ClassDB.class_exists("SkyScatteringLUT"):
		var generator: Object = ClassDB.instantiate("SkyScatteringLUT")
		if generator != null and generator.has_method("generate_lut"):
			var lut_image := generator.call("generate_lut", 128, 64, 2.0) as Image
			if lut_image != null:
				_atmospheric_lut = ImageTexture.create_from_image(lut_image)
				sky_material.set_shader_parameter("atmospheric_lut", _atmospheric_lut)
	sky_material.set_shader_parameter("has_atmospheric_lut", _atmospheric_lut != null and lut_strength > 0.001)
	sky_material.set_shader_parameter("atmospheric_lut_strength", lut_strength)
	# Tiny lunar surface shading only for the high-end graphics profiles.
	sky_material.set_shader_parameter("moon_detail_strength",
		clampf(float(settings.get("moon_detail_strength", 0.0)), 0.0, 1.0))
	# Optional cloud layer is completely skipped on Performance. Ultra uses
	# two filtered LUT taps; others use at most one, at sky refresh cadence.
	sky_material.set_shader_parameter("cirrus_detail",
		clampi(int(settings.get("cirrus_detail", 0)), 0, 2))
	sky_material.set_shader_parameter("cirrus_opacity",
		clampf(float(settings.get("cirrus_opacity", 0.0)), 0.0, 0.65))
	sun.shadow_enabled = _shadows_allowed
	sun.directional_shadow_max_distance = float(settings["shadow_distance"])
	# Renderer-aware PCSS is configured once per quality switch. Balanced and
	# Compatibility use the cheaper shadow filtering path.
	SunShadowQuality.apply(sun,
		int(settings.get("quality_level", 1)),
		str(settings.get("rendering_method", "gl_compatibility")),
		light_level, _last_sun_height, storm)
	_shadow_elapsed = 0.0
	environment.glow_enabled = bool(settings["glow"])
	# SSAO requires Forward+; the Compatibility renderer ignores it safely.
	environment.ssao_enabled = bool(settings["ssao"])
	match int(settings["sky_radiance"]):
		32:
			sky.radiance_size = Sky.RADIANCE_SIZE_32
		128:
			sky.radiance_size = Sky.RADIANCE_SIZE_128
		256:
			sky.radiance_size = Sky.RADIANCE_SIZE_256
		_:
			sky.radiance_size = Sky.RADIANCE_SIZE_64
