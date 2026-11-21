#[compute]

#version 450

#VERSION_DEFINES

// Generates the frame at time t between the previous and the current frame.
// flow = previous_uv - current_uv, defined at current-frame positions.

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(set = 0, binding = 0) uniform sampler2D prev_color;
layout(set = 0, binding = 1) uniform sampler2D cur_color;
layout(set = 0, binding = 2) uniform sampler2D flow_tex;
layout(set = 0, binding = 3) uniform sampler2D prev_depth;
layout(set = 0, binding = 4) uniform sampler2D cur_depth;
layout(rgba16f, set = 0, binding = 5) uniform restrict writeonly image2D output_image;

layout(push_constant, std430) uniform Params {
	vec2 size;
	vec2 inv_size;
	float t; // Interpolation phase, 0 = previous frame, 1 = current frame.
	float depth_threshold;
	float pad0;
	float pad1;
}
params;

void main() {
	ivec2 pos = ivec2(gl_GlobalInvocationID.xy);
	if (any(greaterThanEqual(vec2(pos), params.size))) {
		return;
	}

	vec2 uv_t = (vec2(pos) + 0.5) * params.inv_size;

	// Find the current-frame position that lands on uv_t at time t (short fixed-point iteration):
	// uv_cur + (1 - t) * flow(uv_cur) = uv_t.
	vec2 uv_cur = uv_t;
	vec4 f = textureLod(flow_tex, uv_cur, 0.0);
	for (int i = 0; i < 2; i++) {
		uv_cur = clamp(uv_t - (1.0 - params.t) * f.xy, vec2(0.0), vec2(1.0));
		f = textureLod(flow_tex, uv_cur, 0.0);
	}
	vec2 uv_prev = uv_cur + f.xy;

	vec3 c_cur = textureLod(cur_color, uv_cur, 0.0).rgb;
	vec3 c_prev = textureLod(prev_color, uv_prev, 0.0).rgb;
	vec3 c_plain = mix(textureLod(prev_color, uv_t, 0.0).rgb, textureLod(cur_color, uv_t, 0.0).rgb, params.t);

	// Disocclusion: the previous surface at the reprojected position must match the current one.
	float d_cur = textureLod(cur_depth, uv_cur, 0.0).x;
	float d_prev = textureLod(prev_depth, uv_prev, 0.0).x;
	bool out_of_screen = any(lessThan(uv_prev, vec2(0.0))) || any(greaterThan(uv_prev, vec2(1.0)));
	float depth_diff = abs(d_cur - d_prev) / max(max(d_cur, d_prev), 1e-5);
	float valid = (out_of_screen || depth_diff > params.depth_threshold) ? 0.0 : 1.0;

	vec3 warped = mix(c_prev, c_cur, params.t);
	vec3 result = mix(c_cur, warped, valid);

	// Low confidence optical flow: fall back to a plain cross-fade, which is the least objectionable failure.
	result = mix(c_plain, result, smoothstep(0.1, 0.5, f.z));

	imageStore(output_image, pos, vec4(result, 1.0));
}
