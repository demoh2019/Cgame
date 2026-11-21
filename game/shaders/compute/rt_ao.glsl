#[compute]
#version 460
// Hardware ray-traced ambient occlusion: cosine-weighted hemisphere rays of
// limited length via GL_EXT_ray_query. Original work for Cgame.

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
	if (depth <= 0.0) {
		imageStore(out_tex, px, vec4(1.0));
		return;
	}
	vec2 inv_size = 1.0 / rt.p0.xy;
	vec2 uv = (vec2(px) + 0.5) * inv_size;
	vec3 vpos = rt_view_pos(uv, depth);
	vec3 wpos = (rt.cam_to_world * vec4(vpos, 1.0)).xyz;
	vec3 n = rt_world_normal(depth_tex, px, inv_size, vpos);
	vec3 t = rt_tangent_any(n);
	vec3 b = cross(n, t);

	uint frame = uint(rt.p0.z);
	int rays = max(int(rt.p0.w), 1);
	float bias = rt.p1.z * (1.0 + length(vpos) * 0.02);
	vec3 origin = wpos + n * bias;
	float visible = 0.0;
	for (int i = 0; i < rays; i++) {
		uint salt = frame * 31u + uint(i) * 977u;
		float r1 = rt_hash(uvec2(px), salt);
		float r2 = rt_hash(uvec2(px) + uvec2(15485u, 32452u), salt);
		// Cosine-weighted hemisphere sample.
		float rr = sqrt(r1);
		float phi = 6.2831853 * r2;
		vec3 dir = normalize(t * (rr * cos(phi)) + b * (rr * sin(phi)) + n * sqrt(max(1.0 - r1, 0.0)));
		if (!rt_occluded(tlas, origin, dir, 0.0, rt.p1.y)) {
			visible += 1.0;
		}
	}
	imageStore(out_tex, px, vec4(visible / float(rays)));
}
