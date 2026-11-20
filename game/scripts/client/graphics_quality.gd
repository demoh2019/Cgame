extends RefCounted

## User-selectable visual fidelity. Both the Compatibility and Forward+ renderers remain supported.
## Keep the choice local to the client; it must never affect authoritative simulation.

const SETTINGS_PATH := "user://albion_after_graphics.cfg"
const NAMES := ["Performance", "Balanced", "High", "Ultra"]
const VisualProfiles = preload("res://scripts/client/graphics_profiles.gd")
const GraphicsLighting = preload("res://scripts/client/graphics_lighting.gd")
const GraphicsShadowAtlas = preload("res://scripts/client/graphics_shadow_atlas.gd")
const GraphicsReflections = preload("res://scripts/client/graphics_reflections.gd")
const GraphicsIndirectLighting = preload("res://scripts/client/graphics_indirect_lighting.gd")
const WaterRefraction = preload("res://scripts/client/water_refraction.gd")
const GraphicsResolution = preload("res://scripts/client/graphics_resolution.gd")
const ShadowBudget = preload("res://scripts/client/shadow_budget.gd")
const Foliage = preload("res://scripts/client/foliage.gd")
const SceneryLod = preload("res://scripts/client/scenery_lod.gd")
const DungeonLightBudget = preload("res://scripts/client/dungeon_light_budget.gd")
const DungeonReflectionBudget = preload("res://scripts/client/dungeon_reflection_budget.gd")
const ChunkView = preload("res://scripts/client/chunk_view.gd")

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
				"blur_quality": 0, "blur_radius": 0.0, "glow": false, "ssao": false, "ssil": false, "cloud_shadows": false,
				"scale": 0.59, "grass_radius": 66.0, "grass_budget": 1500, "grass_fade_start": 25.0, "grass_fade_end": 40.0, "terrain_detail_radius": 24.0, "ground_contact_strength": 0.0, "puddle_ripple_strength": 0.0, "mesh_lod_threshold": 4.0, "terrain_layer_budget": 2, "cliff_normal_quality": 0.0, "specular_aa_strength": 0.0, "sharpen_strength": 0.0, "deband_strength": 0.0}
		1:
			return {"shadows": true, "shadow_distance": 70.0, "msaa": Viewport.MSAA_DISABLED, "anisotropy": Viewport.ANISOTROPY_4X,
				"blur_quality": 1, "blur_radius": 1.6, "glow": false, "ssao": false, "ssil": false, "cloud_shadows": true,
				"scale": 0.77, "grass_radius": 90.0, "grass_budget": 2200, "grass_fade_start": 40.0, "grass_fade_end": 60.0, "terrain_detail_radius": 42.0, "ground_contact_strength": 0.28, "puddle_ripple_strength": 0.22, "mesh_lod_threshold": 2.0, "terrain_layer_budget": 3, "cliff_normal_quality": 0.0, "specular_aa_strength": 0.0, "sharpen_strength": 0.0, "deband_strength": 0.0}
		2:
			return {"shadows": true, "shadow_distance": 110.0, "msaa": Viewport.MSAA_2X, "anisotropy": Viewport.ANISOTROPY_8X,
				"blur_quality": 2, "blur_radius": 2.6, "glow": true, "ssao": true, "ssil": false, "cloud_shadows": true,
				"scale": 1.0, "grass_radius": 116.0, "grass_budget": 3000, "grass_fade_start": 54.0, "grass_fade_end": 80.0, "terrain_detail_radius": 68.0, "ground_contact_strength": 0.48, "puddle_ripple_strength": 0.65, "mesh_lod_threshold": 1.0, "terrain_layer_budget": 4, "cliff_normal_quality": 0.7, "specular_aa_strength": 0.18, "sharpen_strength": 0.14, "deband_strength": 0.8}
		_:
			return {"shadows": true, "shadow_distance": 140.0, "msaa": Viewport.MSAA_4X, "anisotropy": Viewport.ANISOTROPY_16X,
				"blur_quality": 2, "blur_radius": 3.0, "glow": true, "ssao": true, "ssil": true, "cloud_shadows": true,
				"scale": 1.0, "grass_radius": 140.0, "grass_budget": 4000, "grass_fade_start": 66.0, "grass_fade_end": 94.0, "terrain_detail_radius": 96.0, "ground_contact_strength": 0.7, "puddle_ripple_strength": 1.0, "mesh_lod_threshold": 0.75, "terrain_layer_budget": 13, "cliff_normal_quality": 1.0, "specular_aa_strength": 0.30, "sharpen_strength": 0.22, "deband_strength": 1.0}


## Native manual High/Ultra can use a small focused detail boost. Forward+ adaptive
## FSR2 already performs image reconstruction; never sharpen that output twice.
static func post_sharpen_strength(value: int, method: String, adaptive: bool) -> float:
	if method == "forward_plus" and adaptive:
		return 0.0
	return float(profile(value)["sharpen_strength"])


## Fast path for frame-rate adjustment; no scene-node, texture, LOD or
## streamer changes are performed here.
static func apply_resolution(viewport: Viewport,
		render_scale: float = -1.0, adaptive: bool = false) -> void:
	var renderer: String = str(RenderingServer.get_current_rendering_method())
	GraphicsResolution.apply(viewport,
		GraphicsResolution.plan(renderer, profile(_level), render_scale, adaptive))


static func apply(viewport: Viewport, atmosphere: Node3D,
		post_material: ShaderMaterial, water: MeshInstance3D = null,
		streamer: Node = null, render_scale: float = -1.0,
		adaptive: bool = false) -> void:
	var p := profile(_level)
	# One global uniform adjusts every streamed terrain chunk; no resource reimport or per-chunk updates.
	RenderingServer.global_shader_parameter_set(&"aa_terrain_detail_radius", float(p["terrain_detail_radius"]))
	RenderingServer.global_shader_parameter_set(&"aa_ground_contact_strength", float(p["ground_contact_strength"]))
	# Rain ripples share one shader uniform across every streamed terrain material.
	# Zero on Performance: the expensive per-pixel ring work is skipped entirely.
	RenderingServer.global_shader_parameter_set(&"aa_puddle_ripple_strength",
		float(p["puddle_ripple_strength"]))
	RenderingServer.global_shader_parameter_set(&"aa_terrain_layer_budget", int(p["terrain_layer_budget"]))
	# Only High/Ultra near cliffs sample three extra rock normal projections.
	RenderingServer.global_shader_parameter_set(&"aa_cliff_normal_quality",
		float(p["cliff_normal_quality"]))
	# Shared normal-variance filter is completely disabled on low-end presets.
	RenderingServer.global_shader_parameter_set(&"aa_specular_aa_strength",
		float(p["specular_aa_strength"]))
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
	# The active backend can differ from ProjectSettings after a driver fallback.
	var method := RenderingServer.get_current_rendering_method()
	# One shared sun atlas across the process. Only change its allocation when
	# the resolved quality/backend budget differs; Auto may apply repeatedly.
	GraphicsShadowAtlas.apply(_level, str(method))
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
	if atmosphere != null:
		# The atmosphere owns the persistent shadow enable flag used by its day/night update.
		# Applying only to the sun node would let nighttime weather restore shadows on Performance.
		var atmosphere_profile: Dictionary = p.duplicate()
		atmosphere_profile["sky_radiance"] = world_profile["sky_radiance"]
		# Populate the cached-sky fast path and directional sunset haze budget.
		atmosphere_profile["sky_use_cached_radiance"] = world_profile["sky_use_cached_radiance"]
		atmosphere_profile["sky_scattering_strength"] = world_profile["sky_scattering_strength"]
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
		var env := atmosphere.get("environment") as Environment
		if env != null:
			env.glow_enabled = p["glow"]
			# Fixed quality tiers trade contact AO and indirect bounce against GPU cost.
			# This overwrites Atmosphere's startup defaults on every preset change.
			GraphicsIndirectLighting.apply(env, _level, str(method))
		# Keep the cinematic shadow/fog budget tied to the active renderer,
		# not merely to the requested quality preset.
		GraphicsLighting.apply(sun, env, _level, method)
		# Hybrid sky + screen-space reflections on High/Ultra Forward+ only.
		# Runtime changes (including Auto) also turn SSR off when required.
		GraphicsReflections.apply(env, _level, method)
	if post_material != null:
		post_material.set_shader_parameter("blur_quality", p["blur_quality"])
		post_material.set_shader_parameter("blur_radius", p["blur_radius"])
		post_material.set_shader_parameter("sharpen_strength", post_sharpen_strength(_level, method, adaptive))
		# Sub-LSB output dither is fused into the existing grade pass. Auto
		# resolution and renderer switching cannot leave stale grain enabled.
		post_material.set_shader_parameter("deband_strength", float(p["deband_strength"]))
	# Texture-group-style anisotropy on expensive terrain samplers only:
	# Performance/Balanced use trilinear; High sharpens color at grazing
	# angles; Ultra also filters normal detail. Existing chunk road/biome
	# maps are kept in place when a preset is switched.
	ChunkView.configure_terrain_filter(_level)
	if viewport != null:
		for terrain in viewport.get_tree().get_nodes_in_group(ChunkView.TERRAIN_GROUP):
			ChunkView.apply_terrain_filter(terrain)
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
	if viewport != null:
		for batch in viewport.get_tree().get_nodes_in_group(ChunkView.SCENERY_GROUP):
			if batch is MultiMeshInstance3D:
				ChunkView.apply_scenery_detail(batch)

	# The graphics profiles also control water detail and how many terrain chunks are streamed.
	if water != null and water.material_override is ShaderMaterial:
		var water_shader := water.material_override as ShaderMaterial
		# High/Ultra Forward+ get real scene refraction. The low shader does
		# not declare a screen sampler, so it cannot force a buffer copy.
		WaterRefraction.apply(water_shader, world_profile, _level, str(method))
		water_shader.set_shader_parameter("ripple_strength", float(world_profile["water_ripples"]))
		# Only high-frequency ocean detail is faded, not the large waves,
		# shoreline transparency, Fresnel or the physically lit reflections.
		water_shader.set_shader_parameter("detail_fade_start", float(world_profile["water_detail_start"]))
		water_shader.set_shader_parameter("detail_fade_end", float(world_profile["water_detail_end"]))
		water_shader.set_shader_parameter("shore_glimmer_strength", float(world_profile["shore_glimmer_strength"]))
		water_shader.set_shader_parameter("shore_glimmer_fade_start", float(world_profile["shore_glimmer_start"]))
		water_shader.set_shader_parameter("shore_glimmer_fade_end", float(world_profile["shore_glimmer_end"]))
	if streamer != null:
		streamer.set("load_radius", float(world_profile["chunk_radius"]))
		streamer.set("unload_radius", float(world_profile["chunk_unload"]))
