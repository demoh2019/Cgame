#[compute]
#version 450
// Spatial (depth-aware 5x5) + temporal (reprojected, neighbourhood-clamped)
// denoise of the raw RT shadow / AO visibility, then composite onto the scene
// colour. Original work for Cgame; standard technique.

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(set = 0, binding = 0) uniform sampler2D depth_tex;
layout(r16f, set = 0, binding = 1) uniform restrict readonly image2D raw_shadow;
layout(r16f, set = 0, binding = 2) uniform restrict readonly image2D raw_ao;
layout(set = 0, binding = 4) uniform sampler2D hist_in;
layout(rg16f, set = 0, binding = 5) uniform restrict writeonly image2D hist_out;
layout(rgba16f, set = 0, binding = 6) uniform restrict image2D color_tex;
#include "res://shaders/compute/rt_common.inc"

void main() {
	ivec2 px = ivec2(gl_GlobalInvocationID.xy);
	ivec2 size = ivec2(rt.p0.xy);
	if (px.x >= size.x || px.y >= size.y) {
		return;
	}
	float depth = texelFetch(depth_tex, px, 0).r;
	if (depth <= 0.0) {
		imageStore(hist_out, px, vec4(1.0));
		return;
	}
	vec2 inv_size = 1.0 / rt.p0.xy;
	float lin = -rt_view_pos((vec2(px) + 0.5) * inv_size, depth).z;

	// Spatial depth-aware filter, plus min/max of the 3x3 for history clamping.
	vec2 sum = vec2(0.0);
	float wsum = 0.0;
	vec2 vmin = vec2(1.0);
	vec2 vmax = vec2(0.0);
	for (int y = -2; y <= 2; y++) {
		for (int x = -2; x <= 2; x++) {
			ivec2 q = clamp(px + ivec2(x, y), ivec2(0), size - 1);
			float dq = texelFetch(depth_tex, q, 0).r;
			if (dq <= 0.0) {
				continue;
			}
			float lq = -rt_view_pos((vec2(q) + 0.5) * inv_size, dq).z;
			float w = exp(-abs(lq - lin) / max(lin * 0.02, 0.01)) * exp(-float(x * x + y * y) * 0.2);
			vec2 v = vec2(imageLoad(raw_shadow, q).r, imageLoad(raw_ao, q).r);
			sum += v * w;
			wsum += w;
			if (abs(x) <= 1 && abs(y) <= 1) {
				vmin = min(vmin, v);
				vmax = max(vmax, v);
			}
		}
	}
	vec2 cur = wsum > 0.0 ? sum / wsum : vec2(1.0);

	// Temporal reprojection.
	vec3 wpos = rt_world_pos((vec2(px) + 0.5) * inv_size, depth);
	vec4 pc = rt.prev_view_proj * vec4(wpos, 1.0);
	vec2 puv = (pc.xy / pc.w) * 0.5 + 0.5;
	vec2 result = cur;
	if (pc.w > 0.0 && all(greaterThanEqual(puv, vec2(0.0))) && all(lessThanEqual(puv, vec2(1.0))) && rt.p0.z > 0.0) {
		vec2 h = textureLod(hist_in, puv, 0.0).rg;
		h = clamp(h, vmin, vmax);
		result = mix(cur, h, rt.p2.z);
	}
	imageStore(hist_out, px, vec4(result, 0.0, 1.0));

	vec4 c = imageLoad(color_tex, px);
	float f = mix(1.0, result.x, rt.p2.x) * mix(1.0, result.y, rt.p2.y);
	imageStore(color_tex, px, vec4(c.rgb * f, c.a));
}
