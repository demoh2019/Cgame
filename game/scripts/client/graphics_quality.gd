extends RefCounted
const GroundPlants = preload("res://scripts/client/ground_plants.gd")
const GrassField = preload("res://scripts/client/grass_field.gd")

## User-selectable visual fidelity. Both the Compatibility and Forward+ renderers remain supported.
## Keep the choice local to the client; it must never affect authoritative simulation.

const SETTINGS_PATH := "user://albion_after_graphics.cfg"
const NAMES := ["Performance", "Balanced", "High", "Ultra"]
const VisualProfiles = preload("res://scripts/client/graphics_profiles.gd")
const GraphicsLighting = preload("res://scripts/client/graphics_lighting.gd")
const GraphicsTonemapping = preload("res://scripts/client/graphics_tonemapping.gd")
const GraphicsLens = preload("res://scripts/client/graphics_lens.gd")
const GraphicsShadowAtlas = preload("res://scripts/client/graphics_shadow_atlas.gd")
const GraphicsContactShadows = preload("res://scripts/client/graphics_contact_shadows.gd")
const GraphicsSunShafts = preload("res://scripts/client/graphics_sun_shafts.gd")
const BlobShadow = preload("res://scripts/client/blob_shadow.gd")
const LensDirt = preload("res://scripts/client/lens_dirt.gd")
const GraphicsReflections = preload("res://scripts/client/graphics_reflections.gd")
const GraphicsIndirectLighting = preload("res://scripts/client/graphics_indirect_lighting.gd")
const WaterRefraction = preload("res://scripts/client/water_refraction.gd")
const WaterCaustics = preload("res://scripts/client/water_caustics.gd")
const GraphicsResolution = preload("res://scripts/client/graphics_resolution.gd")
const GraphicsTextureStreaming = preload("res://scripts/client/graphics_texture_streaming.gd")
const GraphicsNativeSpecularAA = preload("res://scripts/client/graphics_native_specular_aa.gd")
const GraphicsSkinShading = preload("res://scripts/client/graphics_skin_scattering.gd")
const StoneMicrodetail = preload("res://scripts/client/graphics_stone_microdetail.gd")
const ShadowBudget = preload("res://scripts/client/shadow_budget.gd")
const Foliage = preload("res://scripts/client/foliage.gd")
const SceneryLod = preload("res://scripts/client/scenery_lod.gd")
const DungeonLightBudget = preload("res://scripts/client/dungeon_light_budget.gd")
const DungeonReflectionBudget = preload("res://scripts/client/dungeon_reflection_budget.gd")
const OutdoorReflectionBudget = preload("res://scripts/client/outdoor_reflection_budget.gd")
const ChunkView = preload("res://scripts/client/chunk_view.gd")
const GraphicsFramePacing = preload("res://scripts/client/graphics_frame_pacing.gd")
const GraphicsFoveatedShading = preload("res://scripts/client/graphics_foveated_shading.gd")
const GraphicsHdrOutput = preload("res://scripts/client/graphics_hdr_output.gd")
const GraphicsAreaLights = preload("res://scripts/client/graphics_area_lights.gd")
const CharacterShading = preload("res://scripts/client/character_shading.gd")
const ImpostorField = preload("res://scripts/client/impostor_field.gd")
const Rendering = preload("res://scripts/native/cgame_rendering.gd") # Native cgame_rendering module when built in.

static var _level: int = 1
static var _loaded: bool = false


static func load_preference() -> void:
	if _loaded:
		return
	_loaded = true
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) == OK:
		_level = clampi(int(config.get_value("rendering", "quality", 1)), 0, NAMES.size() - 1)


static func level() -> int:
	return _level


## Per-refresh limit for releasing old *visual* chunks after teleports.
## High quality can tolerate more teardown work per streaming tick; lower
## presets pace detach/cleanup more aggressively to avoid frame spikes.
static func unload_budget_for_quality(value: int) -> int:
	return [12, 20, 32, 48][clampi(value, 0, 3)]


## Soft wall-clock time slice for native obsolete-chunk deactivation.
## Keep a small guaranteed cleanup slice even on Performance settings.
static func unload_time_budget_for_quality(value: int) -> int:
	return [400, 650, 900, 1200][clampi(value, 0, 3)]


## Conservative detached cosmetic scene cache estimate, not physical RAM.
static func streamed_chunk_cache_bytes_for_quality(value: int) -> int:
	return [8, 16, 24, 32][clampi(value, 0, 3)] * 1048576


## Bound how long detached scenery retains memory while player is idle.
static func streamed_chunk_cache_retention_for_quality(value: int) -> float:
	return [3.0, 5.0, 8.0, 12.0][clampi(value, 0, 3)]


## Time-slice ordinary expiration of detached cosmetic chunks.
static func streamed_cache_expirations_for_quality(value: int) -> int:
	return [1, 1, 2, 2][clampi(value, 0, 3)]


static func streamed_cache_expiration_usec_for_quality(value: int) -> int:
	return [350, 500, 750, 1000][clampi(value, 0, 3)]


## Startup only: Unreal World Partition-style area ramp. Preserve a safe
## nearby terrain area and gradually request the configured full range.
## Fractions scale area, not distance, on our 2D XZ streaming grid.
static func startup_streaming_area_for_quality(value: int) -> float:
	return [0.36, 0.49, 0.64, 0.81][clampi(value, 0, 3)]


static func startup_streaming_ramp_duration(value: int) -> float:
	return [3.0, 3.5, 4.0, 4.5][clampi(value, 0, 3)]


## Cosmetic streaming only: scripts far from the camera update at a
## budgeted interval instead of running expensive visual work every frame.
## This is separate from the even farther complete simulation-pause radius.
static func streamed_tick_radius_for_quality(value: int) -> float:
	return [32.0, 48.0, 64.0, 80.0][clampi(value, 0, 3)]


static func streamed_tick_interval_for_quality(value: int) -> float:
	return [0.20, 0.125, 0.075, 0.05][clampi(value, 0, 3)]


static func get_name() -> String:
	return NAMES[_level]


static func set_level(value: int, persist: bool = true) -> void:
	_level = clampi(value, 0, NAMES.size() - 1)
	_loaded = true
	if persist:
		var config := ConfigFile.new()
		config.load(SETTINGS_PATH) # Keep other preferences, notably Auto.
		config.set_value("rendering", "quality", _level)
		var error := config.save(SETTINGS_PATH)
		if error != OK:
			push_warning("Could not save graphics quality: %d" % error)


static func cycle() -> void:
	set_level((_level + 1) % NAMES.size())


## Pure data so settings can be verified without a GPU and retuned together.
static func profile(value: int) -> Dictionary:
	match clampi(value, 0, NAMES.size() - 1):
		0:
			return {"shadows": false, "shadow_distance": 45.0, "msaa": Viewport.MSAA_DISABLED, "anisotropy": Viewport.ANISOTROPY_2X,
				"blur_quality": 0, "blur_radius": 0.0, "glow": false, "ssao": false, "ssil": false, "sdfgi": false, "cloud_shadows": false,
				"scale": 0.59, "upscaler": "spatial", "grass_radius": 66.0, "grass_budget": 1500, "decor_budget_usec": 850, "grass_fade_start": 25.0, "grass_fade_end": 40.0, "terrain_detail_radius": 24.0, "terrain_mesh_build_budget_usec": 900, "terrain_mesh_streaming_priority": 1, "horizon_ao_strength": 0.0, "terrain_pixel_error": 6.0, "ground_contact_strength": 0.0, "curvature_strength": 0.0, "puddle_ripple_strength": 0.0, "mesh_lod_threshold": 4.0, "terrain_layer_budget": 2, "terrain_warp_strength": 0.0, "terrain_height_blend": 0.0, "cliff_normal_quality": 0.0, "specular_aa_strength": 0.0, "micro_occlusion": 0.0, "normal_variance_strength": 0.0, "wet_clearcoat": 0.0, "sharpen_strength": 0.0, "deband_strength": 0.0}
		1:
			return {"shadows": true, "shadow_distance": 70.0, "msaa": Viewport.MSAA_DISABLED, "anisotropy": Viewport.ANISOTROPY_4X,
				"blur_quality": 1, "blur_radius": 1.6, "glow": false, "ssao": false, "ssil": false, "sdfgi": false, "cloud_shadows": true,
				"scale": 0.77, "upscaler": "spatial", "grass_radius": 90.0, "grass_budget": 2200, "decor_budget_usec": 1100, "grass_fade_start": 40.0, "grass_fade_end": 60.0, "terrain_detail_radius": 42.0, "terrain_mesh_build_budget_usec": 1500, "terrain_mesh_streaming_priority": 2, "horizon_ao_strength": 0.0, "terrain_pixel_error": 3.5, "ground_contact_strength": 0.28, "curvature_strength": 0.30, "puddle_ripple_strength": 0.22, "mesh_lod_threshold": 2.0, "terrain_layer_budget": 3, "terrain_warp_strength": 0.0, "terrain_height_blend": 0.0, "cliff_normal_quality": 0.0, "specular_aa_strength": 0.0, "micro_occlusion": 0.0, "normal_variance_strength": 0.0, "wet_clearcoat": 0.0, "sharpen_strength": 0.12, "deband_strength": 0.0}
		2:
			return {"shadows": true, "shadow_distance": 110.0, "msaa": Viewport.MSAA_2X, "anisotropy": Viewport.ANISOTROPY_8X,
				"blur_quality": 2, "blur_radius": 2.6, "glow": true, "ssao": true, "ssil": true, "sdfgi": false, "cloud_shadows": true,
				"scale": 1.0, "grass_radius": 116.0, "grass_budget": 3000, "decor_budget_usec": 1700, "grass_fade_start": 54.0, "grass_fade_end": 80.0, "terrain_detail_radius": 68.0, "terrain_mesh_build_budget_usec": 2300, "terrain_mesh_streaming_priority": 2, "horizon_ao_strength": 0.50, "terrain_pixel_error": 1.8, "ground_contact_strength": 0.48, "curvature_strength": 0.70, "puddle_ripple_strength": 0.65, "mesh_lod_threshold": 1.0, "terrain_layer_budget": 4, "terrain_warp_strength": 0.24, "terrain_height_blend": 0.48, "cliff_normal_quality": 0.7, "specular_aa_strength": 0.18, "micro_occlusion": 0.55, "normal_variance_strength": 0.55, "wet_clearcoat": 0.45, "sharpen_strength": 0.14, "deband_strength": 0.8}
		_:
			return {"shadows": true, "shadow_distance": 140.0, "msaa": Viewport.MSAA_4X, "anisotropy": Viewport.ANISOTROPY_16X,
				"blur_quality": 2, "blur_radius": 3.0, "glow": true, "ssao": true, "ssil": false, "sdfgi": true, "cloud_shadows": true,
				"scale": 1.0, "grass_radius": 140.0, "grass_budget": 4000, "decor_budget_usec": 2400, "grass_fade_start": 66.0, "grass_fade_end": 94.0, "terrain_detail_radius": 96.0, "terrain_mesh_build_budget_usec": 3500, "terrain_mesh_streaming_priority": 2, "horizon_ao_strength": 0.80, "terrain_pixel_error": 0.9, "ground_contact_strength": 0.7, "curvature_strength": 1.0, "puddle_ripple_strength": 1.0, "mesh_lod_threshold": 0.75, "terrain_layer_budget": 13, "terrain_warp_strength": 0.42, "terrain_height_blend": 0.85, "cliff_normal_quality": 1.0, "specular_aa_strength": 0.30, "micro_occlusion": 0.85, "normal_variance_strength": 0.95, "wet_clearcoat": 0.65, "sharpen_strength": 0.22, "deband_strength": 1.0}


## Limit expensive SDFGI occlusion to Ultra dungeon spaces. Online scene
## calls this at its existing weather tick, with idempotent GPU updates.
static func update_dynamic_sdfgi(environment: Environment, underground: bool) -> void:
	GraphicsIndirectLighting.update_visibility(environment, _level,
		str(RenderingServer.get_current_rendering_method()), underground)


## Native manual High/Ultra can use a small focused detail boost. Forward+ adaptive
## FSR2 already performs image reconstruction; never sharpen that output twice.
static func post_sharpen_strength(value: int, method: String, adaptive: bool) -> float:
	if method == "forward_plus" and adaptive:
		return 0.0
	return float(profile(value)["sharpen_strength"])


## Fast path for frame-rate adjustment; no scene-node, texture, LOD or
## streamer changes are performed here.
## The same driver-aware policy is used for initial, manual and adaptive
## resolution changes, without relaunching or rebuilding world resources.
static func metalfx_resolution_floor() -> float:
	# The same eligibility gate is used by the adaptive controller and by
	# the actual render-mode plan. Never claim a floor above tier ceiling.
	return GraphicsResolution.metalfx_budget_floor(
		GraphicsResolution.runtime_metalfx_min_scale(),
		float(profile(_level)["scale"]))


static func apply_resolution(viewport: Viewport,
		render_scale: float = -1.0, adaptive: bool = false) -> void:
	var renderer: String = str(RenderingServer.get_current_rendering_method())
	var driver: String = str(RenderingServer.get_current_rendering_driver_name())
	var minimum: float = metalfx_resolution_floor()
	GraphicsResolution.apply(viewport,
		GraphicsResolution.plan(renderer, profile(_level), render_scale,
			adaptive, driver, minimum))


static func apply(viewport: Viewport, atmosphere: Node3D,
		post_material: ShaderMaterial, water: MeshInstance3D = null,
		streamer: Node = null, render_scale: float = -1.0,
		adaptive: bool = false) -> void:
	var p := profile(_level)
	# One global uniform adjusts every streamed terrain chunk; no resource reimport or per-chunk updates.
	RenderingServer.global_shader_parameter_set(&"aa_terrain_detail_radius", float(p["terrain_detail_radius"]))
	RenderingServer.global_shader_parameter_set(&"aa_ground_contact_strength", float(p["ground_contact_strength"]))
	RenderingServer.global_shader_parameter_set(&"aa_terrain_curvature_strength",
		float(p["curvature_strength"]))
	# Native terrain sky visibility reuses existing vertex B; zero disables AO.
	RenderingServer.global_shader_parameter_set(&"aa_terrain_horizon_ao_strength",
		float(p["horizon_ao_strength"]))
	# HDRP-style normal-map micro-shadows: reuse existing sampled terrain
	# normals, preserve SSAO lighting, no new textures or GPU passes.
	RenderingServer.global_shader_parameter_set(&"aa_terrain_micro_occlusion",
		float(p.get("micro_occlusion", 0.0)))
	# Premium terrain reads normal variance already packed by native mip baking.
	RenderingServer.global_shader_parameter_set(&"aa_terrain_normal_variance_strength",
		float(p["normal_variance_strength"]))
	# Rain ripples share one shader uniform across every streamed terrain material.
	# Zero on Performance: the expensive per-pixel ring work is skipped entirely.
	RenderingServer.global_shader_parameter_set(&"aa_puddle_ripple_strength",
		float(p["puddle_ripple_strength"]))
	RenderingServer.global_shader_parameter_set(&"aa_terrain_layer_budget", int(p["terrain_layer_budget"]))
	# High/Ultra break repetitive ground PBR tiles without duplicating textures.
	RenderingServer.global_shader_parameter_set(&"aa_terrain_warp_strength",
		float(p["terrain_warp_strength"]))
	# High/Ultra height-aware material boundaries (terrain world noise is reused).
	# One GPU scalar applies to every streamed chunk; no per-chunk uploads.
	RenderingServer.global_shader_parameter_set(&"aa_terrain_height_blend",
		float(p["terrain_height_blend"]))
	# Only High/Ultra near cliffs sample three extra rock normal projections.
	RenderingServer.global_shader_parameter_set(&"aa_cliff_normal_quality",
		float(p["cliff_normal_quality"]))
	# Shared normal-variance filter is completely disabled on low-end presets.
	RenderingServer.global_shader_parameter_set(&"aa_specular_aa_strength",
		float(p["specular_aa_strength"]))
	# Shader variants on High/Ultra draw an extra rain-wet dielectric BRDF;
	# Performance and Balanced don't compile it at all.
	RenderingServer.global_shader_parameter_set(&"aa_terrain_wet_clearcoat",
		float(p["wet_clearcoat"]))
	# Per-instance foliage fade shares the exact GPU batch visibility ranges.
	# The shader is opaque (ordered discard), never alpha-blended.
	RenderingServer.global_shader_parameter_set(&"aa_foliage_tree_cull",
		SceneryLod.range_for("tree", _level))
	RenderingServer.global_shader_parameter_set(&"aa_foliage_bush_cull",
		SceneryLod.range_for("bush", _level))
	RenderingServer.global_shader_parameter_set(&"aa_foliage_fade_width",
		SceneryLod.foliage_fade_width(_level))
	var world_profile: Dictionary = VisualProfiles.settings(_level)
	# One uniform controls wet foliage highlights in every streamed nature batch.
	# Performance skips specular detail without rebuilding any meshes.
	RenderingServer.global_shader_parameter_set(&"aa_vegetation_wet_gloss",
		float(world_profile["wet_leaf_gloss"]))
	# Thin leaf transmission is a single PBR backlight term; no new material copies.
	RenderingServer.global_shader_parameter_set(&"aa_leaf_transmission",
		float(world_profile["leaf_transmission"]))
	# Physically inspired leaf/grass pigment filtering only on High/Ultra.
	# Existing PBR backlighting and all streamed nature MultiMeshes are reused.
	RenderingServer.global_shader_parameter_set(&"aa_leaf_optics_quality",
		float(world_profile["leaf_optics_quality"]))
	# Cheap direct-light transmission on grass tips; never rebuild existing
	# MultiMesh tiles on a quality change.
	RenderingServer.global_shader_parameter_set(&"aa_grass_transmission",
		float(world_profile["grass_transmission"]))
	# Animate grass lighting normals only on higher graphics levels. This
	# shares the same vertex shader and never adds a pixel texture lookup.
	RenderingServer.global_shader_parameter_set(&"aa_grass_normal_wind",
		float(world_profile["grass_normal_wind"]))
	# Crown AO scales down as genuine shadow maps and SSAO become available.
	RenderingServer.global_shader_parameter_set(&"aa_canopy_occlusion",
		float(world_profile["canopy_occlusion"]))
	# Shadow maps are budgeted independently from normal object visibility.
	ShadowBudget.configure(world_profile)
	# One global torch budget covers all streamed underground rooms.
	DungeonLightBudget.configure(_level)
	# Local dungeon cubemaps are pooled and captured only on nearby room changes.
	DungeonReflectionBudget.configure(_level)
	OutdoorReflectionBudget.configure(_level)
	# The active backend can differ from ProjectSettings after a driver fallback.
	var method := RenderingServer.get_current_rendering_method()
	# Opaque submerged PBR terrain and procedural terrain share a single
	# quality uniform. Only High/Ultra Forward+ pay for animated caustics.
	RenderingServer.global_shader_parameter_set(&"aa_water_caustics_strength",
		WaterCaustics.quality_strength(_level, str(method)))
	# One shared sun atlas across the process. Only change its allocation when
	# the resolved quality/backend budget differs; Auto may apply repeatedly.
	GraphicsShadowAtlas.apply(_level, str(method))
	# The engine-side streaming worker prefetches a sharper mip for moving
	# cameras on High/Ultra, but only if the fork exposes its singleton.
	GraphicsTextureStreaming.apply(_level, str(method))
	# Native screen-space roughness AA stabilizes all imported glTF PBR meshes,
	# not only our custom terrain/foliage shaders. No new screen pass.
	GraphicsNativeSpecularAA.apply(_level, str(method))
	# Only imported opaque skin on Forward+ High/Ultra pays for native SSS.
	GraphicsSkinShading.configure(_level, str(method), viewport)
	# Detail-normal assets are shared by every cached dungeon masonry mesh.
	# High/Ultra enable native PBR detail; low-end presets spend zero taps.
	StoneMicrodetail.configure(_level, str(method))
	# Steady frame delivery: vsync mode and FPS cap per tier (UE5 t.MaxFPS).
	Rendering.frame_pacing_apply(_level)
	# HDR10/EDR swapchain on High/Ultra when the monitor supports it.
	Rendering.hdr_apply(_level, str(method))
	if viewport != null:
		# Foveated VRS keeps full shading around the player on low presets.
		Rendering.foveated_apply(viewport, _level, str(method))
		# Torch/lantern emitter radius drives PCSS soft local shadows.
		Rendering.area_lights_configure(_level, viewport.get_tree() if viewport.is_inside_tree() else null)
	# Hair/cloth/eye models apply to characters built from now on.
	CharacterShading.configure(_level)
	# Baked billboard impostor rings past the real decor range.
	Rendering.impostor_configure(_level)
	if viewport != null:
		# Texture-group anisotropic shader variants are already cached per tier.
		# This viewport cap makes imported glTF PBR texture detail just as sharp.
		viewport.anisotropic_filtering_level = int(p["anisotropy"])
		# Screen-space mesh decimation applies to imported GLTF models inside MultiMeshes.
		# Higher thresholds choose cheaper geometry sooner, without hiding gameplay resources.
		viewport.mesh_lod_threshold = float(p["mesh_lod_threshold"])
		apply_resolution(viewport, render_scale, adaptive)
	# MSAA edge coverage smooths leaf silhouettes on native High/Ultra.
	# FSR2 or Compatibility automatically reuses the ordinary alpha-cutout shader.
	Foliage.configure_antialiasing(
		Foliage.supports_alpha_coverage(str(method), viewport.msaa_3d) if viewport != null else false)
	# Far leaf alpha coverage uses cached native mip levels even with FSR2.
	# Low-end renderers retain their original imported texture allocations.
	Foliage.configure_alpha_mipmaps(_level, str(method))
	# Round contact blobs stand in for sun shadows on Performance.
	if viewport != null and viewport.is_inside_tree():
		viewport.get_tree().call_group(BlobShadow.GROUP, "set_visible", BlobShadow.wanted(bool(p["shadows"])))
	var native_vignette := false
	var lens_env: Environment = null
	if atmosphere != null:
		# The atmosphere owns the persistent shadow enable flag used by its day/night update.
		# Applying only to the sun node would let nighttime weather restore shadows on Performance.
		var atmosphere_profile: Dictionary = p.duplicate()
		atmosphere_profile["sky_radiance"] = world_profile["sky_radiance"]
		# Populate the cached-sky fast path and directional sunset haze budget.
		atmosphere_profile["sky_use_cached_radiance"] = world_profile["sky_use_cached_radiance"]
		atmosphere_profile["sky_scattering_strength"] = world_profile["sky_scattering_strength"]
		atmosphere_profile["atmospheric_lut_strength"] = world_profile["atmospheric_lut_strength"]
		# Keep the world's directional light in sync with spectral sky extinction.
		atmosphere_profile["sun_transmittance_strength"] = world_profile["sun_transmittance_strength"]
		atmosphere_profile["moon_detail_strength"] = world_profile["moon_detail_strength"]
		atmosphere_profile["cirrus_detail"] = world_profile["cirrus_detail"]
		atmosphere_profile["volumetric_cloud_steps"] = world_profile["volumetric_cloud_steps"]
		atmosphere_profile["cirrus_opacity"] = world_profile["cirrus_opacity"]
		atmosphere_profile["cloud_lighting_strength"] = world_profile["cloud_lighting_strength"]
		# Only desktop Forward+ gets froxel volumetrics. Compatibility/Mobile use
		# one lightweight weather-driven height-fog layer instead.
		atmosphere_profile["quality_level"] = _level
		atmosphere_profile["rendering_method"] = method
		atmosphere_profile["sky_refresh_interval"] = world_profile["sky_refresh_interval"]
		if atmosphere.has_method("apply_graphics_profile"):
			atmosphere.call("apply_graphics_profile", atmosphere_profile)
		var sun := atmosphere.get("sun") as DirectionalLight3D
		if sun != null:
			sun.shadow_enabled = p["shadows"]
			sun.directional_shadow_max_distance = p["shadow_distance"]
			# Screen-space contact detail is restricted to High/Ultra Forward+.
			# The engine skips its forced depth prepass when no light opts in.
			GraphicsContactShadows.apply(sun, _level, str(method))
			# Unreal/CryEngine-style screen-space god rays, Forward+ High/Ultra only.
			if viewport != null:
				GraphicsSunShafts.apply(viewport.get_camera_3d(), sun, _level, str(method))
		var env := atmosphere.get("environment") as Environment
		if env != null:
			env.glow_enabled = p["glow"]
			# Fixed quality tiers trade contact AO and indirect bounce against GPU cost.
			# This overwrites Atmosphere's startup defaults on every preset change.
			GraphicsIndirectLighting.apply(env, _level, str(method))
		# Keep the cinematic shadow/fog budget tied to the active renderer,
		# not merely to the requested quality preset.
		GraphicsLighting.apply(sun, env, _level, method)
		# Native AgX preserves sunrise/cloud highlight hues on supported
		# Forward+ High/Ultra. Low-end remains on the established ACES curve.
		GraphicsTonemapping.apply(env, _level, str(method))
		# Native HDR lens fringing + filmic grain inside the same tonemap pass.
		native_vignette = GraphicsLens.apply(env, _level, str(method))
		lens_env = env
		# Bloom dirt mask: bright lights reveal smudges on the lens (High/Ultra Forward+).
		LensDirt.apply(env, _level, str(method))
		# Hybrid sky + screen-space reflections on High/Ultra Forward+ only.
		# Runtime changes (including Auto) also turn SSR off when required.
		GraphicsReflections.apply(env, _level, method)
	if post_material != null:
		post_material.set_shader_parameter("blur_quality", p["blur_quality"])
		post_material.set_shader_parameter("blur_radius", p["blur_radius"])
		var sharpen: float = post_sharpen_strength(_level, method, adaptive)
		# The engine fork sharpens natively (CAS in the tonemap pass, before tilt-shift),
		# so the canvas pass skips its own and nothing is sharpened twice.
		if lens_env != null and str(method) == "forward_plus" and "lens_sharpen" in lens_env:
			lens_env.set("lens_sharpen", sharpen * 1.6)
			sharpen = 0.0
		post_material.set_shader_parameter("sharpen_strength", sharpen)
		# Sub-LSB output dither is fused into the existing grade pass. Auto
		# resolution and renderer switching cannot leave stale grain enabled.
		post_material.set_shader_parameter("deband_strength", float(p["deband_strength"]))
		post_material.set_shader_parameter("lens_distortion", GraphicsLens.distortion(_level, str(method)))
		# The engine's optical cos^4 vignette replaces the flat canvas one on High/Ultra.
		post_material.set_shader_parameter("vignette", 0.0 if native_vignette else 0.28)
	# Texture-group-style anisotropy on expensive terrain samplers only:
	# Performance/Balanced use trilinear; High sharpens color at grazing
	# angles; Ultra also filters normal detail. Existing chunk road/biome
	# maps are kept in place when a preset is switched.
	ChunkView.configure_terrain_filter(_level)
	ChunkView.configure_terrain_geomorph(_level)
	ChunkView.configure_terrain_horizon(_level)
	ChunkView.configure_terrain_screen_lod(_level)
	ChunkView.configure_terrain_pixel_error(float(p["terrain_pixel_error"]))
	# Native mesh-streaming CPU time slice is shared across all terrain nodes;
	# quality changes reuse existing LOD meshes, not a destructive rebuild.
	ChunkView.configure_terrain_mesh_budget(int(p["terrain_mesh_build_budget_usec"]))
	ChunkView.configure_terrain_streaming_priority(int(p["terrain_mesh_streaming_priority"]))
	ChunkView.configure_terrain_mesh_residency(_level)
	ChunkView.configure_terrain_error_lod(_level)
	if viewport != null:
		for lod_terrain in viewport.get_tree().get_nodes_in_group(ChunkView.TERRAIN_LOD_GROUP):
			ChunkView.apply_terrain_geomorph(lod_terrain)
			ChunkView.apply_terrain_horizon(lod_terrain)
			ChunkView.apply_terrain_screen_lod(lod_terrain)
			ChunkView.apply_terrain_pixel_error(lod_terrain)
			ChunkView.apply_terrain_mesh_budget(lod_terrain)
			ChunkView.apply_terrain_streaming_priority(lod_terrain)
			ChunkView.apply_terrain_mesh_residency(lod_terrain)
			ChunkView.apply_terrain_error_lod(lod_terrain)
	if viewport != null:
		for terrain in viewport.get_tree().get_nodes_in_group(ChunkView.TERRAIN_GROUP):
			ChunkView.apply_terrain_filter(terrain)
	# Scanned ground plants: off on Low, sparser on Medium, densest on Ultra (applies to new tiles).
	GroundPlants.density_scale = GroundPlants.quality_scale(_level)
	GroundPlants.distance_scale = GroundPlants.quality_distance_scale(_level)
	GroundPlants.card_planes = GroundPlants.quality_card_planes(_level)
	GroundPlants.far_density = GroundPlants.quality_far_density(_level)
	# Engine foveated rendering (Metal rasterization rate maps): screen edges shade at a lower rate on the
	# cheaper presets. CGAME_FOVEATION=<edge rate> overrides it for A/B runs (1 = off).
	var foveation: float = [0.5, 0.6, 1.0, 1.0][clampi(_level, 0, 3)]
	if OS.get_environment("CGAME_FOVEATION") != "":
		foveation = clampf(OS.get_environment("CGAME_FOVEATION").to_float(), 0.25, 1.0)
	if ProjectSettings.has_setting("rendering/vrs/cgame_foveation_edge_rate"):
		ProjectSettings.set_setting("rendering/vrs/cgame_foveation_edge_rate", foveation)
	GrassField.far_density = GroundPlants.quality_far_density(_level) # Applies to grass tiles built from now on.
	# Reuse the game's existing 3-tier grass LOD; never rebuild world geometry on a preset switch.
	ChunkView.configure_grass(float(world_profile["grass_build_radius"]), int(world_profile["grass_budget_usec"]),
			float(world_profile["grass_fade_start"]), float(world_profile["grass_fade_end"]))
	if viewport != null:
		for tile in viewport.get_tree().get_nodes_in_group(ChunkView.GRASS_GROUP):
			if tile is MultiMeshInstance3D:
				tile.visibility_range_end = ChunkView.grass_visibility_end

	# Following HLOD practice, imported mesh LOD bias and distant decor
	# culling scale with quality. Existing GPU batches are updated in place.
	ChunkView.configure_scenery(_level)
	# Native WorldStreamer continues its existing per-frame chunk budget;
	# cosmetic detail has one separate, small camera-priority frame slice.
	ChunkView.configure_decor_budget(int(p["decor_budget_usec"]))
	if viewport != null:
		# Unreal Cull Distance Volume-inspired bulk update: preserve the
		# existing per-object policy but send grouped decor bounds through
		# one native call per bounded 4096-instance batch.
		SceneryLod.apply_many(
			viewport.get_tree().get_nodes_in_group(ChunkView.SCENERY_GROUP), _level)

	# The graphics profiles also control water detail and how many terrain chunks are streamed.
	if water != null and water.material_override is ShaderMaterial:
		var water_shader := water.material_override as ShaderMaterial
		# High/Ultra Forward+ get real scene refraction. The low shader does
		# not declare a screen sampler, so it cannot force a buffer copy.
		WaterRefraction.apply(water_shader, world_profile, _level, str(method))
		water_shader.set_shader_parameter("ripple_strength", float(world_profile["water_ripples"]))
		# Spectral light transported through clear, shallow water. Zero on
		# Performance avoids the branch; even Ultra makes no extra texture reads.
		water_shader.set_shader_parameter("shallow_scattering_strength",
			float(world_profile["shallow_scattering_strength"]))
		# Wind-driven water waves reuse the atmosphere's existing weather vector
		# and the existing normal/whitecap calculations. No extra wave meshes.
		water_shader.set_shader_parameter("wind_wave_strength",
			float(world_profile["wind_wave_strength"]))
		# Only high-frequency ocean detail is faded, not the large waves,
		# shoreline transparency, Fresnel or the physically lit reflections.
		water_shader.set_shader_parameter("detail_fade_start", float(world_profile["water_detail_start"]))
		water_shader.set_shader_parameter("detail_fade_end", float(world_profile["water_detail_end"]))
		water_shader.set_shader_parameter("shore_glimmer_strength", float(world_profile["shore_glimmer_strength"]))
		# Reuse the existing depth buffer for coherent animated shoreline surf.
		water_shader.set_shader_parameter("shore_surf_strength", float(world_profile["shore_surf_strength"]))
		water_shader.set_shader_parameter("shore_glimmer_fade_start", float(world_profile["shore_glimmer_start"]))
		water_shader.set_shader_parameter("shore_glimmer_fade_end", float(world_profile["shore_glimmer_end"]))
	if streamer != null:
		streamer.set("load_radius", float(world_profile["chunk_radius"]))
		streamer.set("unload_radius", float(world_profile["chunk_unload"]))
		# Unreal-style bounded deactivation of far procedural scenery.
		# The fork method is opt-in; stock Godot and older engine builds
		# retain the existing unlimited unload path.
		if streamer.has_method("set_max_unloads_per_update"):
			var unload_limit: int = unload_budget_for_quality(_level)
			if int(streamer.call("get_max_unloads_per_update")) != unload_limit:
				streamer.call("set_max_unloads_per_update", unload_limit)
		# Runtime quality changes immediately trim detached cosmetic cache.
		if streamer.has_method("set_max_cached_chunk_bytes"):
			var cache_bytes: int = streamed_chunk_cache_bytes_for_quality(_level)
			if int(streamer.call("get_max_cached_chunk_bytes")) != cache_bytes:
				streamer.call("set_max_cached_chunk_bytes", cache_bytes)
		if streamer.has_method("set_cached_chunk_retention_seconds"):
			var retention: float = streamed_chunk_cache_retention_for_quality(_level)
			if not is_equal_approx(float(streamer.call("get_cached_chunk_retention_seconds")), retention):
				streamer.call("set_cached_chunk_retention_seconds", retention)
		# Prevent a busy frame when several detached scenes expire together.
		if streamer.has_method("set_max_cached_expirations_per_frame"):
			var expiry_slots: int = streamed_cache_expirations_for_quality(_level)
			var expiry_usec: int = streamed_cache_expiration_usec_for_quality(_level)
			if int(streamer.call("get_max_cached_expirations_per_frame")) != expiry_slots:
				streamer.call("set_max_cached_expirations_per_frame", expiry_slots)
			if int(streamer.call("get_max_cached_expiration_work_usec")) != expiry_usec:
				streamer.call("set_max_cached_expiration_work_usec", expiry_usec)
		# One expensive scene detach must not consume a whole frame of
		# subsequent cleanup. Older native builds remain fully compatible.
		if streamer.has_method("set_max_unload_work_usec"):
			var unload_usec: int = unload_time_budget_for_quality(_level)
			if int(streamer.call("get_max_unload_work_usec")) != unload_usec:
				streamer.call("set_max_unload_work_usec", unload_usec)
		# Native cosmetic tick LOD never pauses collision, network state,
		# loot or other authoritative actors; only ChunkView opts in.
		if streamer.has_method("set_tick_throttle_radius"):
			var tick_radius: float = streamed_tick_radius_for_quality(_level)
			var tick_interval: float = streamed_tick_interval_for_quality(_level)
			if not is_equal_approx(float(streamer.call("get_tick_throttle_radius")), tick_radius):
				streamer.call("set_tick_throttle_radius", tick_radius)
			if not is_equal_approx(float(streamer.call("get_tick_throttle_interval")), tick_interval):
				streamer.call("set_tick_throttle_interval", tick_interval)
			if not is_equal_approx(float(streamer.call("get_tick_throttle_hysteresis")), 12.0):
				streamer.call("set_tick_throttle_hysteresis", 12.0)
