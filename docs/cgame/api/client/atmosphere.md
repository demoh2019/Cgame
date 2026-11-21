# atmosphere.gd

> (no header comment)

`res://scripts/client/atmosphere.gd`

## Constants

- `const CloudShadowLut = preload("res://scripts/client/cloud_shadow_lut.gd")`
- `const SkyRainbow = preload("res://scripts/client/sky_rainbow.gd")`
- `const SkyAurora = preload("res://scripts/client/sky_aurora.gd")`
- `const GraphicsWhiteBalance = preload("res://scripts/client/graphics_white_balance.gd")`
- `const SkyFogHarmony = preload("res://scripts/client/sky_fog_harmony.gd")`
- `const WaterCaustics = preload("res://scripts/client/water_caustics.gd")`
- `const Moisture = preload("res://scripts/client/weather_surface_memory.gd")`
- `const CinematicColorGrade = preload("res://scripts/client/cinematic_color_grade.gd")`
- `const CinematicBloom = preload("res://scripts/client/cinematic_bloom.gd")`
- `const VegetationWind = preload("res://scripts/client/vegetation_wind.gd")`
- `const CinematicFog = preload("res://scripts/client/cinematic_fog.gd")`
- `const SunShadowQuality = preload("res://scripts/client/sun_shadow_quality.gd")`
- `const BiomeAtmosphere = preload("res://scripts/client/biome_atmosphere.gd")`
- `const SunShadowAtmosphere = preload("res://scripts/client/sun_shadow_atmosphere.gd")`
- `const MoonVisuals = preload("res://scripts/client/moon_visuals.gd")`
- `const LightningFlash = preload("res://scripts/client/graphics_lightning_flash.gd")`
- `const GraphicsEyeAdaptation = preload("res://scripts/client/graphics_eye_adaptation.gd")`
- `const GraphicsCinematicDof = preload("res://scripts/client/graphics_cinematic_dof.gd")`
- `const SolarIrradiance = preload("res://scripts/client/solar_irradiance.gd")`
- `const SHADOW_FILTER_INTERVAL := 0.25`
- `const BLOOM_INTERVAL := 0.20`
- `const NIGHT_TOP := Color(0.01, 0.015, 0.05)`
- `const NIGHT_HORIZON := Color(0.04, 0.05, 0.11)`
- `const DAY_TOP := Color(0.2, 0.4, 0.78)`
- `const DAY_HORIZON := Color(0.66, 0.78, 0.9)`
- `const DUSK_HORIZON := Color(1.0, 0.55, 0.28)`
- `const STORM_TOP := Color(0.24, 0.27, 0.32)`
- `const STORM_HORIZON := Color(0.45, 0.48, 0.52)`

## Documented variables

- `var _sky_refresh_interval := 0.4` - Slow-moving sky lighting is cached separately from per-frame directional light and fog.

## Functions

### `update`

```gdscript
func update(daylight: float, sun_height: float, phase: float, storming: bool, delta: float, wind: Vector2 = Vector2.ZERO, biome: String = "plains", moon_phase: float = 0.5) -> void
```

`daylight` 0..1 (0 night), `sun_height` -1..1, `phase` 0..1 around the day, `storming` whether it is stormy here.

### `trigger_lightning`

```gdscript
func trigger_lightning(distance_m: float) -> void
```

Called only for an authenticated lightning_struck event from the server
(or the same authoritative local simulation), never every rain frame.

### `apply_graphics_profile`

```gdscript
func apply_graphics_profile(settings: Dictionary) -> void
```

Render-only switches; weather and the shared day/night clock are unaffected.

_1 private function(s) starting with `_` are not listed._
