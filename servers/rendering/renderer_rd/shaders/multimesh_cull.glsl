#[compute]

#version 450

#VERSION_DEFINES

// Cgame: GPU per-instance culling for MultiMesh (Forward+).
// One thread per instance: the instance's bounding sphere (mesh AABB centre and half-diagonal, scaled by the
// instance's largest basis column) is tested against the view frustum and the maximum draw distance, all in the
// MultiMesh's local space. Survivors are packed into a second instance buffer with an atomic counter, which is
// also the instance count of the indirect draw, so the CPU never reads anything back.

layout(local_size_x = 64, local_size_y = 1, local_size_z = 1) in;

layout(set = 0, binding = 0, std430) buffer restrict readonly SrcInstances {
	float data[];
}
src_instances;

layout(set = 0, binding = 1, std430) buffer restrict writeonly DstInstances {
	float data[];
}
dst_instances;

layout(set = 0, binding = 2, std430) buffer restrict Commands {
	uint data[];
}
commands;

layout(push_constant, std430) uniform Params {
	vec4 planes[5]; // Near and side planes in local space, normalized; distance > w means outside.
	vec4 eye_and_distance; // Local camera position, maximum distance (0 = unlimited) in local units.
	vec4 aabb_center_radius; // Mesh AABB centre and half-diagonal.
	uint instance_count;
	uint stride_and_surfaces; // Floats per instance (bits 0-7), surface count (8-15), min density (16-23), density start (24-31).
	uint current_offset; // Instance offsets of the current and previous halves (motion vectors).
	uint previous_offset;
}
params;

#define COMMAND_STRIDE 5u

// Stable per-instance random number in [0, 1) (PCG hash of the source index).
float instance_hash(uint index) {
	uint state = index * 747796405u + 2891336453u;
	uint word = ((state >> ((state >> 28u) + 4u)) ^ state) * 277803737u;
	return float((word >> 22u) ^ word) * (1.0 / 4294967296.0);
}

// Copies one instance, scaling its basis (not its origin) by `scale`.
void copy_instance(uint src, uint dst, uint stride, float scale) {
	for (uint f = 0u; f < stride; f++) {
		float value = src_instances.data[src + f];
		if (f < 12u && (f & 3u) != 3u) {
			value *= scale;
		}
		dst_instances.data[dst + f] = value;
	}
}

void main() {
	uint index = gl_GlobalInvocationID.x;
	if (index >= params.instance_count) {
		return;
	}

	uint stride = params.stride_and_surfaces & 0xFFu;
	uint surfaces = (params.stride_and_surfaces >> 8u) & 0xFFu;
	uint base = (params.current_offset + index) * stride;

	// Rows of the 3x4 transform: basis row in xyz, origin component in w.
	vec4 r0 = vec4(src_instances.data[base + 0u], src_instances.data[base + 1u], src_instances.data[base + 2u], src_instances.data[base + 3u]);
	vec4 r1 = vec4(src_instances.data[base + 4u], src_instances.data[base + 5u], src_instances.data[base + 6u], src_instances.data[base + 7u]);
	vec4 r2 = vec4(src_instances.data[base + 8u], src_instances.data[base + 9u], src_instances.data[base + 10u], src_instances.data[base + 11u]);

	vec3 c = params.aabb_center_radius.xyz;
	vec3 center = vec3(dot(r0.xyz, c) + r0.w, dot(r1.xyz, c) + r1.w, dot(r2.xyz, c) + r2.w);
	vec3 col0 = vec3(r0.x, r1.x, r2.x);
	vec3 col1 = vec3(r0.y, r1.y, r2.y);
	vec3 col2 = vec3(r0.z, r1.z, r2.z);
	float scale_sq = max(dot(col0, col0), max(dot(col1, col1), dot(col2, col2)));
	if (scale_sq < 1e-12) {
		return; // Collapsed instances (hidden by zero scale) are never drawn.
	}
	float radius = params.aabb_center_radius.w * sqrt(scale_sq);
	uint density_byte = (params.stride_and_surfaces >> 16u) & 0xFFu;
	if (density_byte < 255u) {
		radius *= inversesqrt(max(float(density_byte) / 255.0, 1e-3)); // Survivors may grow; never clip them at the screen edge.
	}

	for (uint i = 0u; i < 5u; i++) {
		if (dot(params.planes[i].xyz, center) - params.planes[i].w > radius) {
			return;
		}
	}
	float max_distance = params.eye_and_distance.w;
	float eye_distance = distance(center, params.eye_and_distance.xyz);
	if (max_distance > 0.0 && eye_distance - radius > max_distance) {
		return;
	}

	// Density LOD: past the start distance fewer instances are kept (down to min_density at max_distance), and
	// survivors grow by 1/sqrt(kept) so the covered area stays the same, the "wider but fewer" idea from
	// Ghost of Tsushima's grass. Each instance has a fixed hash, so the same ones go first; one about to
	// drop out shrinks to nothing over a short band instead of popping.
	float scale = 1.0;
	uint min_density_byte = (params.stride_and_surfaces >> 16u) & 0xFFu;
	if (max_distance > 0.0 && min_density_byte < 255u) {
		float min_density = float(min_density_byte) / 255.0;
		float start = float(params.stride_and_surfaces >> 24u) / 255.0;
		float t = clamp((eye_distance / max_distance - start) / max(1.0 - start, 1e-4), 0.0, 1.0);
		// The threshold starts one fade band above 1 so nothing shrinks before thinning begins.
		const float band = 0.06;
		float threshold = mix(1.0 + band, min_density, t);
		float h = instance_hash(index);
		if (h >= threshold) {
			return;
		}
		float kept = clamp(threshold - 0.5 * band, max(min_density, 1e-3), 1.0);
		scale = inversesqrt(kept) * clamp((threshold - h) / band, 0.0, 1.0);
		if (scale <= 0.0) {
			return;
		}
	}

	uint slot = atomicAdd(commands.data[1], 1u);
	// Every surface draws the same packed instances; the final count is the largest slot + 1.
	for (uint s = 1u; s < surfaces; s++) {
		atomicMax(commands.data[s * COMMAND_STRIDE + 1u], slot + 1u);
	}

	copy_instance(base, (params.current_offset + slot) * stride, stride, scale);
	if (params.previous_offset != params.current_offset) {
		copy_instance((params.previous_offset + index) * stride, (params.previous_offset + slot) * stride, stride, scale);
	}
}
