extends RefCounted
## Pure graphics detail budgets used by graphics_quality.gd.
## Gameplay simulation and the single persisted quality preference remain unchanged.

const PRESETS := [
	{"sky_radiance": 32, "sky_refresh_interval": 0.7, "grass_build_radius": 70.0, "grass_fade_start": 26.0,
		"grass_fade_end": 40.0, "grass_budget_usec": 2000,
		"water_ripples": 0.0, "tree_shadow_radius": 0.0, "bush_shadow_radius": 0.0,
		"structure_shadow_radius": 0.0, "chunk_radius": 125.0, "chunk_unload": 190.0},
	{"sky_radiance": 64, "sky_refresh_interval": 0.5, "grass_build_radius": 95.0, "grass_fade_start": 38.0,
		"grass_fade_end": 56.0, "grass_budget_usec": 2500,
		"water_ripples": 0.22, "tree_shadow_radius": 48.0, "bush_shadow_radius": 26.0,
		"structure_shadow_radius": 68.0, "chunk_radius": 150.0, "chunk_unload": 220.0},
	{"sky_radiance": 64, "sky_refresh_interval": 0.3, "grass_build_radius": 110.0, "grass_fade_start": 44.0,
		"grass_fade_end": 60.0, "grass_budget_usec": 5000,
		"water_ripples": 0.35, "tree_shadow_radius": 78.0, "bush_shadow_radius": 46.0,
		"structure_shadow_radius": 102.0, "chunk_radius": 165.0, "chunk_unload": 235.0},
	{"sky_radiance": 128, "sky_refresh_interval": 0.2, "grass_build_radius": 130.0, "grass_fade_start": 56.0,
		"grass_fade_end": 75.0, "grass_budget_usec": 8000,
		"water_ripples": 0.48, "tree_shadow_radius": 112.0, "bush_shadow_radius": 70.0,
		"structure_shadow_radius": 138.0, "chunk_radius": 190.0, "chunk_unload": 265.0},
]


static func settings(level: int) -> Dictionary:
	return PRESETS[clampi(level, 0, PRESETS.size() - 1)].duplicate(true)
