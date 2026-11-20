extends RefCounted
## Per-device rendering presets. Visual-only settings never affect the authoritative world simulation.
## Compatibility remains the default renderer; Forward+ effects are opt-in when supported by the renderer.

const CONFIG_PATH := "user://graphics.cfg"
const DEFAULT_LEVEL := 1
const NAMES := ["Performance", "Balanced", "High", "Ultra"]
const PRESETS := [
	{"shadows": false, "shadow_distance": 48.0, "glow": false, "ssao": false, "sky_radiance": 32,
		"grass_build_radius": 70.0, "grass_fade_start": 26.0, "grass_fade_end": 40.0, "grass_budget_usec": 2500,
		"post_blur": 0.0, "water_ripples": 0.0, "chunk_radius": 125.0, "chunk_unload": 190.0},
	{"shadows": true, "shadow_distance": 92.0, "glow": true, "ssao": false, "sky_radiance": 64,
		"grass_build_radius": 95.0, "grass_fade_start": 38.0, "grass_fade_end": 56.0, "grass_budget_usec": 5000,
		"post_blur": 1.2, "water_ripples": 0.22, "chunk_radius": 150.0, "chunk_unload": 220.0},
	{"shadows": true, "shadow_distance": 110.0, "glow": true, "ssao": true, "sky_radiance": 64,
		"grass_build_radius": 110.0, "grass_fade_start": 44.0, "grass_fade_end": 60.0, "grass_budget_usec": 8000,
		"post_blur": 2.6, "water_ripples": 0.35, "chunk_radius": 165.0, "chunk_unload": 235.0},
	{"shadows": true, "shadow_distance": 145.0, "glow": true, "ssao": true, "sky_radiance": 128,
		"grass_build_radius": 130.0, "grass_fade_start": 56.0, "grass_fade_end": 75.0, "grass_budget_usec": 10000,
		"post_blur": 3.0, "water_ripples": 0.48, "chunk_radius": 190.0, "chunk_unload": 265.0},
]


static func normalized(level: int) -> int:
	return clampi(level, 0, NAMES.size() - 1)


static func name_for(level: int) -> String:
	return NAMES[normalized(level)]


static func settings(level: int) -> Dictionary:
	return PRESETS[normalized(level)].duplicate(true)


static func load_saved() -> int:
	var config := ConfigFile.new()
	if config.load(CONFIG_PATH) != OK:
		return DEFAULT_LEVEL
	var value: Variant = config.get_value("graphics", "level", DEFAULT_LEVEL)
	if typeof(value) != TYPE_INT:
		return DEFAULT_LEVEL
	return normalized(int(value))


static func save(level: int) -> void:
	var config := ConfigFile.new()
	config.set_value("graphics", "level", normalized(level))
	var error := config.save(CONFIG_PATH)
	if error != OK:
		push_warning("Could not save graphics quality: %s" % error)
