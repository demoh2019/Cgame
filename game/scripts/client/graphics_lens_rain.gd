extends RefCounted
## High-end virtual lens rain inspired by Unreal post materials and Unity HDRP.
## Integrates into the existing single post_grade.gdshader, never another
## fullscreen layer. Clear weather and low-end hardware take the no-op path.
##
## Dynamic gameplay comes from already-smoothed atmosphere weather, never
## client-declared network inputs or new simulation state.

const MAX_STRENGTH := 0.60
const START_STORM := 0.38


static func strength_for(storm: float, level: int, method: String,
		underground: bool = false, sheltered: bool = false) -> float:
	if not is_finite(storm) or storm <= START_STORM or underground or sheltered:
		return 0.0
	if method != "forward_plus":
		return 0.0
	var tier: int = clampi(level, 0, 3)
	if tier < 2:
		return 0.0
	var budget: float = 0.32 if tier == 2 else MAX_STRENGTH
	return clampf((storm - START_STORM) / (1.0 - START_STORM), 0.0, 1.0) * budget


## A little horizontal drift from already cached 256m weather wind.
## Wind values are allowed to be zero or corrupt without changing shaders.
static func screen_wind(wind: Vector2) -> Vector2:
	if not wind.is_finite() or wind.length_squared() < 0.000001:
		return Vector2.ZERO
	return wind.normalized() * clampf(wind.length() / 6.0, 0.0, 1.0)


## Called alongside GraphicsColorGrade at most five times per second, and
## only in the online scene that already owns the fullscreen screen copy.
static func apply(material: ShaderMaterial, storm: float, level: int,
		method: String, wind: Vector2, underground: bool = false,
		sheltered: bool = false) -> void:
	if material == null:
		return
	var strength: float = strength_for(storm, level, method, underground, sheltered)
	material.set_shader_parameter("lens_rain_strength", strength)
	material.set_shader_parameter("lens_rain_wind",
		screen_wind(wind) if strength > 0.0 else Vector2.ZERO)
