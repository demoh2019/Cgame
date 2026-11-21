#[compute]
#version 450

// GPU per-instance frustum + Hi-Z-lite occlusion culling with visible-index compaction.
// Original implementation (project license). Technique credit: the compute pipeline layout
// follows the public Godot 4 RenderingDevice "compute shader plus GDScript" tutorial pattern
// (godot-docs, CC-BY-3.0 docs / MIT engine examples; concepts only, no code copied). The
// plane/AABB test is the standard "p-vertex" test; Hi-Z follows the classic max-depth pyramid idea.
//
// Conventions (mirrored exactly by gpu_instance_culling.gd CPU fallback):
//   planes   : outward-facing (Godot Camera3D.get_frustum()); inside <=> dot(n, x) - d <= 0.
//   hiz      : single low-res level of per-texel MAX occluder depth, depth01 = ndc.z * 0.5 + 0.5,
//              texel row 0 = ndc.y -1, uv = ndc.xy * 0.5 + 0.5.
//   output   : Visible.count is the atomic append counter; the first 4 uints form an
//              indirect-friendly header {count, 1, 1, 0} so a tiny follow-up pass (or
//              dispatch-indirect) can consume it directly. Order of indices is nondeterministic
//              on the GPU; the host sorts after readback.

layout(local_size_x = 64, local_size_y = 1, local_size_z = 1) in;

struct Instance {
	vec4 center;
	vec4 half_ext;
};

layout(set = 0, binding = 0, std430) restrict readonly buffer Instances {
	Instance items[];
} instances;

layout(set = 0, binding = 1, std430) restrict readonly buffer Planes {
	vec4 p[];
} planes;

layout(set = 0, binding = 2, std430) restrict buffer Visible {
	uint count;
	uint group_y;
	uint group_z;
	uint pad;
	uint indices[];
} visible;

layout(set = 0, binding = 3, std430) restrict readonly buffer HiZ {
	mat4 view_proj;
	vec4 dims; // x = width, y = height, z = depth bias
	float depth[];
} hiz;

layout(push_constant, std430) uniform Params {
	uint instance_count;
	uint plane_count;
	uint use_hiz;
	uint pad;
} params;

bool occluded(vec3 c, vec3 h) {
	int wt = int(hiz.dims.x);
	int ht = int(hiz.dims.y);
	vec2 mn = vec2(1.0e9);
	vec2 mx = vec2(-1.0e9);
	float zmin = 1.0e9;
	for (uint k = 0u; k < 8u; k++) {
		vec3 corner = c + h * vec3(((k & 1u) != 0u) ? 1.0 : -1.0, ((k & 2u) != 0u) ? 1.0 : -1.0, ((k & 4u) != 0u) ? 1.0 : -1.0);
		vec4 clip = hiz.view_proj * vec4(corner, 1.0);
		if (clip.w <= 0.00001) {
			return false; // crosses the near plane: stay conservative
		}
		vec3 ndc = clip.xyz / clip.w;
		vec2 uv = ndc.xy * 0.5 + 0.5;
		mn = min(mn, uv);
		mx = max(mx, uv);
		zmin = min(zmin, ndc.z * 0.5 + 0.5);
	}
	if (mx.x < 0.0 || mx.y < 0.0 || mn.x > 1.0 || mn.y > 1.0) {
		return false; // off screen: frustum planes decide
	}
	int x0 = clamp(int(floor(mn.x * float(wt))), 0, wt - 1);
	int y0 = clamp(int(floor(mn.y * float(ht))), 0, ht - 1);
	int x1 = clamp(int(floor(mx.x * float(wt))), 0, wt - 1);
	int y1 = clamp(int(floor(mx.y * float(ht))), 0, ht - 1);
	float far_depth = 0.0;
	for (int y = y0; y <= y1; y++) {
		for (int x = x0; x <= x1; x++) {
			far_depth = max(far_depth, hiz.depth[y * wt + x]);
		}
	}
	return zmin > far_depth + hiz.dims.z;
}

void main() {
	uint i = gl_GlobalInvocationID.x;
	if (i >= params.instance_count) {
		return;
	}
	vec3 c = instances.items[i].center.xyz;
	vec3 h = instances.items[i].half_ext.xyz;
	for (uint k = 0u; k < params.plane_count; k++) {
		vec4 pl = planes.p[k];
		float d = dot(pl.xyz, c) - pl.w - dot(abs(pl.xyz), h);
		if (d > 0.0) {
			return;
		}
	}
	if (params.use_hiz != 0u && occluded(c, h)) {
		return;
	}
	uint slot = atomicAdd(visible.count, 1u);
	visible.indices[slot] = i;
}
