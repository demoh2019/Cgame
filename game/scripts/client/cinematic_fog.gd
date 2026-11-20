extends RefCounted
## Dual-path atmospheric scattering: cheap sea-level haze on every renderer
## and bounded screen-space froxel fog only for Forward+ on High/Ultra.
## Pure profile/weather functions make GPU-independent regression possible.

const MAX_HEIGHT_DENSITY := 0.0040
const MAX_VOLUME_DENSITY := 0.0200
const PROFILES := [
	{"length": 0.0, "base_density": 0.0, "detail_spread": 2.0,
		"reprojection": 0.0, "height_scale": 0.55, "froxel_size": 0, "froxel_depth": 0},
	{"length": 0.0, "base_density": 0.0, "detail_spread": 2.0,
		"reprojection": 0.0, "height_scale": 0.85, "froxel_size": 0, "froxel_depth": 0},
	{"length": 48.0, "base_density": 0.0060, "detail_spread": 2.35,
		"reprojection": 0.66, "height_scale": 0.85, "froxel_size": 112, "froxel_depth": 96},
	{"length": 72.0, "base_density": 0.0080, "detail_spread": 2.55,
		"reprojection": 0.74, "height_scale": 1.0, "froxel_size": 160, "froxel_depth": 128},
]


static func profile(quality: int, method: String) -> Dictionary:
	var settings: Dictionary = PROFILES[clampi(quality, 0, 3)].duplicate(true)
	# Godot's expensive volumetric pass exists only on Forward+.
	settings["enabled"] = method == "forward_plus" and quality >= 2
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
		# The game's sky provides light already; injecting GI is unnecessary.
		env.volumetric_fog_gi_inject = 0.0
		env.volumetric_fog_ambient_inject = 0.0
	else:
		env.volumetric_fog_density = 0.0
	if sun != null:
		sun.light_volumetric_fog_energy = 0.8 if enabled else 0.0


## A single fast height-fog pass on Compatibility; the optional Forward+
## fog combines with it only in a short, limited range.
static func apply_weather(env: Environment, daylight: float, sun_height: float,
		storm: float, settings: Dictionary, horizon: Color,
		biome: Dictionary = {}) -> void:
	if env == null:
		return
	var frame: Dictionary = weather(daylight, sun_height, storm, settings)
	env.fog_height = 2.6
	# The biomes modify the existing height and froxel fog, never add a pass.
	var height_scale: float = clampf(float(biome.get("height_factor", 1.0)), 0.55, 1.45)
	var volume_scale: float = clampf(float(biome.get("volume_factor", 1.0)), 0.65, 1.25)
	var tint_amount: float = clampf(float(biome.get("tint_amount", 0.0)), 0.0, 0.22) * clampf(daylight, 0.0, 1.0)
	var tint: Color = biome.get("tint", horizon)
	env.fog_height_density = minf(float(frame["height_density"]) * height_scale, MAX_HEIGHT_DENSITY)
	env.fog_sun_scatter = float(frame["sun_scatter"])
	# Atmosphere sets the sky-derived base color first; this is a subtle
	# daylight tint that does not accumulate between successive frames.
	if not biome.is_empty():
		env.fog_light_color = env.fog_light_color.lerp(tint, tint_amount)
	if bool(settings.get("enabled", false)):
		env.volumetric_fog_density = minf(
			float(frame["volume_density"]) * volume_scale, MAX_VOLUME_DENSITY)
		env.volumetric_fog_albedo = horizon.lerp(Color(0.66, 0.7, 0.73), 0.18).lerp(tint, tint_amount)
