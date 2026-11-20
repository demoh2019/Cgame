extends RefCounted
## Renderer-aware screen refraction. Keep the original shader on Performance,
## Balanced and Compatibility: only the advanced variant declares a screen
## texture, so low-end rendering does not trigger a 3D framebuffer copy.

const BASE_WATER = preload("res://assets/shaders/water.gdshader")
const REFRACTIVE_WATER = preload("res://assets/shaders/water_refractive.gdshader")


static func settings(level: int, rendering_method: String) -> Dictionary:
	var tier: int = clampi(level, 0, 3)
	var enabled: bool = rendering_method == "forward_plus" and tier >= 2
	return {
		"enabled": enabled,
		"strength": 0.0 if not enabled else (0.025 if tier == 2 else 0.040),
		"fade_start": 28.0 if tier == 2 else 52.0,
		"fade_end": 70.0 if tier == 2 else 110.0,
		"max_depth": 3.5 if tier == 2 else 5.0,
	}


## Shader switches only when changing quality; no material duplication or
## scene recreation. The caller reapplies existing wave/glimmer parameters.
static func apply(material: ShaderMaterial, level: int, rendering_method: String) -> void:
	if material == null:
		return
	var p: Dictionary = settings(level, rendering_method)
	var chosen: Shader = REFRACTIVE_WATER if bool(p["enabled"]) else BASE_WATER
	if material.shader != chosen:
		material.shader = chosen
	if not bool(p["enabled"]):
		return
	material.set_shader_parameter("refraction_strength", float(p["strength"]))
	material.set_shader_parameter("refraction_fade_start", float(p["fade_start"]))
	material.set_shader_parameter("refraction_fade_end", float(p["fade_end"]))
	material.set_shader_parameter("refraction_max_depth", float(p["max_depth"]))
