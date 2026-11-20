shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
global uniform float aa_weather_wetness;
// Radius of full two-scale albedo and normal mapping; shared by all streamed chunks.
global uniform float aa_terrain_detail_radius;
// Maximum number of PBR layers sampled per pixel (Ultra = all layers).
global uniform int aa_terrain_layer_budget;
global uniform float aa_cliff_normal_quality; // 0 on low-end, 0.7 High, 1 Ultra
#include "res://assets/shaders/cloud_shadow.gdshaderinc"

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
uniform vec2 chunk_origin = vec2(0.0);
uniform float chunk_size = 64.0;
uniform float biome_texels = 17.0;
uniform float tile_meters = 6.0;
uniform float normal_strength = 0.8;
// Per-layer multiplier that moves the photo's average colour to the game's palette (computed on load).
uniform vec3 layer_tint[13];
// Average color of each material: cheap residual retains all biome transitions when texture taps are limited.
uniform vec3 layer_average[13];
// Paved ground of the sites near this chunk: x, z, radius, layer (radius 0: unused). Weeds take back the cracks.
uniform vec4 site_patches[4];

varying vec3 world_position;
varying vec3 world_normal;

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
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

// Distant terrain keeps the existing broad-scale tiling, but skips nearby microdetail samples.
// The blending weight tends smoothly to zero, avoiding hard texture LOD boundaries.
vec3 top_albedo(float layer, vec2 p, float mixer, float detail_fade, vec2 lod_dx, vec2 lod_dy) {
	vec3 far_tile = textureGrad(albedo_layers, vec3(p / (tile_meters * 3.3) + 0.37, layer), lod_dx / 3.3, lod_dy / 3.3).rgb;
	float near_weight = (1.0 - mixer) * detail_fade;
	if (near_weight > 0.001) {
		vec3 near_tile = textureGrad(albedo_layers, vec3(p / tile_meters, layer), lod_dx, lod_dy).rgb;
		far_tile = mix(far_tile, near_tile, near_weight);
	}
	return far_tile * layer_tint[int(layer)];
}

vec3 top_normal(float layer, vec2 p, float detail_fade, vec2 lod_dx, vec2 lod_dy) {
	// When far enough, even the normal map fetch is skipped: distant microrelief is subpixel.
	vec3 normal = vec3(0.0, 0.0, 1.0);
	if (detail_fade > 0.001) {
		vec3 mapped = textureGrad(normal_layers, vec3(p / tile_meters, layer), lod_dx, lod_dy).rgb * 2.0 - 1.0;
		normal = mix(normal, mapped, detail_fade);
	}
	return normal;
}

void fragment() {
	vec2 p = world_position.xz;
	float h = world_position.y;
	vec3 n = normalize(world_normal);
	float slope = 1.0 - clamp(n.y, 0.0, 1.0);
	float broad = fbm(p * 0.012);
	float mid = fbm(p * 0.07 + 3.0);
	float mixer = smoothstep(0.3, 0.7, value_noise(p * 0.05 + 11.0));
	// View-dependent terrain shading LOD is continuous and independent of chunk boundaries.
	// All visible biomes/roads remain authored by the original high fidelity blend.
	// Gradients must be evaluated before any dynamic branch to keep mipmapping stable.
	vec2 lod_dx = dFdx(p / tile_meters);
	vec2 lod_dy = dFdy(p / tile_meters);
	// Explicit derivatives must be evaluated outside branch-dependent cliff samples.
	vec2 cliff_dx_zy = dFdx(world_position.zy / tile_meters);
	vec2 cliff_dy_zy = dFdy(world_position.zy / tile_meters);
	vec2 cliff_dx_xy = dFdx(world_position.xy / tile_meters);
	vec2 cliff_dy_xy = dFdy(world_position.xy / tile_meters);
	float camera_distance = distance(p, CAMERA_POSITION_WORLD.xz);
	float detail_fade = 1.0 - smoothstep(aa_terrain_detail_radius,
		aa_terrain_detail_radius + 24.0, camera_distance);

	// Biome weights from the chunk map, sampled between texel centres so neighbouring chunks meet exactly.
	vec2 local = (p - chunk_origin) / chunk_size;
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
	vec3 color = macro_color;
	vec3 bump = vec3(0.0);
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
		vec3 nn;
		if (i == 5) {
			// Cliffs keep their triplanar mapping; explicit gradients avoid invalid
			// implicit mip derivatives after a texture-layer selection branch.
			vec3 blend = pow(abs(n), vec3(4.0));
			blend /= max(blend.x + blend.y + blend.z, 0.0001);
			c = textureGrad(albedo_layers, vec3(world_position.zy / tile_meters, layer), cliff_dx_zy, cliff_dy_zy).rgb * blend.x
				+ textureGrad(albedo_layers, vec3(p / tile_meters, layer), lod_dx, lod_dy).rgb * blend.y
				+ textureGrad(albedo_layers, vec3(world_position.xy / tile_meters, layer), cliff_dx_xy, cliff_dy_xy).rgb * blend.z;
			c *= layer_tint[5];
			// High/Ultra cliff relief: triplanar normal mapping with stable
			// explicit texture gradients. No extra samples on low settings
			// or distant/subpixel terrain.
			if (aa_cliff_normal_quality > 0.001 && detail_fade > 0.001) {
				vec3 nx = textureGrad(normal_layers,
					vec3(world_position.zy / tile_meters, layer),
					cliff_dx_zy, cliff_dy_zy).rgb * 2.0 - 1.0;
				vec3 ny = textureGrad(normal_layers,
					vec3(p / tile_meters, layer),
					lod_dx, lod_dy).rgb * 2.0 - 1.0;
				vec3 nz = textureGrad(normal_layers,
					vec3(world_position.xy / tile_meters, layer),
					cliff_dx_xy, cliff_dy_xy).rgb * 2.0 - 1.0;
				vec3 along_x = normalize(vec3(sign(n.x) * nx.z, nx.y, nx.x));
				vec3 along_y = normalize(vec3(ny.x, sign(n.y) * ny.z, ny.y));
				vec3 along_z = normalize(vec3(nz.x, nz.y, sign(n.z) * nz.z));
				cliff_world_normal = normalize(
					along_x * blend.x + along_y * blend.y + along_z * blend.z);
			}
			nn = vec3(0.0, 0.0, 1.0);
		} else {
			c = top_albedo(layer, p, mixer, detail_fade, lod_dx, lod_dy);
			nn = top_normal(layer, p, detail_fade, lod_dx, lod_dy);
		}
		// Replace the approximate layer color with the actual PBR texture; the
		// unselected layers still contribute their average palette color.
		color += (c - layer_average[i]) * w[i];
		bump += nn * w[i];
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
	vec3 bent = normalize(tangent * detail.x + bitangent * detail.y + n * detail.z);
	// The cliff relief never bleeds into a grassy or paved transition.
	float cliff_mix = clamp(w[5] / max(all_weight, 0.0001), 0.0, 1.0)
		* clamp(aa_cliff_normal_quality, 0.0, 1.0) * detail_fade;
	bent = normalize(mix(bent, cliff_world_normal, cliff_mix));

	// Wet earth absorbs light; shallow mud and worn pavement collect small smooth puddles.
	// Reuse existing biome and noise weights instead of additional texture reads or noise octaves.
	float wettable = clamp(w[3] + w[4] + w[7] * 0.65 + w[9] + w[10] + w[2] * 0.25, 0.0, 1.0);
	float wetness = clamp(aa_weather_wetness, 0.0, 1.0) * (0.22 + 0.78 * wettable) * (1.0 - clamp(w[8], 0.0, 1.0));
	float puddle = wetness * clamp(w[3] + w[4] + w[9] + w[10], 0.0, 1.0)
		* smoothstep(0.52, 0.78, mid) * (1.0 - smoothstep(0.08, 0.25, slope));
	bent = normalize(mix(bent, n, puddle * 0.75));
	NORMAL = normalize((VIEW_MATRIX * vec4(bent, 0.0)).xyz);

	color *= 1.0 - wetness * 0.18 - puddle * 0.12;
	ALBEDO = apply_cloud_shadow(color, p, TIME);
	// A physically plausible microfacet roughness for each existing layer.
	// This reuses the 13 biome weights (no extra textures or VRAM).
	float dry_roughness = (
		w[0] * 0.91 + w[1] * 0.94 + w[2] * 0.88 + w[3] * 0.86
		+ w[4] * 0.89 + w[5] * 0.73 + w[6] * 0.77 + w[7] * 0.93
		+ w[8] * 0.94 + w[9] * 0.72 + w[10] * 0.83
		+ w[11] * 0.78 + w[12] * 0.82) / max(all_weight, 0.0001);
	dry_roughness = clamp(dry_roughness + (mid - 0.5) * 0.055, 0.55, 0.98);
	// Moss is diffuse and rough; keep the smooth puddle override below intact.
	dry_roughness = mix(dry_roughness, 0.92, ruin_moss * 0.45);
	// Wetness changes roughness, not the dielectric material's F0.
	// Existing shallow puddles still produce very tight highlights.
	ROUGHNESS = clamp(
		mix(mix(dry_roughness, 0.28, wetness * 0.55), 0.08, puddle * 0.9),
		0.045, 1.0);
	SPECULAR = 0.5;
}
