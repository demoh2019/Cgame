shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
global uniform float aa_weather_wetness;
global uniform float aa_weather_rain;
global uniform float aa_snow_cover; // Winter Data Layer, 0..1 (data_layers.gd).
global uniform float aa_ground_contact_strength;
// Precomputed coarser-height target in UV2; interpolated on GPU per engine chunk.
instance uniform float aa_lod_morph = 0.0;
// High/Ultra only: subtle self-occlusion from normal-map microrelief,
// fused into existing PBR AO without any extra texture or screen pass.
global uniform float aa_terrain_micro_occlusion;
// Normal-map alpha stores prefiltered Toksvig coherence. Premium tiers
// resolve missed microfacet variance without additional GPU texture taps.
global uniform float aa_terrain_normal_variance_strength;
// Optional High/Ultra PBR second reflection lobe. The compile-time variant
// omits its GPU work entirely on Performance/Balanced and GL-safe presets.
#ifdef AA_TERRAIN_WET_CLEARCOAT
global uniform float aa_terrain_wet_clearcoat;
#endif
// World-height curvature stored in native vertex colors, not a texture.
global uniform float aa_terrain_curvature_strength;
global uniform float aa_terrain_horizon_ao_strength; // Native baked skylight in COLOR.b
global uniform float aa_puddle_ripple_strength;
// Radius of full two-scale albedo and normal mapping; shared by all streamed chunks.
global uniform float aa_terrain_detail_radius;
// Maximum number of PBR layers sampled per pixel (Ultra = all layers).
global uniform int aa_terrain_layer_budget;
// Low-cost world-space domain warping breaks terrain tiling at High and Ultra.
// The inexpensive tiers use the exact previous mapping and shader reads.
global uniform float aa_terrain_warp_strength;
global uniform float aa_cliff_normal_quality; // 0 on low-end, 0.7 High, 1 Ultra
#include "res://assets/shaders/cloud_shadow.gdshaderinc"
#include "res://assets/shaders/specular_aa.gdshaderinc"
#include "res://assets/shaders/terrain_height_blend.gdshaderinc"
#include "res://assets/shaders/puddle_ripples.gdshaderinc"
#include "res://assets/shaders/water_caustics.gdshaderinc"

// Textured ground. Thirteen CC0 materials (Poly Haven) in two texture arrays:
//   0 lush grass, 1 dry grass, 2 forest floor, 3 swamp mud, 4 road dirt, 5 cliff rock, 6 mountain rock, 7 sand, 8 snow,
//   9 cracked asphalt (ruined cities), 10 broken concrete (bunkers and depots), 11 weathered brick (cities), 12 old planks (docks).
// Which material lies where comes from the chunk's biome map (forest, swamp, plains: baked on the CPU from the same noise
// the server uses), from height (shore, mountains, snow), from slope (cliffs) and from the road mask. Each material is read
// at two scales and the two are blended by noise, so the tiling never shows as a grid; cliffs use a triplanar projection.

uniform sampler2DArray albedo_layers : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2DArray normal_layers : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D biome_map : hint_default_black, filter_linear, repeat_disable; // r forest, g swamp, b plains
uniform sampler2D road_mask : hint_default_black, filter_linear, repeat_disable;
uniform sampler2D contact_map : hint_default_white, filter_linear, repeat_disable;
uniform vec2 chunk_origin = vec2(0.0);
uniform float chunk_size = 64.0;
uniform float biome_texels = 17.0;
uniform float tile_meters = 4.5;
uniform float albedo_texels = 1024.0; // Per-layer texture width, for the magnification test.
uniform float normal_texels = 1024.0;
// Poly Haven displacement per layer (0.5 = flat for layers without one), for close-range parallax.
uniform sampler2DArray height_layers : filter_linear_mipmap, repeat_enable;
uniform float normal_strength = 1.7;
// Per-layer multiplier that moves the photo's average colour to the game's palette (computed on load).
uniform vec3 layer_tint[13];
// Average color of each material: cheap residual retains all biome transitions when texture taps are limited.
uniform vec3 layer_average[13];
// Paved ground of the sites near this chunk: x, z, radius, layer (radius 0: unused). Weeds take back the cracks.
uniform vec4 site_patches[4];

varying vec3 world_position;
varying vec3 world_normal;
// Slowly changing fields are interpolated over terrain triangles instead of
// evaluating multi-octave noise and cloud-map lookups for every screen pixel.
varying float aa_macro_broad;
varying float aa_vertex_mid;
varying float aa_vertex_cloud_shadow;

// Cgame runtime virtual texture (terrain_rvt.gd). Pages of the finished terrain material, baked from
// above by orthographic cameras rendering this same shader, replace the per-pixel layer blending past
// the live radius. Page table: 64x32 RGBA8, left half level 0 (8 m pages), right half level 1 (16 m);
// a texel is (layer + 1 low, high, page x & 255, page z & 255) of the page at its toroidal slot.
global uniform sampler2DArray aa_rvt_albedo : filter_linear_mipmap, repeat_disable;
global uniform sampler2DArray aa_rvt_data : filter_linear_mipmap, repeat_disable;
global uniform sampler2DArray aa_rvt_wet : filter_linear, repeat_disable;
global uniform sampler2D aa_rvt_table : filter_nearest, repeat_disable;
global uniform vec4 aa_rvt_params; // x on, y live radius, z level 0 radius, w level 1 radius
const uint AA_RVT_BAKE_WET = 65536u;
const uint AA_RVT_BAKE_DATA = 131072u;
const uint AA_RVT_BAKE_ALBEDO = 262144u;
const uint AA_RVT_ORDINARY_LAYERS = 32767u;
const float AA_RVT_TEXELS = 256.0;

vec3 aa_srgb_to_linear(vec3 c) {
	return mix(pow((c + 0.055) / 1.055, vec3(2.4)), c / 12.92, lessThan(c, vec3(0.04045)));
}

// One level's page for a world point: returns false when it is not resident.
bool aa_rvt_page(vec2 p, int level, float page_size, out vec3 uvw) {
	vec2 page_f = floor(p / page_size);
	ivec2 page = ivec2(page_f);
	vec4 t = texelFetch(aa_rvt_table, ivec2((page.x & 31) + level * 32, page.y & 31), 0);
	ivec4 b = ivec4(round(t * 255.0));
	int layer = b.r + b.g * 256 - 1;
	uvw = vec3(0.0);
	if (layer < 0 || b.b != (page.x & 255) || b.a != (page.y & 255)) {
		return false;
	}
	// The bake covers one border texel around the page so bilinear taps never leave it.
	vec2 f = p / page_size - page_f;
	uvw = vec3((f * (AA_RVT_TEXELS - 2.0) + 1.0) / AA_RVT_TEXELS, float(layer));
	return true;
}

// Baked material for a point, and how much of it to use (0 = shade live).
// `view_dist` is the 3D distance to the eye (pixel footprint decides live vs cached); `dist` is horizontal,
// matching how terrain_rvt.gd picks pages around the camera.
// `p_dx`/`p_dy` are screen derivatives of the world position, taken before any divergent branch, so the
// mipmapped BC pages filter correctly.
float aa_rvt_fetch(vec2 p, vec2 p_dx, vec2 p_dy, float dist, float view_dist, out vec3 albedo, out vec3 normal, out float roughness, out vec3 wet) {
	albedo = vec3(0.0);
	normal = vec3(0.0, 1.0, 0.0);
	roughness = 0.9;
	wet = vec3(0.0);
	float weight = smoothstep(aa_rvt_params.y, aa_rvt_params.y + 4.0, view_dist)
		* (1.0 - smoothstep(aa_rvt_params.w - 6.0, aa_rvt_params.w, dist));
	if (weight <= 0.0) {
		return 0.0;
	}
	vec3 uvw;
	bool found = dist < aa_rvt_params.z && aa_rvt_page(p, 0, 8.0, uvw);
	bool coarse = false;
	if (!found) {
		found = aa_rvt_page(p, 1, 16.0, uvw);
		coarse = found;
	}
	float to_uv = (AA_RVT_TEXELS - 2.0) / (AA_RVT_TEXELS * (coarse ? 16.0 : 8.0));
	vec2 uv_dx = p_dx * to_uv;
	vec2 uv_dy = p_dy * to_uv;
	if (!found) {
		return 0.0;
	}
	// BC3: sRGB albedo + roughness in alpha. BC5: normal x, z.
	vec4 albedo_roughness = textureGrad(aa_rvt_albedo, uvw, uv_dx, uv_dy);
	albedo = aa_srgb_to_linear(albedo_roughness.rgb);
	if (aa_rvt_params.x > 1.5) {
		albedo = mix(albedo, coarse ? vec3(0.1, 0.2, 1.0) : vec3(1.0, 0.1, 0.1), 0.35); // CGAME_RVT_DEBUG
	}
	vec2 nxz = textureGrad(aa_rvt_data, uvw, uv_dx, uv_dy).rg * 2.0 - 1.0;
	normal = normalize(vec3(nxz.x, sqrt(max(1.0 - dot(nxz, nxz), 0.0)), nxz.y));
	roughness = albedo_roughness.a;
	wet = textureLod(aa_rvt_wet, uvw, 0.0).rgb;
	return weight;
}

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(i), hash21(i + vec2(1.0, 0.0)), f.x), mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), f.x), f.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 3; i++) {
		v += a * value_noise(p);
		p = p * 2.03 + 17.0;
		a *= 0.5;
	}
	return v;
}

void vertex() {
	float morph = clamp(aa_lod_morph * UV2.y, 0.0, 1.0);
	VERTEX.y = mix(VERTEX.y, UV2.x, morph);
	if (morph > 0.001) {
		// Custom0 contains the next LOD's *coarse vertex normals*. Light
		// shading now follows the same triangle transition as vertex height.
		// Performance/Balanced omit this stream; their morph is always zero.
		NORMAL = normalize(mix(NORMAL, CUSTOM0.xyz, morph));
	}
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	// The broad biome color field has a ~83 m cell size. Sampling once per
	// terrain vertex preserves stable world alignment while avoiding 3 fBM
	// octaves per fragment on large stretches of visible terrain.
	aa_macro_broad = fbm(world_position.xz * 0.012);
	// Distant dirt/forest/ruin noise is too small for per-pixel evaluation.
	// The near-field keeps its original fragment FBM exactly; far terrain
	// interpolates the same noise from existing terrain vertices.
	aa_vertex_mid = fbm(world_position.xz * 0.07 + 3.0);
	// Cloud-shadow LUT is 128 texels across 1024 m (~8 m/texel). Terrain
	// vertices have ample resolution to interpolate these soft shadows.
	// This shares the exact LUT/phase/strength with grass and tree leaves.
	aa_vertex_cloud_shadow = cloud_shadow(world_position.xz, TIME);
}

// Distant terrain keeps the existing broad-scale tiling, but skips nearby microdetail samples.
// The blending weight tends smoothly to zero, avoiding hard texture LOD boundaries.
// Close to the camera a 1k texture over a 6 m tile is magnified several times and looks smeared.
// Wherever the near tile is magnified (under ~1 texel per pixel) the same layer is also sampled at a
// 4.5x finer, rotated scale and applied as luminance detail: crisp grit underfoot, no extra textures.
const float AA_MICRO_SCALE = 0.22;
const float AA_PARALLAX_DEPTH = 0.14; // Metres of apparent relief at full displacement contrast.
const float AA_CAVITY_STRENGTH = 0.5; // How dark the deepest cracks and gaps between stones get.

// Parallax occlusion mapping: march the view ray through the layer's height field (4-14 steps,
// fewer when the view is steep or far) so raised stones occlude what lies behind them.
// Returns the corrected terrain position in metres and the height found there (in .z).
vec3 aa_parallax(float layer, vec2 p, vec3 view_world, vec2 lod_dx, vec2 lod_dy, float fade) {
	float grazing = 1.0 - clamp(view_world.y, 0.0, 1.0);
	int steps = int(mix(4.0, 14.0, fade * grazing));
	vec2 shift = -view_world.xz / max(view_world.y, 0.25) * AA_PARALLAX_DEPTH * fade;
	float step_depth = 1.0 / float(steps);
	float ray_depth = 0.0;
	vec2 offset = vec2(0.0);
	vec2 delta = shift * step_depth;
	float surface = 1.0 - textureGrad(height_layers, vec3(p / tile_meters, layer), lod_dx, lod_dy).r;
	float previous_surface = surface;
	for (int i = 0; i < 14; i++) {
		if (i >= steps || ray_depth >= surface) {
			break;
		}
		previous_surface = surface;
		offset += delta;
		ray_depth += step_depth;
		surface = 1.0 - textureGrad(height_layers, vec3((p + offset) / tile_meters, layer), lod_dx, lod_dy).r;
	}
	// Refine between the last two steps.
	float after = surface - ray_depth;
	float before = previous_surface - (ray_depth - step_depth);
	float t = clamp(after / min(after - before, -0.0001), 0.0, 1.0);
	vec2 final_offset = offset - delta * t;
	float height = 1.0 - mix(surface, previous_surface, t);
	return vec3(p + final_offset, height);
}
const mat2 AA_MICRO_ROT = mat2(vec2(0.8776, 0.4794), vec2(-0.4794, 0.8776));

float aa_micro_weight(vec2 lod_dx, vec2 lod_dy) {
	float texels_per_pixel = max(length(lod_dx), length(lod_dy)) * albedo_texels;
	return 1.0 - smoothstep(0.35, 1.3, texels_per_pixel);
}

vec3 top_albedo(float layer, vec2 p, float mixer, float detail_fade, vec2 lod_dx, vec2 lod_dy) {
	float far_scale = max(3.3, 20.0 / tile_meters);
	vec3 far_tile = textureGrad(albedo_layers, vec3(p / (tile_meters * far_scale) + 0.37, layer), lod_dx / far_scale, lod_dy / far_scale).rgb;
	// Near the camera the sharp near tile dominates; the noise mixer only breaks tiling further away.
	float near_weight = detail_fade * (1.0 - mixer * mix(0.35, 1.0, 1.0 - detail_fade));
	if (near_weight > 0.001) {
		vec3 near_tile = textureGrad(albedo_layers, vec3(p / tile_meters, layer), lod_dx, lod_dy).rgb;
		far_tile = mix(far_tile, near_tile, near_weight);
		float micro_w = aa_micro_weight(lod_dx, lod_dy) * detail_fade;
		if (micro_w > 0.01) {
			vec2 mp = AA_MICRO_ROT * (p / (tile_meters * AA_MICRO_SCALE)) + 0.21;
			vec3 micro = textureGrad(albedo_layers, vec3(mp, layer), AA_MICRO_ROT * lod_dx / AA_MICRO_SCALE,
				AA_MICRO_ROT * lod_dy / AA_MICRO_SCALE).rgb;
			float base_l = max(dot(near_tile, vec3(0.299, 0.587, 0.114)), 0.04);
			float micro_l = dot(micro, vec3(0.299, 0.587, 0.114));
			far_tile *= mix(1.0, clamp(micro_l / base_l, 0.55, 1.6), micro_w * 0.65);
		}
	}
	return far_tile * layer_tint[int(layer)];
}

vec4 top_normal(float layer, vec2 p, float detail_fade, vec2 lod_dx, vec2 lod_dy) {
	// One existing texture read supplies both unit normal and averaged
	// normal coherence in alpha. Far terrain skips the texture entirely.
	vec4 normal = vec4(0.0, 0.0, 1.0, 1.0);
	if (detail_fade > 0.001) {
		vec4 mapped = textureGrad(normal_layers, vec3(p / tile_meters, layer), lod_dx, lod_dy);
		normal = mix(normal, vec4(mapped.rgb * 2.0 - 1.0, mapped.a), detail_fade);
		// Matching fine-scale bumps where the near normal map is magnified (normals are 512 px).
		float micro_w = (1.0 - smoothstep(0.2, 0.7, max(length(lod_dx), length(lod_dy)) * normal_texels)) * detail_fade;
		if (micro_w > 0.01) {
			vec2 mp = AA_MICRO_ROT * (p / (tile_meters * AA_MICRO_SCALE)) + 0.21;
			vec3 micro = textureGrad(normal_layers, vec3(mp, layer), AA_MICRO_ROT * lod_dx / AA_MICRO_SCALE,
				AA_MICRO_ROT * lod_dy / AA_MICRO_SCALE).rgb * 2.0 - 1.0;
			normal.xy += micro.xy * micro_w * 0.6;
			normal.xyz = normalize(normal.xyz);
		}
	}
	return normal;
}

void fragment() {
	vec2 p = world_position.xz;
	vec2 aa_p_dx = dFdx(p); // Before any divergent branch (cached-page mip selection).
	vec2 aa_p_dy = dFdy(p);
	float h = world_position.y;
	vec3 n = normalize(world_normal);
	float slope = 1.0 - clamp(n.y, 0.0, 1.0);
	float broad = aa_macro_broad;
	// Explicit texture gradients must be evaluated before any dynamic
	// noise or texture selection branch to keep cliff mipmapping stable.
	vec2 lod_dx = dFdx(p / tile_meters);
	vec2 lod_dy = dFdy(p / tile_meters);
	// Domain warp and the PBR blend must share the same near/far mid-frequency
	// soil field. Declare it before use: shader processors reject forward local
	// references (and the prior layout could fail to compile on Metal).
	// Bake cameras see only the terrain plus one marker layer (and none of the ordinary layers).
	uint aa_layers = CAMERA_VISIBLE_LAYERS;
	bool bake_any = (aa_layers & AA_RVT_ORDINARY_LAYERS) == 0u;
	bool bake_albedo = bake_any && (aa_layers & AA_RVT_BAKE_ALBEDO) != 0u;
	bool bake_data = bake_any && (aa_layers & AA_RVT_BAKE_DATA) != 0u;
	bool bake_wet = bake_any && (aa_layers & AA_RVT_BAKE_WET) != 0u;
	bool baking = bake_albedo || bake_data || bake_wet;
	// Pages are baked at full detail; the view distance only decides where they are used.
	float camera_distance = baking ? 0.0 : distance(p, CAMERA_POSITION_WORLD.xz);
	vec3 rvt_albedo;
	vec3 rvt_normal;
	float rvt_roughness;
	vec3 rvt_wet;
	float rvt_weight = 0.0;
	if (!baking && aa_rvt_params.x > 0.5) {
		rvt_weight = aa_rvt_fetch(p, aa_p_dx, aa_p_dy, camera_distance, distance(world_position, CAMERA_POSITION_WORLD), rvt_albedo, rvt_normal, rvt_roughness, rvt_wet);
	}
	bool need_live = rvt_weight < 0.999;
	float detail_fade = 1.0 - smoothstep(aa_terrain_detail_radius,
		aa_terrain_detail_radius + 24.0, camera_distance);
	// Quality-dependent material complexity, like distance-faded detail
	// in high-end engines: far pixels reuse one interpolated vertex field.
	// Within the full-detail radius, the old pixel noise is preserved exactly.
	float mid = aa_vertex_mid;
	float mixer = 0.5;
	if (detail_fade > 0.001 && need_live) {
		mid = mix(aa_vertex_mid, fbm(p * 0.07 + 3.0), detail_fade);
		// At far LOD the per-pixel mixer had no contribution to albedo:
		// near_weight is already multiplied by detail_fade.
		mixer = smoothstep(0.3, 0.7, value_noise(p * 0.05 + 11.0));
	}
	// Texture-coordinate domain warp inspired by terrain anti-tiling materials.
	// Reuse the two already computed spatially continuous noise fields:
	// no new texture fetches, fbm loops, GPU passes or geometry changes.
	// Keep road, biome, site and physics coordinates in unwarped world space.
	vec2 material_p = p;
	if (aa_terrain_warp_strength > 0.001) {
		vec2 warp = vec2(mid - 0.44,
			broad - 0.44 + (mid - 0.44) * 0.27);
		warp *= tile_meters * clamp(aa_terrain_warp_strength, 0.0, 0.55);
		material_p += warp;
		// Preserve anisotropic mip filtering under continuous non-linear UV
		// deformation. This global-uniform branch is uniform over the draw.
		lod_dx += dFdx(warp / tile_meters);
		lod_dy += dFdy(warp / tile_meters);
	}
	// Direction from the surface toward the camera, in world space, for parallax.
	vec3 view_world = normalize(CAMERA_POSITION_WORLD - world_position);
	float parallax_fade = baking ? 0.0 : 1.0 - smoothstep(8.0, 18.0, camera_distance);
	vec2 cliff_dx_zy = dFdx(world_position.zy / tile_meters);
	vec2 cliff_dy_zy = dFdy(world_position.zy / tile_meters);
	vec2 cliff_dx_xy = dFdx(world_position.xy / tile_meters);
	vec2 cliff_dy_xy = dFdy(world_position.xy / tile_meters);

	// The material record both paths fill: live layer blending near the camera, baked pages further out.
	vec3 color = vec3(0.5);
	vec3 bent = n;
	float r_dry_roughness = 0.9;
	float r_wet_factor = 0.22;
	float r_puddle_shape = 0.0;
	float r_hard_surface = 0.0;
	float r_coherence = 1.0;
	vec2 local = (p - chunk_origin) / chunk_size;
	float r_micro_cavity = 0.0;
	if (need_live) {
	// Biome weights from the chunk map, sampled between texel centres so neighbouring chunks meet exactly.
	vec2 biome_uv = local * ((biome_texels - 1.0) / biome_texels) + 0.5 / biome_texels;
	vec3 biome = textureLod(biome_map, biome_uv, 0.0).rgb;

	float w[13];
	for (int i = 0; i < 13; i++) {
		w[i] = 0.0;
	}
	// Grassland: lush and dry patches; plains lean dry.
	float dryness = clamp(smoothstep(0.42, 0.72, broad) + biome.b * 0.25, 0.0, 1.0);
	float open_land = clamp(1.0 - biome.r - biome.g, 0.0, 1.0);
	w[0] = open_land * (1.0 - dryness);
	w[1] = open_land * dryness;
	// Forest floor, broken by grassy clearings.
	w[2] = biome.r * (0.55 + 0.45 * smoothstep(0.35, 0.6, mid));
	w[0] += biome.r - w[2];
	w[3] = biome.g;
	// Bare earth on rough patches and moderate slopes.
	// A thousand years without people: bare earth only in small patches and on the steeper slopes.
	float bare = smoothstep(0.74, 0.9, mid + slope * 0.8) * 0.45;
	for (int i = 0; i < 4; i++) {
		w[i] *= 1.0 - bare;
	}
	w[4] = bare;
	// Shore sand.
	float shore = 1.0 - smoothstep(0.5, 2.6, h + (broad - 0.5) * 1.4);
	for (int i = 0; i < 5; i++) {
		w[i] *= 1.0 - shore;
	}
	w[7] = shore;
	// Rocky high ground, cliffs on steep slopes, snow on the peaks.
	float high = smoothstep(40.0, 58.0, h + (broad - 0.5) * 8.0);
	for (int i = 0; i < 8; i++) {
		w[i] *= 1.0 - high;
	}
	w[6] += high;
	float cliff = smoothstep(0.22, 0.42, slope + (mid - 0.5) * 0.1);
	for (int i = 0; i < 9; i++) {
		w[i] *= 1.0 - cliff;
	}
	w[5] = cliff;
	float snow = smoothstep(88.0, 108.0, h + (broad - 0.5) * 14.0) * (1.0 - smoothstep(0.32, 0.55, slope));
	// Winter Data Layer: snow settles everywhere above the shoreline, thinner on slopes and in patches.
	float winter = aa_snow_cover * smoothstep(1.2, 3.0, h) * (1.0 - smoothstep(0.28, 0.5, slope))
		* smoothstep(0.25, 0.6, broad + 0.35);
	snow = max(snow, winter);
	for (int i = 0; i < 8; i++) {
		w[i] *= 1.0 - snow;
	}
	w[8] = snow;
	// Paved sites keep their original mossy borders, but the expensive
	// three-octave reclaiming-noise field is needed only inside those borders.
	// Several overlapping sites share exactly the same noise sample per pixel.
	float reclaiming_moss = -1.0;
	for (int k = 0; k < 4; k++) {
		vec4 patch = site_patches[k];
		if (patch.z <= 0.0 || cliff >= 1.0) {
			continue;
		}
		vec2 offset = p - patch.xy;
		// mid is a sum of three value-noise octaves (range [0, 0.875]).
		// Its greatest inward boundary offset is -0.175. Therefore paved
		// equals zero beyond 1.175 * radius, even with edge distortion.
		// Squared distance avoids a square root for most terrain pixels.
		float outer_radius = patch.z * 1.175;
		if (dot(offset, offset) >= outer_radius * outer_radius) {
			continue;
		}
		float d = length(offset) / patch.z;
		float paved = 1.0 - smoothstep(0.7, 1.0, d + (mid - 0.5) * 0.35);
		if (paved <= 0.0) {
			continue;
		}
		if (reclaiming_moss < 0.0) {
			reclaiming_moss = smoothstep(0.42, 0.68, fbm(p * 0.11 + 5.0));
		}
		paved *= 1.0 - 0.9 * reclaiming_moss * (1.0 - cliff);
		paved *= 0.85;
		paved *= 1.0 - cliff;
		for (int i = 0; i < 13; i++) {
			w[i] *= 1.0 - paved;
		}
		w[int(patch.w)] += paved;
	}
	// Roads.
	float road = smoothstep(0.08, 0.55, textureLod(road_mask, local, 0.0).r);
	for (int i = 0; i < 13; i++) {
		w[i] *= 1.0 - road;
	}
	w[4] += road;

	// Optional height-aware terrain layering: where two natural materials meet,
	// raised stone/snow protrudes over softer mud, forest soil and sand.
	// Reuses the ALREADY computed mid/broad fields, with no new texture taps.
	// Roads and authored ruined-site masks retain their exact original weight.
	if (aa_terrain_height_blend > 0.001 && detail_fade > 0.001
			&& road < 0.85 && (w[9] + w[10] + w[11] + w[12]) < 0.40) {
		float natural_sum = 0.0;
		float sculpted_sum = 0.0;
		for (int i = 0; i < 9; i++) {
			if (i == 4) {
				continue; // Preserve the dirt road layer, even on steep terrain.
			}
			float original = w[i];
			natural_sum += original;
			if (original > 0.001) {
				w[i] = original * aa_terrain_relief_gain(
					i, original, mid, broad, aa_terrain_height_blend * detail_fade);
			}
			sculpted_sum += w[i];
		}
		// Conserve the total natural contribution: existing biome, road,
		// shoreline and site masks still sum to exactly the former coverage.
		if (sculpted_sum > 0.00001) {
			float conserve = natural_sum / sculpted_sum;
			for (int i = 0; i < 9; i++) {
				if (i != 4) {
					w[i] *= conserve;
				}
			}
		}
	}

	// Four ranked slots are enough for Performance/Balanced/High. Ultra bypasses ranking
	// and keeps all 13 materials, including tiny biome transitions.
	int layer_budget = aa_terrain_layer_budget >= 13 ? 13 : clamp(aa_terrain_layer_budget, 1, 4);
	int selected_ids[4] = {-1, -1, -1, -1};
	float selected_weights[4] = {0.0, 0.0, 0.0, 0.0};
	vec3 macro_color = vec3(0.0);
	float all_weight = 0.0;
	for (int i = 0; i < 13; i++) {
		float weight = w[i];
		if (weight < 0.02) {
			continue;
		}
		// Unlike truncating to N layers and re-normalizing, this fallback preserves
		// a smooth approximation to small grass, dirt and shoreline contributions.
		macro_color += layer_average[i] * weight;
		all_weight += weight;
		if (layer_budget >= 13) {
			continue;
		}
		// The branch is uniform across a draw: no random texture-fetch count per pixel.
		for (int slot = 0; slot < 4; slot++) {
			if (weight > selected_weights[slot]) {
				for (int shift = 3; shift > slot; shift--) {
					selected_weights[shift] = selected_weights[shift - 1];
					selected_ids[shift] = selected_ids[shift - 1];
				}
				selected_weights[slot] = weight;
				selected_ids[slot] = i;
				break;
			}
		}
	}
	color = macro_color;
	vec3 bump = vec3(0.0);
	float coherence_sum = 0.0;
	vec3 cliff_world_normal = n;
	float sampled_weight = 0.0;
	for (int slot = 0; slot < 13; slot++) {
		if (slot >= layer_budget) {
			break;
		}
		int i = slot;
		if (layer_budget < 13) {
			i = selected_ids[slot];
		}
		if (i < 0 || w[i] < 0.02) {
			continue;
		}
		float layer = float(i);
		vec3 c;
		vec4 normal_sample;
		float cliff_coherence = 1.0;
		if (i == 5) {
			// An distant cliff contributes its existing palette average instead
			// of paying for three tiny, subpixel albedo projections per pixel.
			// The exact high-detail triplanar appearance is preserved nearby;
			// the same smooth camera-distance fade avoids LOD popping.
			c = layer_average[5];
			if (detail_fade > 0.001) {
				// Explicit gradients were computed before any divergent branch,
				// keeping all imported rock mip levels stable on all renderers.
				vec3 blend = pow(abs(n), vec3(4.0));
				blend /= max(blend.x + blend.y + blend.z, 0.0001);
				vec3 cliff_detail = textureGrad(albedo_layers, vec3(world_position.zy / tile_meters, layer), cliff_dx_zy, cliff_dy_zy).rgb * blend.x
					+ textureGrad(albedo_layers, vec3(p / tile_meters, layer), lod_dx, lod_dy).rgb * blend.y
					+ textureGrad(albedo_layers, vec3(world_position.xy / tile_meters, layer), cliff_dx_xy, cliff_dy_xy).rgb * blend.z;
				c = mix(c, cliff_detail * layer_tint[5], detail_fade);
				// High/Ultra keep the exact existing cliff normal mapping nearby.
				// Far fragments already skip both normal and albedo fetches.
				if (aa_cliff_normal_quality > 0.001) {
					vec4 nx_sample = textureGrad(normal_layers,
						vec3(world_position.zy / tile_meters, layer),
						cliff_dx_zy, cliff_dy_zy);
					vec4 ny_sample = textureGrad(normal_layers,
						vec3(p / tile_meters, layer),
						lod_dx, lod_dy);
					vec4 nz_sample = textureGrad(normal_layers,
						vec3(world_position.xy / tile_meters, layer),
						cliff_dx_xy, cliff_dy_xy);
					vec3 nx = nx_sample.rgb * 2.0 - 1.0;
					vec3 ny = ny_sample.rgb * 2.0 - 1.0;
					vec3 nz = nz_sample.rgb * 2.0 - 1.0;
					cliff_coherence = clamp(dot(
						vec3(nx_sample.a, ny_sample.a, nz_sample.a), blend), 0.0, 1.0);
					vec3 along_x = normalize(vec3(sign(n.x) * nx.z, nx.y, nx.x));
					vec3 along_y = normalize(vec3(ny.x, sign(n.y) * ny.z, ny.y));
					vec3 along_z = normalize(vec3(nz.x, nz.y, sign(n.z) * nz.z));
					cliff_world_normal = normalize(
						along_x * blend.x + along_y * blend.y + along_z * blend.z);
				}
			}
			normal_sample = vec4(0.0, 0.0, 1.0, cliff_coherence);
		} else {
			// Parallax offset: pebbles and clods appear raised at grazing angles near the camera.
			vec2 layer_p = material_p;
			float layer_height = 0.5;
			if (parallax_fade > 0.01) {
				vec3 marched = aa_parallax(layer, material_p, view_world, lod_dx, lod_dy, parallax_fade);
				layer_p = marched.xy;
				layer_height = marched.z;
			} else if (detail_fade > 0.01) {
				layer_height = textureGrad(height_layers, vec3(material_p / tile_meters, layer), lod_dx, lod_dy).r;
			}
			c = top_albedo(layer, layer_p, mixer, detail_fade, lod_dx, lod_dy);
			// Cavities: cracks, gaps between pebbles and hollows under leaves fall into shadow.
			c *= mix(1.0, mix(1.0 - AA_CAVITY_STRENGTH, 1.0, smoothstep(0.05, 0.65, layer_height)), detail_fade);
			normal_sample = top_normal(layer, layer_p, detail_fade, lod_dx, lod_dy);
		}
		// Replace the approximate layer color with the actual PBR texture; the
		// unselected layers still contribute their average palette color.
		color += (c - layer_average[i]) * w[i];
		bump += normal_sample.xyz * w[i];
		coherence_sum += normal_sample.a * w[i];
		sampled_weight += w[i];
	}
	color /= max(all_weight, 0.0001);
	if (sampled_weight > 0.001) {
		bump /= sampled_weight;
	} else {
		bump = vec3(0.0, 0.0, 1.0);
	}

	// Large-scale light and colour variation, a little darker where the shore is wet.
	color *= 0.86 + 0.28 * broad;
	color = mix(color, color * 0.6, 1.0 - smoothstep(-1.4, 0.8, h));
	// A touch more saturation to sit with the stylised models.
	float grey = dot(color, vec3(0.299, 0.587, 0.114));
	color = mix(vec3(grey), color, 1.15);

	// Subtle rain-aged moss on ruins, bunkers and abandoned timber.
	// Reuse the existing biome/site weights and mid-frequency noise:
	// there is no extra texture, fBM call or draw pass to shade this patina.
	// Its weight vanishes continuously at the original paving boundaries.
	float ruin_share = clamp((w[9] + w[10] + w[11] + w[12])
		/ max(all_weight, 0.0001), 0.0, 1.0);
	float ruin_moss = ruin_share * smoothstep(0.34, 0.72, mid)
		* (1.0 - cliff) * (1.0 - clamp(w[8], 0.0, 1.0)) * 0.5;
	color *= mix(vec3(1.0), vec3(0.75, 0.92, 0.73), ruin_moss);

	// Normal map in world space: the ground is mapped from above, so x and z are the tangent axes.
	vec3 tangent = normalize(vec3(1.0, 0.0, 0.0) - n * n.x);
	vec3 bitangent = normalize(cross(n, tangent));
	vec3 detail = normalize(vec3(bump.xy * normal_strength, max(bump.z, 0.2)));
	bent = normalize(tangent * detail.x + bitangent * detail.y + n * detail.z);
	// The cliff relief never bleeds into a grassy or paved transition.
	float cliff_mix = clamp(w[5] / max(all_weight, 0.0001), 0.0, 1.0)
		* clamp(aa_cliff_normal_quality, 0.0, 1.0) * detail_fade;
	bent = normalize(mix(bent, cliff_world_normal, cliff_mix));

	// Wet earth absorbs light; shallow mud and worn pavement collect small smooth puddles.
	// Reuse existing biome and noise weights instead of additional texture reads or noise octaves.
	float wettable = clamp(w[3] + w[4] + w[7] * 0.65 + w[9] + w[10] + w[2] * 0.25, 0.0, 1.0);
	r_wet_factor = (0.22 + 0.78 * wettable) * (1.0 - clamp(w[8], 0.0, 1.0));
	r_puddle_shape = clamp(w[3] + w[4] + w[9] + w[10], 0.0, 1.0)
		* smoothstep(0.52, 0.78, mid) * (1.0 - smoothstep(0.08, 0.25, slope));
	// A physically plausible microfacet roughness for each existing layer.
	// This reuses the 13 biome weights (no extra textures or VRAM).
	r_dry_roughness = (
		w[0] * 0.91 + w[1] * 0.94 + w[2] * 0.88 + w[3] * 0.86
		+ w[4] * 0.89 + w[5] * 0.73 + w[6] * 0.77 + w[7] * 0.93
		+ w[8] * 0.94 + w[9] * 0.72 + w[10] * 0.83
		+ w[11] * 0.78 + w[12] * 0.82) / max(all_weight, 0.0001);
	r_dry_roughness = clamp(r_dry_roughness + (mid - 0.5) * 0.055, 0.55, 0.98);
	// Moss is diffuse and rough; keep the smooth puddle override below intact.
	r_dry_roughness = mix(r_dry_roughness, 0.92, ruin_moss * 0.45);
	// Hard, film-holding surfaces for the optional wet clearcoat; moss stays porous, snow is dry.
	r_hard_surface = clamp(w[4] + w[5] * 0.35 + w[6] * 0.25
		+ w[9] + w[10] + w[11] + w[12] * 0.35, 0.0, 1.0)
		* (1.0 - clamp(w[8], 0.0, 1.0)) * (1.0 - ruin_moss * 0.45);
	r_coherence = sampled_weight > 0.001 ? clamp(coherence_sum / sampled_weight, 0.05, 1.0) : 1.0;
	r_micro_cavity = 1.0 - clamp(bump.z, 0.0, 1.0);
	}
	if (rvt_weight > 0.0) {
		color = mix(color, rvt_albedo, rvt_weight);
		bent = normalize(mix(bent, rvt_normal, rvt_weight));
		r_dry_roughness = mix(r_dry_roughness, rvt_roughness, rvt_weight);
		r_wet_factor = mix(r_wet_factor, rvt_wet.r, rvt_weight);
		r_puddle_shape = mix(r_puddle_shape, rvt_wet.g, rvt_weight);
		r_hard_surface = mix(r_hard_surface, rvt_wet.b, rvt_weight);
		r_coherence = mix(r_coherence, 1.0, rvt_weight);
		r_micro_cavity = mix(r_micro_cavity, 0.0, rvt_weight);
	}
	vec3 material_color = color; // What the albedo pages store (weather, clouds and AO stay live).

	float wetness = clamp(aa_weather_wetness, 0.0, 1.0) * r_wet_factor;
	float puddle = wetness * r_puddle_shape;
	bent = normalize(mix(bent, n, puddle * 0.75));
	// Near, wet, flat ground only: animated impact rings disturb existing
	// PBR puddle reflections without any extra texture samples or meshes.
	if (aa_puddle_ripple_strength > 0.001 && aa_weather_rain > 0.005 && puddle > 0.05
			&& camera_distance < aa_terrain_detail_radius) {
		float ripple_fade = 1.0 - smoothstep(
			aa_terrain_detail_radius * 0.58, aa_terrain_detail_radius,
			camera_distance);
		vec2 ripple_tilt = aa_puddle_ripple_tilt(p, TIME);
		bent = normalize(bent + vec3(ripple_tilt.x, 0.0, ripple_tilt.y)
			* (aa_weather_rain * aa_puddle_ripple_strength * sqrt(puddle) * ripple_fade));
	}
	NORMAL = normalize((VIEW_MATRIX * vec4(bent, 0.0)).xyz);

	color *= 1.0 - wetness * 0.18 - puddle * 0.12;
	// Same tint as apply_cloud_shadow(), now with one interpolated scalar per
	// vertex instead of an additional cloud-map lookup for every fragment.
	// Baked per-chunk ground contact AO, enabled only near the camera.
	// White L8 mask = no shadow. Performance skips the texture read.
	float ground_contact = 1.0;
	if (aa_ground_contact_strength > 0.001 && detail_fade > 0.001) {
		float contact_sample = texture(contact_map,
			clamp(local, vec2(0.0), vec2(1.0))).r;
		ground_contact = 1.0 - (1.0 - contact_sample)
			* aa_ground_contact_strength * detail_fade;
	}
	// HDRP-like micro-occlusion from already sampled tangent-space normals.
	// Flattened distant normals cost nothing; wet puddles visually fill cracks.
	// Keep the effect subtle because Forward+ also supplies screen-space AO.
	float micro_cavity = r_micro_cavity;
	float micro_shadow = 1.0 - min(0.18,
		micro_cavity * 0.32 * aa_terrain_micro_occlusion * detail_fade
		* (1.0 - puddle * 0.85));
	float cavity = clamp(COLOR.r, 0.0, 1.0)
		* aa_terrain_curvature_strength * detail_fade;
	float ridge = clamp(COLOR.g, 0.0, 1.0)
		* aa_terrain_curvature_strength * detail_fade;
	// Wet puddles fill micro-cavities. Restore their reflection visibility
	// gradually instead of feeding dry-stone occlusion into native GGX IBL.
	// The same AO channel drives diffuse and Lagarde specular occlusion;
	// contact shadows remain intact even on a smooth rain-wet surface.
	float cavity_visibility = 1.0 - cavity * 0.24 * (1.0 - puddle * 0.85);
	// Native eight-direction horizon visibility arrives via the existing
	// vertex COLOR.b channel. The high-tier branch uses no extra texture.
	float sky_visibility = 1.0;
	if (aa_terrain_horizon_ao_strength > 0.001) {
		sky_visibility = mix(1.0, clamp(COLOR.b, 0.0, 1.0),
			clamp(aa_terrain_horizon_ao_strength, 0.0, 1.0));
	}
	AO = clamp(ground_contact * micro_shadow * cavity_visibility * sky_visibility, 0.0, 1.0);
	ALBEDO = color * mix(1.0, sky_visibility, 0.10)
		* (1.0 - cavity * 0.095 + ridge * 0.035)
		* mix(1.0, ground_contact, 0.12)
		* mix(vec3(1.0), vec3(0.58, 0.63, 0.74), aa_vertex_cloud_shadow);
	// Sunlight focused by moving shallow waves only on submerged near-field
	// terrain. High/Ultra Forward+ only; keeps the existing PBR normal/ORM,
	// SSR, roughness and alpha-free opaque path. No screen or texture read.
	float caustics = aa_water_caustic_illumination(
		p, h, n.y, camera_distance, TIME);
	ALBEDO += vec3(0.10, 0.19, 0.18) * caustics
		* (1.0 - aa_vertex_cloud_shadow * 0.70);
	float dry_roughness = r_dry_roughness;
	// Wetness changes roughness, not the dielectric material's F0.
	// Existing shallow puddles still produce very tight highlights.
	float final_roughness = clamp(
		mix(mix(dry_roughness, 0.28, wetness * 0.55), 0.08, puddle * 0.9),
		0.045, 1.0);
	// Toksvig-like prefiltered normal variance reveals unresolved microrelief.
	// The native engine stores coherence in alpha of the *existing* normal tap.
	// Zero strength on low tiers skips this ALU, and water-filled puddles stay
	// optically smooth rather than turning matte due to the underlying mud.
	if (aa_terrain_normal_variance_strength > 0.001 && detail_fade > 0.001
			&& r_coherence < 0.999 && puddle < 0.85) {
		float coherence = r_coherence;
		float variance = min((1.0 - coherence) / coherence, 0.14);
		final_roughness = sqrt(min(1.0, final_roughness * final_roughness
			+ variance * aa_terrain_normal_variance_strength
			* detail_fade * (1.0 - puddle)));
	}
	// Existing screen-space normal derivatives handle additional subpixel
	// variation without losing the prefiltered normal-map variance.
	ROUGHNESS = filter_specular_roughness(final_roughness, bent);
	SPECULAR = 0.5;
#ifdef AA_TERRAIN_WET_CLEARCOAT
	// A thin liquid film contributes a second, smooth dielectric reflection
	// on top of porous rock and paving. Reuse existing sampled biome weights,
	// weather and curvature instead of fetching new mask/normal textures.
	float hard_surface = r_hard_surface; // Snow and moss are already folded in.
	float water_film = wetness * hard_surface * detail_fade;
	// Rain gathers in worn recessed stone, but moss remains porous/matte.
	water_film *= 0.86 + cavity * 0.14;
	// Steep walls shed moisture instead of reflecting like horizontal asphalt.
	water_film *= 1.0 - smoothstep(0.20, 0.70, slope) * 0.30;
	CLEARCOAT = clamp(water_film * aa_terrain_wet_clearcoat, 0.0, 0.65);
	float film_roughness = mix(0.22, 0.07,
		clamp(puddle + wetness * 0.45, 0.0, 1.0));
	// Apply the existing native normal-variance filter to the clearcoat lobe,
	// avoiding scintillating pinpoint reflections at FSR2 output resolution.
	CLEARCOAT_ROUGHNESS = filter_specular_roughness(film_roughness, bent);
#endif
	if (baking) {
		// Rendered with the Unshaded debug draw and a linear tonemap: the page stores ALBEDO, sRGB-encoded.
		// Data pages are pre-decoded so the stored bytes are the values themselves.
		if (bake_albedo) {
			ALBEDO = clamp(material_color, vec3(0.0), vec3(1.0));
		} else if (bake_data) {
			ALBEDO = aa_srgb_to_linear(vec3(bent.x * 0.5 + 0.5, bent.z * 0.5 + 0.5, r_dry_roughness));
		} else {
			ALBEDO = aa_srgb_to_linear(clamp(vec3(r_wet_factor, r_puddle_shape, r_hard_surface), vec3(0.0), vec3(1.0)));
		}
	}
}
