#[compute]

#version 450

#VERSION_DEFINES

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(set = 0, binding = 0) uniform sampler2D source_depth;
layout(set = 0, binding = 1) uniform sampler2D source_normal_roughness;
layout(set = 0, binding = 2) uniform sampler2D source_depth_half;
layout(set = 0, binding = 3) uniform sampler2D source_normal_roughness_half;
layout(set = 0, binding = 4) uniform sampler2D source_color;
layout(set = 0, binding = 5) uniform sampler2D source_mip_level;
layout(rgba16f, set = 0, binding = 6) uniform restrict writeonly image2D output_color;

layout(push_constant, std430) uniform Params {
	ivec2 screen_size;
	ivec2 pad;
}
params;

void get_sample(float depth, vec3 normal, float roughness, ivec2 pixel_pos,
		ivec2 half_size, out vec4 color, out float weight) {
	// A 2x2 bilateral footprint overlaps the image border; replicate the
	// last real texel instead of invoking undefined texelFetch on Metal.
	ivec2 safe_pixel = clamp(pixel_pos, ivec2(0), half_size - ivec2(1));
	float sample_depth = texelFetch(source_depth_half, safe_pixel, 0).x;
	vec4 sample_normal_roughness = texelFetch(source_normal_roughness_half, safe_pixel, 0);
	vec3 sample_normal = normalize(sample_normal_roughness.xyz * 2.0 - 1.0);
	float sample_roughness = sample_normal_roughness.w;
	if (sample_roughness > 0.5) {
		sample_roughness = 1.0 - sample_roughness;
	}
	sample_roughness /= (127.0 / 255.0);

	// Use the allocated half-resolution image dimensions (which may be
	// rounded on odd-sized viewports), not a guessed full_size * 0.5.
	vec2 uv = (vec2(safe_pixel) + vec2(0.5)) / vec2(half_size);

	float mip_level = texelFetch(source_mip_level, safe_pixel, 0).x * 14.0;
	color = textureLod(source_color, uv, mip_level);

	// Input RGB is tone-compressed radiance premultiplied by hit
	// confidence. Invalid rays should not become black reflections.
	float confidence = clamp(color.a, 0.0, 1.0);
	if (confidence <= 0.0001) {
		color = vec4(0.0);
		weight = 0.0;
		return;
	}
	const vec3 rec709_luminance_weights = vec3(0.2126, 0.7152, 0.0722);
	// Unpremultiply before inverting the HDR transform; otherwise
	// partial-confidence edges lose energy and shift reflection color.
	vec3 straight_tonemapped = color.rgb / confidence;
	float tone_denom = max(1.0 - dot(straight_tonemapped, rec709_luminance_weights), 0.01);
	color.rgb = (straight_tonemapped / tone_denom) * confidence;
	color.a = confidence;

	const float DEPTH_FACTOR = 2048.0;
	const float NORMAL_FACTOR = 32.0;
	const float ROUGHNESS_FACTOR = 16.0;

	float depth_diff = abs(depth - sample_depth);
	float weight_depth = exp(-depth_diff * DEPTH_FACTOR);

	float normal_diff = clamp(1.0 - dot(normal, sample_normal), 0.0, 1.0);
	float weight_normal = exp(-normal_diff * NORMAL_FACTOR);

	float roughness_diff = abs(roughness - sample_roughness);
	float weight_roughness = exp(-roughness_diff * ROUGHNESS_FACTOR);

	// Prioritize genuine SSR hits within the same four-tap footprint;
	// preserve alpha so the existing sky/probe path fills ray misses.
	float confidence_weight = smoothstep(0.02, 0.45, confidence);
	weight = weight_depth * weight_normal * weight_roughness * confidence_weight;
}

void main() {
	ivec2 pixel_pos = ivec2(gl_GlobalInvocationID.xy);

	if (any(greaterThanEqual(pixel_pos, params.screen_size))) {
		return;
	}

	float depth = texelFetch(source_depth, pixel_pos, 0).x;
	vec4 normal_roughness = texelFetch(source_normal_roughness, pixel_pos, 0);
	vec3 normal = normalize(normal_roughness.xyz * 2.0 - 1.0);
	float roughness = normal_roughness.w;
	if (roughness > 0.5) {
		roughness = 1.0 - roughness;
	}
	roughness /= (127.0 / 255.0);

	// True center-to-center mapping from full pixels to half-resolution
	// texels, including non-even window sizes and fractional render scales.
	// floor() is required: signed integer division rounds toward zero and
	// selected the wrong footprint for pixel 0 on left/top borders.
	ivec2 half_size = textureSize(source_depth_half, 0);
	vec2 half_tex_coord = (vec2(pixel_pos) + vec2(0.5)) *
			vec2(half_size) / vec2(params.screen_size) - vec2(0.5);
	ivec2 base_pixel = ivec2(floor(half_tex_coord));
	vec2 bilinear_weights = fract(half_tex_coord);

	vec4 color0, color1, color2, color3;
	float weight0, weight1, weight2, weight3;

	get_sample(depth, normal, roughness, base_pixel + ivec2(0, 0), half_size, color0, weight0);
	get_sample(depth, normal, roughness, base_pixel + ivec2(1, 0), half_size, color1, weight1);
	get_sample(depth, normal, roughness, base_pixel + ivec2(0, 1), half_size, color2, weight2);
	get_sample(depth, normal, roughness, base_pixel + ivec2(1, 1), half_size, color3, weight3);

	// Match each (x,y) sample with its actual bilinear kernel corner;
	// the old inverted weights shifted and reflected glossy SSR details.
	weight0 *= (1.0 - bilinear_weights.x) * (1.0 - bilinear_weights.y);
	weight1 *= bilinear_weights.x * (1.0 - bilinear_weights.y);
	weight2 *= (1.0 - bilinear_weights.x) * bilinear_weights.y;
	weight3 *= bilinear_weights.x * bilinear_weights.y;

	vec4 result_color = color0 * weight0 + color1 * weight1 + color2 * weight2 + color3 * weight3;
	float result_weight = weight0 + weight1 + weight2 + weight3;
	if (result_weight > 0.0) {
		result_color /= result_weight;
	} else {
		result_color = vec4(0.0);
	}

	imageStore(output_color, pixel_pos, result_color);
}
