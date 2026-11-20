extends RefCounted
## Dual-path atmospheric scattering: cheap sea-level haze on every renderer
## and bounded screen-space froxel fog only for Forward+ on High/Ultra.
## Pure profile/weather functions make GPU-independent regression possible.

const MAX_HEIGHT_DENSITY := 0.0040
const MAX_VOLUME_DENSITY := 0.0200
const PROFILES := [
	{"length": 0.0, "base_density": 0.0, "detail_spread": 2.0,
		"reprojection": 0.0, "height_scale": 0.55, "froxel_size": 0, "froxel_depth": 0, "gi_inject": 0.0},
	{"length": 0.0, "base_density": 0.0, "detail_spread": 2.0,
		"reprojection": 0.0, "height_scale": 0.85, "froxel_size": 0, "froxel_depth": 0, "gi_inject": 0.0},
	{"length": 48.0, "base_density": 0.0060, "detail_spread": 2.35,
		"reprojection": 0.66, "height_scale": 0.85, "froxel_size": 112, "froxel_depth": 96, "gi_inject": 0.0},
	{"length": 72.0, "base_density": 0.0080, "detail_spread": 2.55,
		"reprojection": 0.74, "height_scale": 1.0, "froxel_size": 160, "froxel_depth": 128, "gi_inject": 0.24},
]


static func profile(quality: int, method: String) -> Dictionary:
	var settings: Dictionary = PROFILES[clampi(quality, 0, 3)].duplicate(true)
	# Godot's expensive volumetric pass exists only on Forward+.
	settings["enabled"] = method == "forward_plus" and quality >= 2
	# GI voxel sampling must never run on fallback renderers.
	if not bool(settings["enabled"]):
		settings["gi_inject"] = 0.0
	return settings


## No random effects or extra passes per frame. Real gameplay weather drives
## the strength continuously, so abrupt transitions are never needed.
static func weather(daylight: float, sun_height: float, storm: float,
		settings: Dictionary) -> Dictionary:
	var sun: float = clampf(daylight, 0.0, 1.0)
	var rain: float = clampf(storm, 0.0, 1.0)
	var low_sun: float = 1.0 - smoothstep(0.13, 0.54, absf(sun_height))
	var dawn: float = low_sun * smoothstep(0.02, 0.20, sun)
	var height_density: float = clampf(
		(0.00085 + 0.00165 * rain + 0.00060 * dawn)
		* float(settings.get("height_scale", 1.0)), 0.0, MAX_HEIGHT_DENSITY)
	var volume_density: float = 0.0
	if bool(settings.get("enabled", false)):
		volume_density = clampf(float(settings.get("base_density", 0.0)) *
			(0.65 + 0.85 * rain + 0.42 * dawn), 0.0, MAX_VOLUME_DENSITY)
	return {
		"height_density": height_density,
		"volume_density": volume_density,
		"sun_scatter": (0.06 + 0.22 * dawn) * (1.0 - 0.5 * rain) * sun,
		# Forward Mie scattering: low sun reveals rays through mist while storm
		# droplets broaden the lobe. No extra lights, textures, or fog passes.
		"anisotropy": clampf(0.38 + 0.16 * dawn * (1.0 - 0.6 * rain)
			- 0.10 * rain, 0.24, 0.55),
	}


## Applied ONLY when the user changes quality or renderer. Avoids rebuilding
## the volume grid on every daylight update.
static func apply_profile(env: Environment, sun: DirectionalLight3D,
		settings: Dictionary) -> void:
	if env == null:
		return
	var enabled: bool = bool(settings.get("enabled", false))
	if enabled:
		# Match HDRP's scalable froxel grid: High is cheap while Ultra has
		# finer screen-space shafts and fewer stair-steps near thin geometry.
		# The native renderer clamps invalid sizes and skips unchanged values.
		RenderingServer.environment_set_volumetric_fog_volume_size(
			int(settings.get("froxel_size", 128)), int(settings.get("froxel_depth", 128)))
	env.volumetric_fog_enabled = enabled
	if enabled:
		env.volumetric_fog_length = float(settings["length"])
		env.volumetric_fog_detail_spread = float(settings["detail_spread"])
		env.volumetric_fog_anisotropy = 0.38
		# Reprojection smooths volumetric bands, with less ghosting than 0.9.
		env.volumetric_fog_temporal_reprojection_enabled = true
		env.volumetric_fog_temporal_reprojection_amount = float(settings["reprojection"])
		env.volumetric_fog_sky_affect = 0.25
		# On Ultra, let the already-enabled SDFGI field softly illuminate the
		# same froxel volume. No second fog volume, screen pass, or probe capture.
		# High and unsupported renderers avoid even sampling the GI textures.
		# Guard against a missing/uninitialized GI field on scene startup.
		var gi_weight: float = clampf(float(settings.get("gi_inject", 0.0)), 0.0, 0.4) if env.sdfgi_enabled else 0.0
		if absf(env.volumetric_fog_gi_inject - gi_weight) > 0.0001:
			env.volumetric_fog_gi_inject = gi_weight
		env.volumetric_fog_ambient_inject = 0.0
	else:
		# A live Ultra -> High/Compatibility switch must remove the previous
		# SDFGI light contribution immediately, not leave stale fog brightness.
		if env.volumetric_fog_gi_inject != 0.0:
			env.volumetric_fog_gi_inject = 0.0
		env.volumetric_fog_density = 0.0
	if sun != null:
		sun.light_volumetric_fog_energy = 0.8 if enabled else 0.0


## A single fast height-fog pass on Compatibility; the optional Forward+
## fog combines with it only in a short, limited range.
static func apply_weather(env: Environment, daylight: float, sun_height: float,
		storm: float, settings: Dictionary, horizon: Color,
		biome: Dictionary = {}, base_fog: Dictionary = {}) -> void:
	if env == null:
		return
	var frame: Dictionary = weather(daylight, sun_height, storm, settings)
	# The biomes modify the existing height and froxel fog, never add a pass.
	var height_scale: float = clampf(float(biome.get("height_factor", 1.0)), 0.55, 1.45)
	var volume_scale: float = clampf(float(biome.get("volume_factor", 1.0)), 0.65, 1.25)
	var tint_amount: float = clampf(float(biome.get("tint_amount", 0.0)), 0.0, 0.22) * clampf(daylight, 0.0, 1.0)
	var tint: Color = biome.get("tint", horizon)
	var height_density: float = minf(
		float(frame["height_density"]) * height_scale, MAX_HEIGHT_DENSITY)
	var fog_color: Color = base_fog.get("color", env.fog_light_color)
	var fog_density: float = float(base_fog.get("density", env.fog_density))
	# Always tint the sky-derived base color, never last frame's tinted
	# result. Otherwise crossing a forest biome accumulates green each tick.
	if not biome.is_empty():
		fog_color = fog_color.lerp(tint, tint_amount)
	# The fork batches five weather/biome parameters into exactly one native
	# RenderingServer update. Stock Godot uses equivalent individual setters.
	if env.has_method("configure_weather_fog"):
		env.call("configure_weather_fog", fog_color, fog_density, 2.6,
			height_density, float(frame["sun_scatter"]))
	else:
		env.fog_light_color = fog_color
		env.fog_density = fog_density
		env.fog_height = 2.6
		env.fog_height_density = height_density
		env.fog_sun_scatter = float(frame["sun_scatter"])
	if bool(settings.get("enabled", false)):
		# Update when the weather actually changes enough; the renderer otherwise
		# keeps the previous value instead of sending new state every frame.
		var anisotropy: float = float(frame["anisotropy"])
		if absf(env.volumetric_fog_anisotropy - anisotropy) > 0.01:
			env.volumetric_fog_anisotropy = anisotropy
		env.volumetric_fog_density = minf(
			float(frame["volume_density"]) * volume_scale, MAX_VOLUME_DENSITY)
		env.volumetric_fog_albedo = horizon.lerp(Color(0.66, 0.7, 0.73), 0.18).lerp(tint, tint_amount)


## A lightning pulse must not be averaged into ~3/4 of the previous fog frame.
## Reduce history contribution only during the confirmed strike; retain a
## stable low-noise froxel grid for the rest of the weather simulation.
const LIGHTNING_HISTORY_FLOOR := 0.12


static func history_for_lightning(settings: Dictionary, flash: float) -> float:
	var baseline: float = clampf(float(settings.get("reprojection", 0.0)), 0.0, 0.90)
	if not is_finite(flash):
		return baseline
	var transient: float = smoothstep(0.03, 0.65, clampf(flash, 0.0, 1.0))
	return lerpf(baseline, minf(baseline, LIGHTNING_HISTORY_FLOOR), transient)


## The original Environment is reused: no second volume, post pass or light.
## A tiny delta threshold prevents uploads on the long, inactive tail.
static func apply_lightning_history(env: Environment, settings: Dictionary,
		flash: float) -> void:
	if env == null or not env.volumetric_fog_enabled:
		return
	var desired: float = history_for_lightning(settings, flash)
	var current: float = env.volumetric_fog_temporal_reprojection_amount
	if absf(current - desired) >= 0.01 or (flash <= 0.001 and current != desired):
		env.volumetric_fog_temporal_reprojection_amount = desired
