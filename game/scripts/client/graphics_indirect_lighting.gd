extends RefCounted
## Scalable local illumination for Forward+ terrain, PBR structures and vegetation.
## Unlike a duplicate post shader this reuses Godot's internal half-resolution
## SSAO (horizon-based) and SSIL buffers. Compatibility and Mobile allocate none.
##
## High: focused contact AO plus bounded half-resolution screen-space bounce.
## Screen-space color bleed makes sunlit ruin walls and vegetation illuminate
## nearby surfaces without the memory/voxel cost of SDFGI.
## Ultra: distance-field GI captures off-screen bounced light from streamed
## static terrain and structures. Short SDFGI cascades + half-resolution GI
## keep the opt-in Ultra tier bounded on unified-memory GPUs. Do not stack
## a duplicate SSIL bounce pass over SDFGI.
## The Cgame engine can commit all settings atomically; regular Godot falls back
## to the same runtime Environment properties.

static func settings(level: int, method: String) -> Dictionary:
	var tier: int = clampi(level, 0, 3)
	var forward: bool = method == "forward_plus"
	var ao: bool = forward and tier >= 2
	var sdfgi: bool = forward and tier == 3
	var bounce: bool = forward and tier == 2 # High only; Ultra uses SDFGI, never both.
	return {
		"ssao_enabled": ao,
		"ssao_radius": 1.10 if tier == 2 else 1.30,
		"ssao_intensity": 1.20 if tier == 2 else 1.35,
		"ssao_power": 1.40 if tier == 2 else 1.50,
		"ssao_detail": 0.42 if tier == 2 else 0.54,
		"ssao_horizon": 0.07,
		"ssao_sharpness": 0.94 if tier == 2 else 0.92,
		# Keep direct sunlight and artificial lights intact. AO acts on indirect.
		"ssao_light_affect": 0.0,
		"ssil_enabled": bounce,
		# Short rays and restrained intensity prevent strong halos at silhouettes.
		# The project renders SSIL at half resolution.
		"ssil_radius": 2.0,
		"ssil_intensity": 0.38,
		"ssil_sharpness": 0.96,
		"ssil_normal_rejection": 1.0,
		"sdfgi_enabled": sdfgi,
		"sdfgi_cascades": 2,
		"sdfgi_min_cell_size": 0.5,
		"sdfgi_read_sky_light": true,
		"sdfgi_bounce_feedback": 0.32,
		"sdfgi_energy": 0.72,
	}


## Apply only when graphics quality changes; never animate screen-space
## buffer settings at 60 Hz or allocate a second fullscreen pass.
static func apply(environment: Environment, level: int, method: String) -> void:
	if environment == null:
		return
	var p: Dictionary = settings(level, method)
	environment.ssao_enabled = bool(p["ssao_enabled"])
	# Never enable SDFGI while High's SSIL bounce is still active.
	# In the reverse transition, release SDFGI before enabling SSIL.
	# Each transition avoids a frame of double-indirect GPU work.
	if bool(p["sdfgi_enabled"]):
		apply_ssil(environment, p)
		apply_sdfgi(environment, p)
	else:
		apply_sdfgi(environment, p)
		apply_ssil(environment, p)
	if environment.ssao_enabled:
		environment.ssao_radius = float(p["ssao_radius"])
		environment.ssao_intensity = float(p["ssao_intensity"])
		environment.ssao_power = float(p["ssao_power"])
		environment.ssao_detail = float(p["ssao_detail"])
		environment.ssao_horizon = float(p["ssao_horizon"])
		environment.ssao_sharpness = float(p["ssao_sharpness"])
		environment.ssao_light_affect = float(p["ssao_light_affect"])



## Native Cgame batches all SSIL fields into one renderer update. Stock Godot
## uses the same Environment API without requiring a patched engine build.
static func apply_ssil(environment: Environment, p: Dictionary) -> void:
	var enabled: bool = bool(p["ssil_enabled"])
	if environment.has_method("configure_ssil"):
		environment.call("configure_ssil", enabled, float(p["ssil_radius"]),
			float(p["ssil_intensity"]), float(p["ssil_sharpness"]),
			float(p["ssil_normal_rejection"]))
		return
	if not enabled:
		if environment.ssil_enabled:
			environment.ssil_enabled = false
		return
	# Set inactive parameters first, enabling the pass only after it is ready.
	if not is_equal_approx(environment.ssil_radius, float(p["ssil_radius"])):
		environment.ssil_radius = float(p["ssil_radius"])
	if not is_equal_approx(environment.ssil_intensity, float(p["ssil_intensity"])):
		environment.ssil_intensity = float(p["ssil_intensity"])
	if not is_equal_approx(environment.ssil_sharpness, float(p["ssil_sharpness"])):
		environment.ssil_sharpness = float(p["ssil_sharpness"])
	if not is_equal_approx(environment.ssil_normal_rejection, float(p["ssil_normal_rejection"])):
		environment.ssil_normal_rejection = float(p["ssil_normal_rejection"])
	if not environment.ssil_enabled:
		environment.ssil_enabled = true


## The local dynamic GI budget is applied only when the graphics preset or
## rendering backend changes, never on a weather/day-night tick.
## Native Cgame coalesces this into one RendererServer update per tier switch.
static func apply_sdfgi(environment: Environment, p: Dictionary) -> void:
	var enabled: bool = bool(p["sdfgi_enabled"])
	if environment.has_method("configure_sdfgi"):
		environment.call("configure_sdfgi", enabled, int(p["sdfgi_cascades"]),
			float(p["sdfgi_min_cell_size"]), bool(p["sdfgi_read_sky_light"]),
			float(p["sdfgi_bounce_feedback"]), float(p["sdfgi_energy"]))
		return
	# Stock Godot compatibility: disable first, release any old GI cascades,
	# and leave all expensive setup untouched on Performance/Balanced/Mobile.
	if not enabled:
		if environment.sdfgi_enabled:
			environment.sdfgi_enabled = false
		return
	if environment.sdfgi_cascades != int(p["sdfgi_cascades"]):
		environment.sdfgi_cascades = int(p["sdfgi_cascades"])
	if not is_equal_approx(environment.sdfgi_min_cell_size, float(p["sdfgi_min_cell_size"])):
		environment.sdfgi_min_cell_size = float(p["sdfgi_min_cell_size"])
	if environment.sdfgi_read_sky_light != bool(p["sdfgi_read_sky_light"]):
		environment.sdfgi_read_sky_light = bool(p["sdfgi_read_sky_light"])
	if not is_equal_approx(environment.sdfgi_bounce_feedback, float(p["sdfgi_bounce_feedback"])):
		environment.sdfgi_bounce_feedback = float(p["sdfgi_bounce_feedback"])
	if not is_equal_approx(environment.sdfgi_energy, float(p["sdfgi_energy"])):
		environment.sdfgi_energy = float(p["sdfgi_energy"])
	if not environment.sdfgi_enabled:
		environment.sdfgi_enabled = true


## SDFGI occlusion is deliberately INDOOR-ONLY. Godot's extra visibility
## rays eliminate leaks through thick dungeon walls, but introduce dark
## blotches outdoors and cost GPU time. Normal/probe bias is lowered a little
## indoors to reduce leaks; the native engine applies all four fields at once.
## No new GI volumes, SDF cascades, or ray tracing system are created.
static func visibility_settings(level: int, method: String, underground: bool) -> Dictionary:
	var premium: bool = clampi(level, 0, 3) == 3 and method == "forward_plus"
	var interior: bool = premium and underground
	return {
		"use_occlusion": interior,
		"read_sky_light": not interior,
		"normal_bias": 0.95 if interior else 1.1,
		"probe_bias": 0.95 if interior else 1.1,
	}


## Called in the same existing environment/weather tick as the dungeon
## visibility culler. Purely static player-region policy; never re-voxelizes
## the terrain or changes these settings if the player stays put.
static func update_visibility(environment: Environment, level: int,
		method: String, underground: bool) -> void:
	if environment == null:
		return
	var profile: Dictionary = visibility_settings(level, method, underground)
	var occlusion: bool = bool(profile["use_occlusion"])
	var sky: bool = bool(profile["read_sky_light"])
	var normal_bias: float = float(profile["normal_bias"])
	var probe_bias: float = float(profile["probe_bias"])
	# Native and fallback share an idempotent client-side fast path.
	if environment.sdfgi_use_occlusion == occlusion and environment.sdfgi_read_sky_light == sky and \
			is_equal_approx(environment.sdfgi_normal_bias, normal_bias) and \
			is_equal_approx(environment.sdfgi_probe_bias, probe_bias):
		return
	if environment.has_method("configure_sdfgi_visibility"):
		environment.call("configure_sdfgi_visibility", occlusion, sky,
			normal_bias, probe_bias)
		return
	# Stock Godot fallback. Avoid redundant individual RenderingServer updates.
	if environment.sdfgi_use_occlusion != occlusion:
		environment.sdfgi_use_occlusion = occlusion
	if environment.sdfgi_read_sky_light != sky:
		environment.sdfgi_read_sky_light = sky
	if not is_equal_approx(environment.sdfgi_normal_bias, normal_bias):
		environment.sdfgi_normal_bias = normal_bias
	if not is_equal_approx(environment.sdfgi_probe_bias, probe_bias):
		environment.sdfgi_probe_bias = probe_bias
