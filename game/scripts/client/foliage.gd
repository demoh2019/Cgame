extends RefCounted
## Wind for the nature kit: a copy of a mesh whose materials sway with the wind, strongest at the tips.
## The textures and alpha cut-outs of the original materials are kept.

const SHADER_CODE := """
shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform vec4 albedo_color : source_color = vec4(1.0);
uniform float sway = 0.12;
uniform float height_ref = 4.0;
uniform float scissor = 0.5;
uniform bool cut_out = false;
void vertex() {
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float k = clamp(VERTEX.y / height_ref, 0.0, 1.0);
	k *= k;
	float phase = TIME * 1.5 + w.x * 0.33 + w.z * 0.27;
	VERTEX.x += (sin(phase) + 0.4 * sin(phase * 2.3)) * sway * k;
	VERTEX.z += cos(phase * 0.83) * sway * 0.7 * k;
}
void fragment() {
	vec4 t = texture(albedo_tex, UV) * albedo_color;
	ALBEDO = t.rgb;
	ROUGHNESS = 0.9;
	if (cut_out) {
		ALPHA = t.a;
		ALPHA_SCISSOR_THRESHOLD = scissor;
	}
}
"""

static var _shader: Shader
static var _cache: Dictionary = {}


## A swaying copy of `source` (cached by key). `sway` is the tip displacement in meters.
static func swayed(source: Mesh, key: String, sway: float) -> Mesh:
	if source == null:
		return null
	if _cache.has(key):
		return _cache[key]
	if _shader == null:
		_shader = Shader.new()
		_shader.code = SHADER_CODE
	var copy: ArrayMesh = ArrayMesh.new()
	var height := maxf(source.get_aabb().size.y, 0.1)
	for surface in source.get_surface_count():
		var arrays := source.surface_get_arrays(surface)
		copy.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var base := source.surface_get_material(surface)
		if base is BaseMaterial3D:
			var standard := base as BaseMaterial3D
			var material := ShaderMaterial.new()
			material.shader = _shader
			material.set_shader_parameter("sway", sway)
			material.set_shader_parameter("height_ref", height)
			material.set_shader_parameter("albedo_color", standard.albedo_color)
			if standard.albedo_texture != null:
				material.set_shader_parameter("albedo_tex", standard.albedo_texture)
			var cut: bool = standard.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED
			material.set_shader_parameter("cut_out", cut)
			material.set_shader_parameter("scissor", standard.alpha_scissor_threshold if standard.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR else 0.5)
			copy.surface_set_material(surface, material)
		elif base != null:
			copy.surface_set_material(surface, base)
	_cache[key] = copy
	return copy
