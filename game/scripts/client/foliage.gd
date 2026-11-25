extends RefCounted
## Wind for the nature kit: a copy of a mesh whose materials sway with the wind, strongest at the tips.
## The textures and alpha cut-outs of the original materials are kept.

const SHADER_CODE := """
shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;
#include "res://assets/shaders/cloud_shadow.gdshaderinc"
#include "res://assets/shaders/specular_aa.gdshaderinc"
#include "res://assets/shaders/vegetation_wind_space.gdshaderinc"
#include "res://assets/shaders/plant_interaction.gdshaderinc"
#include "res://assets/shaders/foliage_spectral_optics.gdshaderinc"
global uniform float aa_weather_wetness;
global uniform float aa_weather_rain;
global uniform vec3 aa_vegetation_wind;
// Shared quality knob: Performance = matte rain, Ultra = full PBR wet highlights.
global uniform float aa_vegetation_wet_gloss;
// Screen-independent, inexpensive thin-leaf backlight. Performance turns it off.
global uniform float aa_leaf_transmission;
// High/Ultra: cheap Beer-Lambert-like leaf pigments, shared with grass.
global uniform float aa_leaf_optics_quality;
// Shared ambient self-occlusion budget for dense tree crowns.
global uniform float aa_canopy_occlusion;
// Shared tree/bush visibility limits match the actual scene HLOD profiles.
// A zero width disables dithering entirely on low-end hardware.
global uniform float aa_foliage_fade_width;
global uniform float aa_foliage_tree_cull;
global uniform float aa_foliage_bush_cull;
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform vec4 albedo_color : source_color = vec4(1.0);
// Preserve source glTF PBR data. Optional maps are sampled only if actually present.
global uniform float aa_terrain_detail_radius;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D roughness_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D metallic_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D orm_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform bool use_normal_map = false;
uniform bool use_roughness_map = false;
uniform bool use_metallic_map = false;
uniform bool use_orm_map = false;
uniform bool use_vertex_colors = false;
uniform vec4 roughness_mask = vec4(1.0, 0.0, 0.0, 0.0);
uniform vec4 metallic_mask = vec4(1.0, 0.0, 0.0, 0.0);
uniform float material_roughness = 1.0;
uniform float material_metallic = 0.0;
uniform float material_specular = 0.5;
uniform float normal_strength = 1.0;
uniform float sway = 0.12;
uniform float height_ref = 4.0;
uniform float height_min = 0.0;
// 0 = no fade (landmarks/decor), 1 = tree, 2 = bush or berry.
uniform int fade_role = 0;
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
varying float canopy_height;
varying float fade_coverage;

// 4x4 ordered Bayer pattern, without a noise texture or transparent draw.
// Each threshold is stable as the camera moves; the fade is only evaluated
// inside the last few metres of an instance's draw distance.
float ordered_dither_4x4(vec2 fragcoord) {
	vec2 cell = mod(floor(fragcoord), 4.0);
	vec2 low = mod(cell, 2.0);
	vec2 high = floor(cell * 0.5);
	float low_rank = low.x * 2.0 + low.y * 3.0 - 4.0 * low.x * low.y;
	float high_rank = high.x * 2.0 + high.y * 3.0 - 4.0 * high.x * high.y;
	return (low_rank * 4.0 + high_rank + 0.5) * (1.0 / 16.0);
}

void vertex() {
	instance_tint = (instance_tinted || use_vertex_colors) ? COLOR.rgb : vec3(1.0);
	// World-space plant roots give every MultiMesh instance stable colour and gust phase.
	vec2 root = MODEL_MATRIX[3].xz;
	// Two cheap arithmetic hashes replace a per-vertex sine while retaining stable per-tree colour.
	vec2 hash_uv = fract(root * vec2(0.1031, 0.11369));
	hash_uv += vec2(dot(hash_uv, hash_uv.yx + vec2(19.19)));
	float h1 = fract(hash_uv.x * hash_uv.y);
	float h2 = fract(h1 * 31.37 + 0.173); // A decorrelated shade and roughness without texture fetches.
	plant_hue = mix(vec3(0.86, 0.94, 0.86), vec3(1.1, 1.06, 0.84), h1) * mix(0.84, 1.08, h2);
	plant_roughness = mix(0.83, 0.93, h2);
	// Source AABB-relative height avoids changing the look between mountain and
	// valley trees, or between nature-pack and procedural fallback meshes.
	canopy_height = clamp((VERTEX.y - height_min) / max(height_ref, 0.1), 0.0, 1.0);
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	cloud_xz = w.xz;

	// Shader-side wind LOD has no CPU work and no geometry rebuild when the camera moves.
	// Use the root, not each vertex, for the low-frequency wind: the entire crown
	// bends together instead of looking like disconnected branches.
	float distance_to_camera = length(root - CAMERA_POSITION_WORLD.xz);
	fade_coverage = 1.0;
	if (aa_foliage_fade_width > 0.001 && fade_role > 0) {
		float cull_end = fade_role == 1 ? aa_foliage_tree_cull : aa_foliage_bush_cull;
		fade_coverage = 1.0 - smoothstep(cull_end - aa_foliage_fade_width,
			cull_end, distance_to_camera);
	}
	float wind_lod = 1.0 - smoothstep(wind_fade_start, wind_fade_end, distance_to_camera);
	if (wind_lod > 0.001 && sway > 0.0) {
		float wind_power = clamp(aa_vegetation_wind.z, 0.0, 1.0);
		// Sheltered and calm plants need neither trig nor world/local projection.
		if (wind_power > 0.001) {
			float k = clamp(VERTEX.y / height_ref, 0.0, 1.0);
			k *= k; // Keep trunks steady; move light tips.
			vec2 wind_dir = aa_vegetation_wind.xy;
			vec2 crosswind = vec2(-wind_dir.y, wind_dir.x);
			float gust = 0.78 + 0.22 * sin(TIME * 0.46
				+ dot(root, wind_dir * 0.047 + crosswind * 0.012));
			float phase = TIME * (0.95 + wind_power * 0.5)
				+ dot(root, wind_dir * 0.23 + crosswind * 0.07);
			float storm_wind = 1.0 + clamp(aa_weather_rain, 0.0, 1.0) * 0.25;
			float amount = sway * k * gust * wind_lod * storm_wind * wind_power;
			vec2 motion = wind_dir * sin(phase) + crosswind * cos(phase * 0.84) * 0.25;
			// The material's vertices are in LOCAL coordinates. Every imported
			// tree and instanced bush has a different rotation/scale, so bending
			// in world coordinates directly would break the prevailing wind.
			vec2 local_motion = aa_wind_world_to_local_xz(motion * amount, MODEL_MATRIX);
			VERTEX.x += local_motion.x;
			VERTEX.z += local_motion.y;
		}
		// Pushed-aside bushes and shaken (hit / harvested) plants; zero cost while nothing is active.
		vec2 pushed = aa_plant_displacement(root, clamp(VERTEX.y / height_ref, 0.0, 1.0) * wind_lod, TIME);
		if (dot(pushed, pushed) > 0.00001) {
			vec2 pushed_local = aa_wind_world_to_local_xz(pushed, MODEL_MATRIX);
			VERTEX.x += pushed_local.x;
			VERTEX.z += pushed_local.y;
		}
	}
}
void fragment() {
	// Opaque fragment discard avoids alpha-blend sorting and extra screen passes.
	// Zero-width presets skip this branch; near plants skip the Bayer calculation.
	if (fade_coverage < 0.999) {
		if (fade_coverage <= ordered_dither_4x4(FRAGCOORD.xy)) {
			discard;
		}
	}
	vec4 t = texture(albedo_tex, UV) * albedo_color;
	if (red_to_green) {
		// The red autumn leaves become a natural summer green: their brightness drives a deep-to-sunlit leaf ramp, so the
		// shading of the painted leaves stays and the colour is never the acid green of a plain channel swap.
		float lum = clamp(dot(t.rgb, vec3(0.6, 0.3, 0.1)) * 1.25, 0.0, 1.0);
		t.rgb = mix(vec3(0.09, 0.17, 0.06), vec3(0.44, 0.58, 0.21), lum);
	}
	vec3 hue = cut_out ? plant_hue : mix(vec3(1.0), plant_hue, 0.35);
	// Wet leaves and bark darken smoothly while preserving tint, texture and alpha.
	float wet_foliage = clamp(aa_weather_wetness, 0.0, 1.0);
	ALBEDO = apply_cloud_shadow(t.rgb * instance_tint * hue * (1.0 - wet_foliage * 0.17), cloud_xz, TIME);
	// Approximate thin-leaf transmission (Unreal Two-Sided Foliage / Unity HDRP
	// Transmission). Godot's built-in direct-light backlighting uses existing
	// lighting: no extra shadow pass, screen texture, or translucency draw call.
	// Only cut-out foliage receives it; trunks, bark and opaque plants stay PBR.
	BACKLIGHT = vec3(0.0);
	if (cut_out && aa_leaf_transmission > 0.001) {
		// Bright green tissue transmits more light than dark veins. Reuse the
		// existing albedo sample; no additional PBR texture lookups.
		float leaf_mask = smoothstep(0.12, 0.78, dot(t.rgb, vec3(0.23, 0.68, 0.09)));
		// Denser green veins, thin tops and dry pigments transmit different
		// wavelengths. Compute only on premium quality cut-out leaves.
		vec3 spectral = vec3(1.0);
		if (aa_leaf_optics_quality > 0.001) {
			float thickness = mix(1.18, 0.65, leaf_mask)
				* mix(1.13, 0.90, canopy_height);
			spectral = aa_foliage_spectral_filter(t.rgb, thickness,
				aa_leaf_optics_quality);
		}
		BACKLIGHT = t.rgb * instance_tint * hue * leaf_mask * spectral
			* aa_leaf_transmission * (1.0 - wet_foliage * 0.18);
	}
	// Both sides of a blade are lit as if they faced the viewer: otherwise half the grass turns black.
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}
	// Explicit gradients keep mip selection stable in GPU branches.
	vec2 uv_dx = dFdx(UV);
	vec2 uv_dy = dFdy(UV);
	float roughness = material_roughness;
	float metallic = material_metallic;
	float occlusion = 1.0;
	// Used only by the optional roughness filter; tangent-space normal maps
	// contribute to pixel variance without a second normal-map sample.
	vec3 aa_filter_normal = normalize(NORMAL);
	// As in distance-aware layered materials, stop sampling subpixel PBR maps.
	// The same global budget governs terrain, vegetation and runtime graphics presets.
	float pbr_detail = 1.0 - smoothstep(aa_terrain_detail_radius,
		aa_terrain_detail_radius + 24.0, length(cloud_xz - CAMERA_POSITION_WORLD.xz));
	if (pbr_detail > 0.01) {
		if (use_orm_map) {
			// Godot ORM convention: occlusion R, roughness G, metalness B.
			vec3 orm = textureGrad(orm_tex, UV, uv_dx, uv_dy).rgb;
			occlusion = mix(1.0, orm.r, pbr_detail);
			roughness *= mix(1.0, orm.g, pbr_detail);
			metallic *= mix(1.0, orm.b, pbr_detail);
		} else {
			if (use_roughness_map) {
				float map_roughness = dot(textureGrad(roughness_tex, UV, uv_dx, uv_dy), roughness_mask);
				roughness *= mix(1.0, map_roughness, pbr_detail);
			}
			if (use_metallic_map && material_metallic > 0.0) {
				float map_metallic = dot(textureGrad(metallic_tex, UV, uv_dx, uv_dy), metallic_mask);
				metallic *= mix(1.0, map_metallic, pbr_detail);
			}
		}
		// The tangent-space normal is meaningful only on imported surfaces with
		// normal+tangent arrays. Do not pay a texture read for the distant LOD.
		#ifdef AA_FOLIAGE_HAS_TANGENTS
		if (use_normal_map) {
			vec3 normal_sample = textureGrad(normal_tex, UV, uv_dx, uv_dy).rgb;
			NORMAL_MAP = normal_sample;
			NORMAL_MAP_DEPTH = normal_strength * pbr_detail;
			vec3 tangent_normal = normal_sample * 2.0 - 1.0;
			float aa_normal_scale = clamp(normal_strength * pbr_detail, 0.0, 1.0);
			aa_filter_normal = normalize(mix(vec3(0.0, 0.0, 1.0),
				tangent_normal, aa_normal_scale));
		}
		#endif
	}
	// Approximate ambient light lost inside the crown without an extra
	// depth/SSAO pass. Preserve the imported ORM AO and its distance fade.
	float crown_shadow = 0.0;
	if (cut_out && aa_canopy_occlusion > 0.001) {
		float open_sky = smoothstep(0.12, 0.9, canopy_height);
		crown_shadow = clamp(aa_canopy_occlusion, 0.0, 0.5) * (1.0 - open_sky);
	}
	AO = clamp(occlusion * (1.0 - crown_shadow), 0.0, 1.0);
	// Keep the canopy readable on Compatibility where screen-space AO is absent.
	if (cut_out) {
		ALBEDO *= 1.0 - crown_shadow * 0.12;
	}
	float foliage_variation = cut_out ? plant_roughness : 1.0;
	// Only inexpensive PBR parameters change in rain; optional PBR normal/
	// ORM textures, artist alpha and batched geometry are preserved.
	float wet_gloss = wet_foliage * clamp(aa_vegetation_wet_gloss, 0.0, 1.0);
	float final_roughness = clamp(mix(roughness * foliage_variation,
		cut_out ? 0.32 : 0.64, wet_gloss), 0.04, 1.0);
	ROUGHNESS = filter_specular_roughness(final_roughness, aa_filter_normal);
	METALLIC = clamp(metallic, 0.0, 1.0);
	SPECULAR = clamp(mix(material_specular, 0.7, wet_gloss), 0.0, 1.0);
	if (cut_out) {
		ALPHA = t.a;
		ALPHA_SCISSOR_THRESHOLD = scissor;
	}
}
"""

const MeshLOD = preload("res://scripts/client/mesh_lod_preservation.gd")

static var _shader_variants: Dictionary = {} # Normal-map on/off x MSAA coverage on/off.
static var _coverage_enabled := false
static var _alpha_mips_enabled := false
static var _coverage_texture_cache: Dictionary = {} # One optimized texture per source+cutoff.
static var _cache: Dictionary = {}


## Alpha-to-coverage is supported only by the Vulkan renderers with actual MSAA.
## FSR2 provides its own AA and disables MSAA, so that path uses the original shader.
static func supports_alpha_coverage(method: String, msaa: int) -> bool:
	return (method == "forward_plus" or method == "mobile") and msaa != Viewport.MSAA_DISABLED


## Shared shaders: only thin alpha-cutout leaves use the MSAA variant.
## Neither variant adds a texture fetch, a draw call, or a transparent sorting pass.
static func _shader_for_surface(cutout: bool, normal_mapped: bool = false) -> Shader:
	# NORMAL_MAP has a compile-time tangent requirement, even when its runtime
	# use_normal_map uniform is false. Build a tangent-free shader for those meshes.
	var coverage: bool = cutout and _coverage_enabled
	var variant: int = (2 if coverage else 0) + (1 if normal_mapped else 0)
	if not _shader_variants.has(variant):
		var code := SHADER_CODE
		if normal_mapped:
			code = code.replace("shader_type spatial;",
				"shader_type spatial;\n#define AA_FOLIAGE_HAS_TANGENTS")
		if coverage:
			code = code.replace(
				"render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;",
				"render_mode cull_disabled, diffuse_burley, specular_schlick_ggx, alpha_to_coverage;").replace(
				"ALPHA_SCISSOR_THRESHOLD = scissor;",
				"ALPHA_SCISSOR_THRESHOLD = scissor;\n\t\tALPHA_ANTIALIASING_EDGE = 0.3;\n\t\tALPHA_TEXTURE_COORDINATE = UV;")
		var shader := Shader.new()
		shader.code = code
		_shader_variants[variant] = shader
	return _shader_variants[variant] as Shader

## Switching quality changes the shader of already cached instances in place:
## no mesh regeneration, no texture duplication and no world-chunk rebuild.
static func configure_antialiasing(enabled: bool) -> void:
	if _coverage_enabled == enabled:
		return
	_coverage_enabled = enabled
	for mesh in _cache.values():
		if not mesh is ArrayMesh:
			continue
		var geometry := mesh as ArrayMesh
		for surface in geometry.get_surface_count():
			var material := geometry.surface_get_material(surface) as ShaderMaterial
			if material != null and bool(material.get_shader_parameter("cut_out")):
				material.shader = _shader_for_surface(true,
					bool(material.get_meta("aa_foliage_normal_mapped", false)))





## Alpha coverage mipmaps keep small leaves and thin branches visible
## after minification. FSR2 benefits too: this is independent of MSAA.
static func alpha_mipmaps_enabled(quality: int, method: String) -> bool:
	return quality >= 2 and method == "forward_plus"


static func _coverage_texture(source: Texture2D, threshold: float) -> Texture2D:
	if source == null or not _alpha_mips_enabled:
		return source
	# Limit the one-time CPU bake and GPU memory use on Apple Silicon.
	# Large atlas images preserve the original streaming/import path.
	if source.get_width() < 2 or source.get_height() < 2 or \
			source.get_width() > 1024 or source.get_height() > 1024:
		return source
	var cutoff: float = clampf(threshold, 0.05, 0.95)
	var key: String = str(source.get_instance_id()) + ":" + str(roundi(cutoff * 1000.0))
	if _coverage_texture_cache.has(key):
		return _coverage_texture_cache[key] as Texture2D
	var pixels: Image = source.get_image()
	if pixels == null:
		_coverage_texture_cache[key] = source
		return source
	if pixels.is_compressed() and pixels.decompress() != OK:
		_coverage_texture_cache[key] = source
		return source
	if pixels.get_format() != Image.FORMAT_RGBA8:
		pixels.convert(Image.FORMAT_RGBA8)
	if pixels.has_mipmaps():
		pixels.clear_mipmaps()
	if pixels.detect_alpha() == Image.ALPHA_NONE:
		_coverage_texture_cache[key] = source
		return source
	var optimized: Image
	if pixels.has_method("create_alpha_coverage_mipmaps"):
		optimized = pixels.call("create_alpha_coverage_mipmaps", cutoff) as Image
	else:
		# Stock Godot supports ordinary mipmaps, not the extended coverage API.
		# Keep the imported texture if even ordinary mip generation fails.
		optimized = pixels if pixels.generate_mipmaps() == OK else null
	var result: Texture2D = ImageTexture.create_from_image(optimized) if optimized != null else source
	_coverage_texture_cache[key] = result
	return result


static func _update_alpha_mip_surface(material: ShaderMaterial) -> void:
	if not material.has_meta("aa_cutout_original_texture"):
		return
	var original: Texture2D = material.get_meta("aa_cutout_original_texture") as Texture2D
	var cutoff: float = float(material.get_meta("aa_cutout_threshold", 0.5))
	var desired: Texture2D = _coverage_texture(original, cutoff)
	if material.get_shader_parameter("albedo_tex") != desired:
		material.set_shader_parameter("albedo_tex", desired)


## Quality changes only update cached materials, never mesh geometries.
static func configure_alpha_mipmaps(quality: int, method: String) -> void:
	var desired: bool = alpha_mipmaps_enabled(quality, method)
	if _alpha_mips_enabled == desired:
		return
	_alpha_mips_enabled = desired
	for mesh in _cache.values():
		if not mesh is ArrayMesh:
			continue
		var geometry := mesh as ArrayMesh
		for surface in geometry.get_surface_count():
			var material := geometry.surface_get_material(surface) as ShaderMaterial
			if material != null:
				_update_alpha_mip_surface(material)


## StandardMaterial3D can pack roughness and metallic in arbitrary channels.
static func _channel_mask(channel: int) -> Vector4:
	match channel:
		BaseMaterial3D.TEXTURE_CHANNEL_GREEN:
			return Vector4(0.0, 1.0, 0.0, 0.0)
		BaseMaterial3D.TEXTURE_CHANNEL_BLUE:
			return Vector4(0.0, 0.0, 1.0, 0.0)
		BaseMaterial3D.TEXTURE_CHANNEL_ALPHA:
			return Vector4(0.0, 0.0, 0.0, 1.0)
		BaseMaterial3D.TEXTURE_CHANNEL_GRAYSCALE:
			return Vector4(1.0 / 3.0, 1.0 / 3.0, 1.0 / 3.0, 0.0)
		_:
			return Vector4(1.0, 0.0, 0.0, 0.0)


## The exact scene-category fade ranges are shared through global uniforms.
## Never apply the tree/bush range to monuments or decor with authored ranges.
static func fade_role_for(key: String) -> int:
	if key.begins_with("tree:") or key.begins_with("painted:") or key.begins_with("kenney_expanded_tree:"):
		return 1
	if key == "bush" or key == "berry":
		return 2
	return 0


## A swaying copy of `source` (cached by key). `sway` is the tip displacement in meters. `tinted`: multiply by the
## MultiMesh instance colour.
static func swayed(source: Mesh, key: String, sway: float, tinted: bool = false) -> Mesh:
	if source == null:
		return null
	if _cache.has(key):
		return _cache[key]
	var copy: ArrayMesh = ArrayMesh.new()
	var height := maxf(source.get_aabb().size.y, 0.1)
	var min_height: float = source.get_aabb().position.y
	for surface in source.get_surface_count():
		var arrays := source.surface_get_arrays(surface)
		copy.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], MeshLOD.copy_lods(source, surface))
		var base := source.surface_get_material(surface)
		if base is BaseMaterial3D:
			var standard := base as BaseMaterial3D
			var cut: bool = standard.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED
			var material := ShaderMaterial.new()
			var tangent_data = arrays[Mesh.ARRAY_TANGENT]
			var normal_data = arrays[Mesh.ARRAY_NORMAL]
			var normal_map: Texture2D = standard.normal_texture
			var normal_mapped: bool = standard.normal_enabled and normal_map != null and \
				tangent_data is PackedFloat32Array and normal_data is PackedVector3Array and \
				normal_data.size() > 0 and tangent_data.size() == normal_data.size() * 4
			# Select the shader before setting imported PBR parameters. Only a real
			# tangent frame may use the normal-mapped variant.
			material.shader = _shader_for_surface(cut, normal_mapped)
			material.set_meta("aa_foliage_normal_mapped", normal_mapped)
			material.set_shader_parameter("sway", sway)
			material.set_shader_parameter("instance_tinted", tinted)
			material.set_shader_parameter("height_ref", height)
			material.set_shader_parameter("height_min", min_height)
			material.set_shader_parameter("fade_role", fade_role_for(key))
			material.set_shader_parameter("albedo_color", standard.albedo_color)
			material.set_shader_parameter("use_vertex_colors", standard.vertex_color_use_as_albedo)
			material.set_shader_parameter("material_roughness", standard.roughness)
			material.set_shader_parameter("material_metallic", standard.metallic)
			material.set_shader_parameter("material_specular", standard.metallic_specular)
			var orm: Texture2D = standard.orm_texture
			if orm != null:
				material.set_shader_parameter("use_orm_map", true)
				material.set_shader_parameter("orm_tex", orm)
			else:
				var roughness_map: Texture2D = standard.roughness_texture
				if roughness_map != null:
					material.set_shader_parameter("use_roughness_map", true)
					material.set_shader_parameter("roughness_tex", roughness_map)
					material.set_shader_parameter("roughness_mask", _channel_mask(standard.roughness_texture_channel))
				var metallic_map: Texture2D = standard.metallic_texture
				if metallic_map != null and standard.metallic > 0.0:
					material.set_shader_parameter("use_metallic_map", true)
					material.set_shader_parameter("metallic_tex", metallic_map)
					material.set_shader_parameter("metallic_mask", _channel_mask(standard.metallic_texture_channel))
			# Shader compilation must also avoid reading NORMAL_MAP on tangentless
			# surfaces; the uniform alone is not enough.
			if normal_mapped:
				material.set_shader_parameter("use_normal_map", true)
				material.set_shader_parameter("normal_tex", normal_map)
				material.set_shader_parameter("normal_strength", standard.normal_scale)
			var texture: Texture2D = standard.albedo_texture
			# The kit's twisted-tree leaves (also on Bush_Common) are autumn red; this world is green, so the shader turns
			# them green (red and green swapped keeps the shape and shading of the leaves).
			material.set_shader_parameter("red_to_green", texture != null and texture.resource_path.ends_with("Leaves_TwistedTree_C.png"))
			var threshold: float = standard.alpha_scissor_threshold if \
				standard.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR else 0.5
			if texture != null:
				if cut:
					# Keep source texture for exact restoration on Balanced.
					material.set_meta("aa_cutout_original_texture", texture)
					material.set_meta("aa_cutout_threshold", threshold)
					material.set_shader_parameter("albedo_tex", _coverage_texture(texture, threshold))
				else:
					material.set_shader_parameter("albedo_tex", texture)
			material.set_shader_parameter("cut_out", cut)
			material.set_shader_parameter("scissor", threshold)
			copy.surface_set_material(surface, material)
		elif base != null:
			copy.surface_set_material(surface, base)
	_cache[key] = copy
	return copy
