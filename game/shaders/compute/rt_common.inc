// Shared helpers for the hardware ray-traced compute passes (rt_shadows, rt_ao,
// rt_denoise). Original work for Cgame, written against the public Khronos
// GL_EXT_ray_query specification (no third-party shader code). Included by each
// pass via #include (rt_compositor_effect.gd inlines it itself, because raw
// RDShaderSource compilation does not resolve res:// includes).
// rt_occluded() is only emitted when RT_USE_RAY_QUERY is defined (shadow/AO passes).

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
