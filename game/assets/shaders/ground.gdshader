shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
global uniform float aa_weather_wetness;
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

// Albedo of one layer seen from above, at two scales mixed by noise (`mixer`).
vec3 top_albedo(float layer, vec2 p, float mixer) {
	vec3 near_tile = texture(albedo_layers, vec3(p / tile_meters, layer)).rgb;
	vec3 far_tile = texture(albedo_layers, vec3(p / (tile_meters * 3.3) + 0.37, layer)).rgb;
	return mix(near_tile, far_tile, mixer) * layer_tint[int(layer)];
}

vec3 top_normal(float layer, vec2 p) {
	vec3 n = texture(normal_layers, vec3(p / tile_meters, layer)).rgb * 2.0 - 1.0;
	return vec3(n.x, n.y, n.z);
}

void fragment() {
	vec2 p = world_position.xz;
	float h = world_position.y;
	vec3 n = normalize(world_normal);
	float slope = 1.0 - clamp(n.y, 0.0, 1.0);
	float broad = fbm(p * 0.012);
	float mid = fbm(p * 0.07 + 3.0);
	float mixer = smoothstep(0.3, 0.7, value_noise(p * 0.05 + 11.0));

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
	// Old pavement of ruined cities and bunkers: a ragged edge, and grass coming up through it in patches.
	for (int k = 0; k < 4; k++) {
		vec4 patch = site_patches[k];
		if (patch.z <= 0.0) {
			continue;
		}
		float d = length(p - patch.xy) / patch.z;
		float paved = 1.0 - smoothstep(0.7, 1.0, d + (mid - 0.5) * 0.35);
		// Grass has taken back much of it: whole drifts of green, and moss everywhere else.
		paved *= 1.0 - 0.9 * smoothstep(0.42, 0.68, fbm(p * 0.11 + 5.0)) * (1.0 - cliff);
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

	vec3 color = vec3(0.0);
	vec3 bump = vec3(0.0, 0.0, 0.0);
	float total = 0.0;
	for (int i = 0; i < 13; i++) {
		if (w[i] < 0.02) {
			continue;
		}
		float layer = float(i);
		vec3 c;
		vec3 nn;
		if (i == 5) {
			// Triplanar cliff rock.
			vec3 blend = pow(abs(n), vec3(4.0));
			blend /= (blend.x + blend.y + blend.z);
			c = texture(albedo_layers, vec3(world_position.zy / tile_meters, layer)).rgb * blend.x
				+ texture(albedo_layers, vec3(p / tile_meters, layer)).rgb * blend.y
				+ texture(albedo_layers, vec3(world_position.xy / tile_meters, layer)).rgb * blend.z;
			c *= layer_tint[5];
			nn = vec3(0.0, 0.0, 1.0);
		} else {
			c = top_albedo(layer, p, mixer);
			nn = top_normal(layer, p);
		}
		color += c * w[i];
		bump += nn * w[i];
		total += w[i];
	}
	color /= max(total, 0.0001);
	bump /= max(total, 0.0001);

	// Large-scale light and colour variation, a little darker where the shore is wet.
	color *= 0.86 + 0.28 * broad;
	color = mix(color, color * 0.6, 1.0 - smoothstep(-1.4, 0.8, h));
	// A touch more saturation to sit with the stylised models.
	float grey = dot(color, vec3(0.299, 0.587, 0.114));
	color = mix(vec3(grey), color, 1.15);

	// Normal map in world space: the ground is mapped from above, so x and z are the tangent axes.
	vec3 tangent = normalize(vec3(1.0, 0.0, 0.0) - n * n.x);
	vec3 bitangent = normalize(cross(n, tangent));
	vec3 detail = normalize(vec3(bump.xy * normal_strength, max(bump.z, 0.2)));
	vec3 bent = normalize(tangent * detail.x + bitangent * detail.y + n * detail.z);

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
	float dry_roughness = mix(0.92, 0.6, w[8]) - 0.15 * shore;
	ROUGHNESS = mix(mix(dry_roughness, 0.28, wetness * 0.55), 0.08, puddle * 0.9);
	SPECULAR = min(0.9, 0.2 + wetness * 0.2 + puddle * 0.3);
}
