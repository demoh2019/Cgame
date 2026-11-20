extends RefCounted
## Wind for the nature kit: a copy of a mesh whose materials sway with the wind, strongest at the tips.
## The textures and alpha cut-outs of the original materials are kept.

const SHADER_CODE := """
shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;
#include "res://assets/shaders/cloud_shadow.gdshaderinc"
global uniform float aa_weather_wetness;
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform vec4 albedo_color : source_color = vec4(1.0);
uniform float sway = 0.12;
uniform float height_ref = 4.0;
// Small movements disappear below a pixel at this range; avoid distant trigonometry.
uniform float wind_fade_start = 48.0;
uniform float wind_fade_end = 120.0;
uniform float scissor = 0.5;
uniform bool cut_out = false;
uniform bool red_to_green = false;
uniform bool instance_tinted = false; // Decor MultiMeshes carry a per-instance colour; other meshes may have dark vertex colours.
varying vec3 instance_tint;
varying vec3 plant_hue;
varying vec2 cloud_xz;
varying float plant_roughness;
void vertex() {
	instance_tint = instance_tinted ? COLOR.rgb : vec3(1.0);
	// World-space plant roots give every MultiMesh instance stable colour and gust phase.
	vec2 root = MODEL_MATRIX[3].xz;
	// Two cheap arithmetic hashes replace a per-vertex sine while retaining stable per-tree colour.
	vec2 hash_uv = fract(root * vec2(0.1031, 0.11369));
	hash_uv += vec2(dot(hash_uv, hash_uv.yx + vec2(19.19)));
	float h1 = fract(hash_uv.x * hash_uv.y);
	float h2 = fract(h1 * 31.37 + 0.173); // A decorrelated shade and roughness without texture fetches.
	plant_hue = mix(vec3(0.86, 0.94, 0.86), vec3(1.1, 1.06, 0.84), h1) * mix(0.84, 1.08, h2);
	plant_roughness = mix(0.83, 0.93, h2);
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	cloud_xz = w.xz;

	// Shader-side wind LOD has no CPU work and no geometry rebuild when the camera moves.
	// Use the root, not each vertex, for the low-frequency wind: the entire crown
	// bends together instead of looking like disconnected branches.
	float distance_to_camera = length(root - CAMERA_POSITION_WORLD.xz);
	float wind_lod = 1.0 - smoothstep(wind_fade_start, wind_fade_end, distance_to_camera);
	if (wind_lod > 0.001 && sway > 0.0) {
		float k = clamp(VERTEX.y / height_ref, 0.0, 1.0);
		k *= k; // Keep trunks steady; move light tips.
		float gust = 0.78 + 0.22 * sin(TIME * 0.46 + dot(root, vec2(0.047, 0.034)));
		float phase = TIME * 1.45 + dot(root, vec2(0.23, 0.19));
		// Existing weather blending supplies a smooth storm strength with no per-plant CPU updates.
		float storm_wind = 1.0 + clamp(aa_weather_wetness, 0.0, 1.0) * 0.65;
		float amount = sway * k * gust * wind_lod * storm_wind;
		VERTEX.x += sin(phase) * amount;
		VERTEX.z += cos(phase * 0.84) * amount * 0.7;
	}
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
	// Nonuniform micro-roughness breaks up overly identical highlights at no texture cost.
	ROUGHNESS = cut_out ? plant_roughness : 0.93;
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
