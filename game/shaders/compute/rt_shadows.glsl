#[compute]
#version 460
// Hardware ray-traced directional-light shadows: one jittered ray per pixel
// towards the sun disc (soft penumbra from the sun's angular radius), via
// GL_EXT_ray_query against the TLAS. Original work for Cgame.

#extension GL_EXT_ray_query : require
#define RT_USE_RAY_QUERY

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(set = 0, binding = 0) uniform accelerationStructureEXT tlas;
layout(set = 0, binding = 1) uniform sampler2D depth_tex;
layout(r16f, set = 0, binding = 2) uniform restrict writeonly image2D out_tex;
#include "res://shaders/compute/rt_common.inc"

void main() {
	ivec2 px = ivec2(gl_GlobalInvocationID.xy);
	ivec2 size = ivec2(rt.p0.xy);
	if (px.x >= size.x || px.y >= size.y) {
		return;
	}
	float depth = texelFetch(depth_tex, px, 0).r;
	if (depth <= 0.0) { // reverse-Z: 0 is the far plane / sky
		imageStore(out_tex, px, vec4(1.0));
		return;
	}
	vec2 inv_size = 1.0 / rt.p0.xy;
	vec2 uv = (vec2(px) + 0.5) * inv_size;
	vec3 vpos = rt_view_pos(uv, depth);
	vec3 wpos = (rt.cam_to_world * vec4(vpos, 1.0)).xyz;
	vec3 n = rt_world_normal(depth_tex, px, inv_size, vpos);

	vec3 L = normalize(rt.sun_dir_radius.xyz);
	if (dot(n, L) <= 0.0) { // already unlit by the sun
		imageStore(out_tex, px, vec4(1.0));
		return;
	}

	uint frame = uint(rt.p0.z);
	float r1 = rt_hash(uvec2(px), frame);
	float r2 = rt_hash(uvec2(px) + uvec2(7919u, 10429u), frame);
	// Uniform sample of the sun's disc.
	float a = sqrt(r1) * tan(rt.sun_dir_radius.w);
	float phi = 6.2831853 * r2;
	vec3 t = rt_tangent_any(L);
	vec3 b = cross(L, t);
	vec3 dir = normalize(L + t * (a * cos(phi)) + b * (a * sin(phi)));

	// Bias along the normal, scaled with distance to hide depth-precision acne.
	float bias = rt.p1.z * (1.0 + length(vpos) * 0.02);
	bool hit = rt_occluded(tlas, wpos + n * bias, dir, 0.0, rt.p1.x);
	imageStore(out_tex, px, vec4(hit ? 0.0 : 1.0));
}
