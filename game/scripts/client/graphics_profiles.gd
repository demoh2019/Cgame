extends RefCounted
## Pure graphics detail budgets used by graphics_quality.gd.
## Gameplay simulation and the single persisted quality preference remain unchanged.

const PRESETS := [
	{"sky_radiance": 32, "sky_use_cached_radiance": true, "sky_refresh_interval": 0.7, "sky_scattering_strength": 0.0, "atmospheric_lut_strength": 0.0, "moon_detail_strength": 0.0, "cirrus_detail": 0, "cirrus_opacity": 0.00, "grass_build_radius": 70.0, "grass_fade_start": 26.0,
		"grass_fade_end": 40.0, "grass_budget_usec": 2000,
		"water_ripples": 0.0, "shallow_scattering_strength": 0.0, "wind_wave_strength": 0.0, "water_refraction_strength": 0.00, "water_refraction_start": 12.0, "water_refraction_end": 22.0, "wet_leaf_gloss": 0.0, "leaf_transmission": 0.0, "grass_transmission": 0.0, "grass_normal_wind": 0.00, "canopy_occlusion": 0.42, "water_detail_start": 20.0, "water_detail_end": 45.0, "shore_glimmer_strength": 0.0, "shore_surf_strength": 0.0, "shore_glimmer_start": 12.0, "shore_glimmer_end": 22.0, "tree_shadow_radius": 0.0, "bush_shadow_radius": 0.0,
		"structure_shadow_radius": 0.0, "chunk_radius": 125.0, "chunk_unload": 190.0},
	{"sky_radiance": 64, "sky_use_cached_radiance": true, "sky_refresh_interval": 0.5, "sky_scattering_strength": 0.35, "atmospheric_lut_strength": 0.0, "moon_detail_strength": 0.35, "cirrus_detail": 1, "cirrus_opacity": 0.22, "grass_build_radius": 95.0, "grass_fade_start": 38.0,
		"grass_fade_end": 56.0, "grass_budget_usec": 2500,
		"water_ripples": 0.22, "shallow_scattering_strength": 0.13, "wind_wave_strength": 0.0, "water_refraction_strength": 0.00, "water_refraction_start": 18.0, "water_refraction_end": 30.0, "wet_leaf_gloss": 0.35, "leaf_transmission": 0.28, "grass_transmission": 0.10, "grass_normal_wind": 0.28, "canopy_occlusion": 0.32, "water_detail_start": 40.0, "water_detail_end": 85.0, "shore_glimmer_strength": 0.0, "shore_surf_strength": 0.0, "shore_glimmer_start": 18.0, "shore_glimmer_end": 30.0, "tree_shadow_radius": 48.0, "bush_shadow_radius": 26.0,
		"structure_shadow_radius": 68.0, "chunk_radius": 150.0, "chunk_unload": 220.0},
	{"sky_radiance": 64, "sky_use_cached_radiance": false, "sky_refresh_interval": 0.3, "sky_scattering_strength": 0.7, "atmospheric_lut_strength": 0.52, "moon_detail_strength": 0.70, "cirrus_detail": 1, "cirrus_opacity": 0.38, "grass_build_radius": 110.0, "grass_fade_start": 44.0,
		"grass_fade_end": 60.0, "grass_budget_usec": 5000,
		"water_ripples": 0.35, "shallow_scattering_strength": 0.38, "wind_wave_strength": 0.27, "water_refraction_strength": 0.52, "water_refraction_start": 25.0, "water_refraction_end": 74.0, "wet_leaf_gloss": 0.7, "leaf_transmission": 0.48, "grass_transmission": 0.22, "grass_normal_wind": 0.58, "canopy_occlusion": 0.24, "water_detail_start": 65.0, "water_detail_end": 125.0, "shore_glimmer_strength": 0.45, "shore_surf_strength": 0.58, "shore_glimmer_start": 28.0, "shore_glimmer_end": 62.0, "tree_shadow_radius": 78.0, "bush_shadow_radius": 46.0,
		"structure_shadow_radius": 102.0, "chunk_radius": 165.0, "chunk_unload": 235.0},
	{"sky_radiance": 128, "sky_use_cached_radiance": false, "sky_refresh_interval": 0.2, "sky_scattering_strength": 1.0, "atmospheric_lut_strength": 0.78, "moon_detail_strength": 1.0, "cirrus_detail": 2, "cirrus_opacity": 0.52, "grass_build_radius": 130.0, "grass_fade_start": 56.0,
		"grass_fade_end": 75.0, "grass_budget_usec": 8000,
		"water_ripples": 0.48, "shallow_scattering_strength": 0.72, "wind_wave_strength": 0.45, "water_refraction_strength": 0.86, "water_refraction_start": 42.0, "water_refraction_end": 110.0, "wet_leaf_gloss": 1.0, "leaf_transmission": 0.68, "grass_transmission": 0.36, "grass_normal_wind": 0.85, "canopy_occlusion": 0.18, "water_detail_start": 105.0, "water_detail_end": 195.0, "shore_glimmer_strength": 0.85, "shore_surf_strength": 0.95, "shore_glimmer_start": 44.0, "shore_glimmer_end": 86.0, "tree_shadow_radius": 112.0, "bush_shadow_radius": 70.0,
		"structure_shadow_radius": 138.0, "chunk_radius": 190.0, "chunk_unload": 265.0},
]


static func settings(level: int) -> Dictionary:
	return PRESETS[clampi(level, 0, PRESETS.size() - 1)].duplicate(true)
