extends RefCounted
## User-selectable visual fidelity. Both the Compatibility and Forward+ renderers remain supported.
## Keep the choice local to the client; it must never affect authoritative simulation.

const SETTINGS_PATH := "user://albion_after_graphics.cfg"
const NAMES := ["Performance", "Balanced", "High", "Ultra"]
const VisualProfiles = preload("res://scripts/client/graphics_profiles.gd")
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
			return {"shadows": false, "shadow_distance": 45.0, "msaa": Viewport.MSAA_3D_DISABLED,
				"blur_quality": 0, "blur_radius": 0.0, "glow": false, "ssao": false, "ssil": false,
				"scale": 0.59, "grass_radius": 66.0, "grass_budget": 1500, "grass_fade_start": 25.0, "grass_fade_end": 40.0}
		1:
			return {"shadows": true, "shadow_distance": 70.0, "msaa": Viewport.MSAA_3D_DISABLED,
				"blur_quality": 1, "blur_radius": 1.6, "glow": false, "ssao": false, "ssil": false,
				"scale": 0.77, "grass_radius": 90.0, "grass_budget": 2200, "grass_fade_start": 40.0, "grass_fade_end": 60.0}
		2:
			return {"shadows": true, "shadow_distance": 110.0, "msaa": Viewport.MSAA_3D_2X,
				"blur_quality": 2, "blur_radius": 2.6, "glow": true, "ssao": false, "ssil": false,
				"scale": 1.0, "grass_radius": 116.0, "grass_budget": 3000, "grass_fade_start": 54.0, "grass_fade_end": 80.0}
		_:
			return {"shadows": true, "shadow_distance": 140.0, "msaa": Viewport.MSAA_3D_4X,
				"blur_quality": 2, "blur_radius": 3.0, "glow": true, "ssao": true, "ssil": true,
				"scale": 1.0, "grass_radius": 140.0, "grass_budget": 4000, "grass_fade_start": 66.0, "grass_fade_end": 94.0}


static func apply(viewport: Viewport, atmosphere: Node3D, post_material: ShaderMaterial, water: MeshInstance3D = null, streamer: Node = null) -> void:
	var p := profile(_level)
	var visuals: Dictionary = VisualProfiles.settings(_level)
	# The active backend can differ from ProjectSettings after a driver fallback.
	var method := RenderingServer.get_current_rendering_method()
	if viewport != null:
		if method == "forward_plus" and _level <= 1:
			# FSR2 provides temporal antialiasing. Combining it with MSAA/TAA wastes GPU time.
			viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR2
			viewport.scaling_3d_scale = float(p["scale"])
			viewport.use_taa = false
			viewport.msaa_3d = Viewport.MSAA_3D_DISABLED
			viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
		elif method == "mobile" and _level <= 1:
			viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR
			viewport.scaling_3d_scale = float(p["scale"])
			viewport.use_taa = false
			viewport.msaa_3d = Viewport.MSAA_3D_DISABLED
			viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
		else:
			# Native resolution on High/Ultra and on Compatibility (which lacks FSR2).
			if method == "forward_plus" or method == "mobile":
				viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
				viewport.scaling_3d_scale = 1.0
				viewport.use_taa = false
			viewport.msaa_3d = p["msaa"]
			viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if _level <= 1 else Viewport.SCREEN_SPACE_AA_DISABLED
	if atmosphere != null:
		if atmosphere.has_method("apply_graphics_profile"):
			var settings: Dictionary = p.duplicate()
			settings["sky_radiance"] = visuals["sky_radiance"]
			atmosphere.call("apply_graphics_profile", settings)
		var sun := atmosphere.get("sun") as DirectionalLight3D
		if sun != null:
			sun.shadow_enabled = p["shadows"]
			sun.directional_shadow_max_distance = p["shadow_distance"]
		var env := atmosphere.get("environment") as Environment
		if env != null:
			env.glow_enabled = p["glow"]
			env.ssao_enabled = bool(p["ssao"]) and method == "forward_plus"
			env.ssil_enabled = bool(p["ssil"]) and method == "forward_plus"
	if post_material != null:
		post_material.set_shader_parameter("blur_quality", p["blur_quality"])
		post_material.set_shader_parameter("blur_radius", p["blur_radius"])
	# Reuse the existing LOD and streaming system rather than rebuilding terrain.
	ChunkView.configure_grass(float(visuals["grass_build_radius"]), int(visuals["grass_budget_usec"]),
			float(visuals["grass_fade_start"]), float(visuals["grass_fade_end"]))
	if water != null:
		var water_shader := water.material_override as ShaderMaterial
		if water_shader != null:
			water_shader.set_shader_parameter("ripple_strength", float(visuals["water_ripples"]))
	if streamer != null:
		streamer.set("load_radius", float(visuals["chunk_radius"]))
		streamer.set("unload_radius", float(visuals["chunk_unload"]))
	if viewport != null:
		for tile in viewport.get_tree().get_nodes_in_group(ChunkView.GRASS_GROUP):
			if tile is MultiMeshInstance3D:
				tile.visibility_range_end = ChunkView.grass_visibility_end
