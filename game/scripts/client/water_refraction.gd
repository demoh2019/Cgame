extends RefCounted
## Two cacheable variants of the same ocean shader. On low presets and
## non-Forward+ backends the screen sampler is preprocessed away.
const BASE_SHADER = preload("res://assets/shaders/water.gdshader")
static var _high_shader: Shader


static func enabled(level: int, method: String) -> bool:
	return level >= 2 and method == "forward_plus"


static func shader_for(level: int, method: String) -> Shader:
	if not enabled(level, method):
		return BASE_SHADER
	if _high_shader == null:
		_high_shader = Shader.new()
		# Cache once; toggling presets never recompiles a shader per chunk.
		_high_shader.code = BASE_SHADER.code.replace(
			"shader_type spatial;",
			"shader_type spatial;\n#define WATER_REFRACTION")
	return _high_shader


static func apply(material: ShaderMaterial, profile: Dictionary,
		level: int, method: String) -> void:
	if material == null:
		return
	var target: Shader = shader_for(level, method)
	if material.shader != target:
		material.shader = target
	if enabled(level, method):
		# Uses the same premium Forward+ shader/variant as scene refraction;
		# both the explicit anisotropic BRDF and its tangent frame are absent
		# from the Performance/Balanced/Compatibility source after preprocessing.
		material.set_shader_parameter("wind_anisotropy_strength",
			clampf(float(profile.get("water_anisotropy_strength", 0.0)), 0.0, 0.45))
		material.set_shader_parameter("refraction_strength",
			clampf(float(profile.get("water_refraction_strength", 0.0)), 0.0, 1.0))
		material.set_shader_parameter("refraction_fade_start",
			maxf(0.0, float(profile.get("water_refraction_start", 25.0))))
		material.set_shader_parameter("refraction_fade_end",
			maxf(1.0, float(profile.get("water_refraction_end", 74.0))))
