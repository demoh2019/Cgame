#[compute]

#version 450

#VERSION_DEFINES

// Stores the current final 3D color and depth as the history for the next frame.

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(set = 0, binding = 0) uniform sampler2D cur_color;
layout(set = 0, binding = 1) uniform sampler2D cur_depth;
layout(rgba16f, set = 0, binding = 2) uniform restrict writeonly image2D history_color;
layout(r32f, set = 0, binding = 3) uniform restrict writeonly image2D history_depth;

layout(push_constant, std430) uniform Params {
	vec2 size;
	vec2 inv_size;
}
params;

void main() {
	ivec2 pos = ivec2(gl_GlobalInvocationID.xy);
	if (any(greaterThanEqual(vec2(pos), params.size))) {
		return;
	}
	vec2 uv = (vec2(pos) + 0.5) * params.inv_size;
	imageStore(history_color, pos, vec4(textureLod(cur_color, uv, 0.0).rgb, 1.0));
	imageStore(history_depth, pos, vec4(textureLod(cur_depth, uv, 0.0).x, 0.0, 0.0, 0.0));
}
