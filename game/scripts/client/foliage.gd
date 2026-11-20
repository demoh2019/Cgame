extends RefCounted
## Wind for the nature kit: a copy of a mesh whose materials sway with the wind, strongest at the tips.
## The textures and alpha cut-outs of the original materials are kept.

const SHADER_CODE := """
shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;
#include "res://assets/shaders/cloud_shadow.gdshaderinc"
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform vec4 albedo_color : source_color = vec4(1.0);
uniform float sway = 0.12;
uniform float height_ref = 4.0;
uniform float scissor = 0.5;
uniform bool cut_out = false;
uniform bool red_to_green = false;
uniform bool instance_tinted = false; // Decor MultiMeshes carry a per-instance colour; other meshes may have dark vertex colours.
varying vec3 instance_tint;
varying vec3 plant_hue;
varying vec2 cloud_xz;
void vertex() {
	instance_tint = instance_tinted ? COLOR.rgb : vec3(1.0);
	// Every plant a slightly different green (some yellower, some bluer, some darker), as in a real wood: identical
	// copies of one tree are what make a forest look artificial.
	vec2 root = MODEL_MATRIX[3].xz;
	float h1 = fract(sin(dot(root, vec2(12.9898, 78.233))) * 43758.5453);
	float h2 = fract(sin(dot(root, vec2(39.346, 11.135))) * 24634.6345);
	plant_hue = mix(vec3(0.86, 0.94, 0.86), vec3(1.1, 1.06, 0.84), h1) * mix(0.84, 1.08, h2);
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	cloud_xz = w.xz;
	float k = clamp(VERTEX.y / height_ref, 0.0, 1.0);
	k *= k;
	float phase = TIME * 1.5 + w.x * 0.33 + w.z * 0.27;
	VERTEX.x += (sin(phase) + 0.4 * sin(phase * 2.3)) * sway * k;
	VERTEX.z += cos(phase * 0.83) * sway * 0.7 * k;
}
void fragment() {
	vec4 t = texture(albedo_tex, UV) * albedo_color;
	if (red_to_green) {
		// The red autumn leaves become a natural summer green: their brightness drives a deep-to-sunlit leaf ramp, so the
		// shading of the painted leaves stays and the colour is never the acid green of a plain channel swap.
		float lum = clamp(dot(t.rgb, vec3(0.6, 0.3, 0.1)) * 1.25, 0.0, 1.0);
		t.rgb = mix(vec3(0.09, 0.17, 0.06), vec3(0.44, 0.58, 0.21), lum);
	}
	vec3 hue = cut_out ? plant_hue : mix(vec3(1.0), plant_hue, 0.35);
	ALBEDO = apply_cloud_shadow(t.rgb * instance_tint * hue, cloud_xz, TIME);
	// Both sides of a blade are lit as if they faced the viewer: otherwise half the grass turns black.
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}
	ROUGHNESS = 0.9;
	if (cut_out) {
		ALPHA = t.a;
		ALPHA_SCISSOR_THRESHOLD = scissor;
	}
}
"""

static var _shader: Shader
static var _cache: Dictionary = {}


## A swaying copy of `source` (cached by key). `sway` is the tip displacement in meters. `tinted`: multiply by the
## MultiMesh instance colour.
static func swayed(source: Mesh, key: String, sway: float, tinted: bool = false) -> Mesh:
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
			material.set_shader_parameter("instance_tinted", tinted)
			material.set_shader_parameter("height_ref", height)
			material.set_shader_parameter("albedo_color", standard.albedo_color)
			var texture: Texture2D = standard.albedo_texture
			# The kit's twisted-tree leaves (also on Bush_Common) are autumn red; this world is green, so the shader turns
			# them green (red and green swapped keeps the shape and shading of the leaves).
			material.set_shader_parameter("red_to_green", texture != null and texture.resource_path.ends_with("Leaves_TwistedTree_C.png"))
			if texture != null:
				material.set_shader_parameter("albedo_tex", texture)
			var cut: bool = standard.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED
			material.set_shader_parameter("cut_out", cut)
			material.set_shader_parameter("scissor", standard.alpha_scissor_threshold if standard.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR else 0.5)
			copy.surface_set_material(surface, material)
		elif base != null:
			copy.surface_set_material(surface, base)
	_cache[key] = copy
	return copy
