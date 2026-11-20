extends RefCounted
## User-selectable visual fidelity. Both the Compatibility and Forward+ renderers remain supported.
## Keep the choice local to the client; it must never affect authoritative simulation.

const SETTINGS_PATH := "user://albion_after_graphics.cfg"
const NAMES := ["Performance", "Balanced", "High", "Ultra"]

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
				"blur_quality": 0, "blur_radius": 0.0, "glow": false, "ssao": false}
		1:
			return {"shadows": true, "shadow_distance": 70.0, "msaa": Viewport.MSAA_3D_DISABLED,
				"blur_quality": 1, "blur_radius": 1.6, "glow": false, "ssao": false}
		2:
			return {"shadows": true, "shadow_distance": 110.0, "msaa": Viewport.MSAA_3D_2X,
				"blur_quality": 2, "blur_radius": 2.6, "glow": true, "ssao": false}
		_:
			return {"shadows": true, "shadow_distance": 140.0, "msaa": Viewport.MSAA_3D_4X,
				"blur_quality": 2, "blur_radius": 3.0, "glow": true, "ssao": true}


static func apply(viewport: Viewport, atmosphere: Node3D, post_material: ShaderMaterial) -> void:
	var p := profile(_level)
	if viewport != null:
		viewport.msaa_3d = p["msaa"]
		# FXAA makes the lighter presets readable without MSAA's multisample cost.
		viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if _level <= 1 else Viewport.SCREEN_SPACE_AA_DISABLED
	if atmosphere != null:
		var sun := atmosphere.get("sun") as DirectionalLight3D
		if sun != null:
			sun.shadow_enabled = p["shadows"]
			sun.directional_shadow_max_distance = p["shadow_distance"]
		var env := atmosphere.get("environment") as Environment
		if env != null:
			env.glow_enabled = p["glow"]
			# Godot ignores SSAO/glow on Compatibility; keep one profile system for Forward+.
			env.ssao_enabled = p["ssao"]
	if post_material != null:
		post_material.set_shader_parameter("blur_quality", p["blur_quality"])
		post_material.set_shader_parameter("blur_radius", p["blur_radius"])
