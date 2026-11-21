/**************************************************************************/
/*  cgame_rt_shaders.h                                                    */
/**************************************************************************/
/*                         This file is part of:                          */
/*                             GODOT ENGINE                               */
/*                        https://godotengine.org                         */
/**************************************************************************/
/* Copyright (c) 2014-present Godot Engine contributors (see AUTHORS.md). */
/* Copyright (c) 2007-2014 Juan Linietsky, Ariel Manzur.                  */
/*                                                                        */
/* Permission is hereby granted, free of charge, to any person obtaining  */
/* a copy of this software and associated documentation files (the        */
/* "Software"), to deal in the Software without restriction, including    */
/* without limitation the rights to use, copy, modify, merge, publish,    */
/* distribute, sublicense, and/or sell copies of the Software, and to     */
/* permit persons to whom the Software is furnished to do so, subject to  */
/* the following conditions:                                              */
/*                                                                        */
/* The above copyright notice and this permission notice shall be         */
/* included in all copies or substantial portions of the Software.        */
/*                                                                        */
/* THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,        */
/* EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF     */
/* MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. */
/* IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY   */
/* CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,   */
/* TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE      */
/* SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.                 */
/**************************************************************************/

#pragma once

// GLSL sources of the hardware ray-traced shadow / ambient occlusion passes. Original work for
// Cgame, written against the public Khronos GL_EXT_ray_query / VK_KHR_ray_query specifications (no
// third-party shader code). Each pass contains the line RT_COMMON_INCLUDE, which
// CgameRTEffect::prepare_source() replaces with the text of RT_COMMON_GLSL.

namespace CgameRTShaders {

inline constexpr const char *RT_COMMON_INCLUDE = "#include \"res://shaders/compute/rt_common.inc\"";

// Shared helpers: parameter block, hash, depth reconstruction, normals and (optional) ray query.
inline constexpr const char *RT_COMMON_GLSL = R"GLSL(
layout(set = 0, binding = 3, std140) uniform RtParams {
	mat4 inv_proj; // clip -> view
	mat4 cam_to_world; // view -> world
	mat4 prev_view_proj; // world -> previous frame clip
	vec4 sun_dir_radius; // xyz: direction TOWARDS the sun (world), w: angular radius (radians)
	vec4 p0; // x: width, y: height, z: frame index, w: rays per pixel
	vec4 p1; // x: shadow tmax, y: ao tmax, z: ray origin bias, w: unused
	vec4 p2; // x: shadow strength, y: ao strength, z: temporal blend, w: unused
}
rt;

float rt_hash(uvec2 p, uint frame) {
	// Integer avalanche hash (public-domain technique).
	uint h = p.x * 1664525u + p.y * 1013904223u + frame * 22695477u;
	h ^= h >> 16;
	h *= 2246822519u;
	h ^= h >> 13;
	h *= 3266489917u;
	h ^= h >> 16;
	return float(h & 0xFFFFFFu) / 16777216.0;
}

vec3 rt_view_pos(vec2 uv, float depth) {
	vec4 v = rt.inv_proj * vec4(uv * 2.0 - 1.0, depth, 1.0);
	return v.xyz / v.w;
}

vec3 rt_world_pos(vec2 uv, float depth) {
	return (rt.cam_to_world * vec4(rt_view_pos(uv, depth), 1.0)).xyz;
}

// Geometric normal from depth derivatives (picks the smaller-difference side
// on each axis to avoid smearing across depth discontinuities).
vec3 rt_world_normal(sampler2D depth_tex, ivec2 px, vec2 inv_size, vec3 view_pos) {
	ivec2 size = ivec2(1.0 / inv_size + 0.5);
	vec2 uv = (vec2(px) + 0.5) * inv_size;
	vec3 r = rt_view_pos(uv + vec2(inv_size.x, 0.0), texelFetch(depth_tex, min(px + ivec2(1, 0), size - 1), 0).r);
	vec3 l = rt_view_pos(uv - vec2(inv_size.x, 0.0), texelFetch(depth_tex, max(px - ivec2(1, 0), ivec2(0)), 0).r);
	vec3 u = rt_view_pos(uv - vec2(0.0, inv_size.y), texelFetch(depth_tex, max(px - ivec2(0, 1), ivec2(0)), 0).r);
	vec3 d = rt_view_pos(uv + vec2(0.0, inv_size.y), texelFetch(depth_tex, min(px + ivec2(0, 1), size - 1), 0).r);
	vec3 dx = abs(r.z - view_pos.z) < abs(view_pos.z - l.z) ? r - view_pos : view_pos - l;
	vec3 dy = abs(d.z - view_pos.z) < abs(view_pos.z - u.z) ? d - view_pos : view_pos - u;
	vec3 n = normalize(cross(dx, dy));
	// Face the camera (view space looks down -Z).
	if (dot(n, view_pos) > 0.0) {
		n = -n;
	}
	return normalize((rt.cam_to_world * vec4(n, 0.0)).xyz);
}

vec3 rt_tangent_any(vec3 n) {
	return normalize(abs(n.y) < 0.99 ? cross(n, vec3(0.0, 1.0, 0.0)) : cross(n, vec3(1.0, 0.0, 0.0)));
}

#ifdef RT_USE_RAY_QUERY
// True when anything opaque lies within [tmin, tmax] along the ray.
bool rt_occluded(accelerationStructureEXT tlas, vec3 origin, vec3 dir, float tmin, float tmax) {
	rayQueryEXT rq;
	rayQueryInitializeEXT(rq, tlas, gl_RayFlagsTerminateOnFirstHitEXT | gl_RayFlagsOpaqueEXT, 0xFF, origin, tmin, dir, tmax);
	while (rayQueryProceedEXT(rq)) {
	}
	return rayQueryGetIntersectionTypeEXT(rq, true) != gl_RayQueryCommittedIntersectionNoneEXT;
}
#endif
)GLSL";

// Directional-light shadows: one jittered ray per pixel towards the sun disc.
inline constexpr const char *RT_SHADOWS_GLSL = R"GLSL(#version 460

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
)GLSL";

// Ambient occlusion: cosine-weighted hemisphere rays of limited length.
inline constexpr const char *RT_AO_GLSL = R"GLSL(#version 460

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
)GLSL";

// Spatial (depth-aware 5x5) + temporal (reprojected, neighbourhood-clamped) denoise of the raw
// visibility, then composite onto the scene colour.
inline constexpr const char *RT_DENOISE_GLSL = R"GLSL(#version 450

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
)GLSL";

} //namespace CgameRTShaders
