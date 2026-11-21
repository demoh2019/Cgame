#[compute]

#version 450

#VERSION_DEFINES

// Optical-flow-lite refinement. Starts from the engine velocity buffer (previous_uv - current_uv)
// and refines it with a small block-matching search on luma between the previous and current
// frame. Outputs the refined motion (uv units) and a confidence value.

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(set = 0, binding = 0) uniform sampler2D prev_color;
layout(set = 0, binding = 1) uniform sampler2D cur_color;
layout(set = 0, binding = 2) uniform sampler2D velocity_buffer;
layout(rgba16f, set = 0, binding = 3) uniform restrict writeonly image2D flow_image;

layout(push_constant, std430) uniform Params {
	vec2 size;
	vec2 inv_size;
	float search_scale; // 0 disables the refinement (game motion vectors only).
	float pad0;
	float pad1;
	float pad2;
}
params;

float luma(vec3 c) {
	return dot(c, vec3(0.299, 0.587, 0.114));
}

float patch_sad(vec2 uv_cur, vec2 uv_prev) {
	float sad = 0.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 o = vec2(x, y) * params.inv_size;
			sad += abs(luma(textureLod(cur_color, uv_cur + o, 0.0).rgb) - luma(textureLod(prev_color, uv_prev + o, 0.0).rgb));
		}
	}
	return sad / 9.0;
}

void main() {
	ivec2 pos = ivec2(gl_GlobalInvocationID.xy);
	if (any(greaterThanEqual(vec2(pos), params.size))) {
		return;
	}

	vec2 uv = (vec2(pos) + 0.5) * params.inv_size;
	vec2 mv = textureLod(velocity_buffer, uv, 0.0).xy;
	if (any(greaterThanEqual(abs(mv), vec2(1.0)))) {
		mv = vec2(0.0); // Invalid/cleared motion.
	}

	float best = patch_sad(uv, uv + mv);
	vec2 best_mv = mv;

	if (params.search_scale > 0.0) {
		for (int y = -2; y <= 2; y++) {
			for (int x = -2; x <= 2; x++) {
				if (x == 0 && y == 0) {
					continue;
				}
				vec2 cand = mv + vec2(x, y) * params.inv_size * params.search_scale;
				float s = patch_sad(uv, uv + cand) + 0.002 * length(vec2(x, y)); // Prefer the game vector on ties.
				if (s < best) {
					best = s;
					best_mv = cand;
				}
			}
		}
	}

	float confidence = 1.0 - clamp(best * 8.0, 0.0, 1.0);
	imageStore(flow_image, pos, vec4(best_mv, confidence, 0.0));
}
