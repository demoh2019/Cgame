#[task]
#version 450
#extension GL_EXT_mesh_shader : require

// Meshlet task (amplification) stage: one thread per meshlet culls it against the frustum
// and its normal cone, compacts the survivors into the task payload and launches exactly
// that many mesh work groups (one per visible meshlet).
//
// Original implementation (project license). Techniques (ideas only, no code copied):
//   - meshoptimizer (Arseny Kapoulkine, MIT): meshlet bounds and the normal-cone test
//     dot(center - cam, axis) >= cutoff * |center - cam| + radius.
//   - Khronos GL_EXT_mesh_shader / VK_EXT_mesh_shader specification (task payload, EmitMeshTasksEXT).
//   - NVIDIA "Introduction to Turing Mesh Shaders" (public blog) for the task-stage culling pattern.
//
// Conventions mirror game/scripts/client/meshlet_renderer.gd (CPU reference implementation):
//   planes are outward-facing (Camera3D.get_frustum()): inside <=> dot(n, x) - d <= 0.
//   Meshlet descriptor: counts = (vertex_offset, triangle_offset, vertex_count, triangle_count),
//   sphere = (center.xyz, radius), cone = (axis.xyz, cutoff) in model space.
//   Requires VK_EXT_mesh_shader (RenderingDevice.SUPPORTS_MESH_SHADER).

#define TASK_GROUP_SIZE 32u

layout(local_size_x = 32, local_size_y = 1, local_size_z = 1) in;

struct Meshlet {
	uvec4 counts;
	vec4 sphere;
	vec4 cone;
};

layout(set = 0, binding = 3, std430) restrict readonly buffer Meshlets {
	Meshlet items[];
}
meshlets;

layout(set = 0, binding = 4, std140) uniform Frame {
	mat4 view_proj;
	mat4 model;
	vec4 planes[6];
	vec4 camera_pos;
	uvec4 params; // x = meshlet count, y = flags (1 = frustum cull, 2 = cone cull).
}
frame;

struct TaskPayload {
	uint ids[32];
};

taskPayloadSharedEXT TaskPayload payload;

shared uint visible_count;

bool meshlet_visible(Meshlet m) {
	// Empty slots start with zeroed descriptors; evicted pages are overwritten
	// before the next draw. Never emit a mesh workgroup for an empty slot.
	if (m.counts.z == 0u || m.counts.w == 0u) {
		return false;
	}
	float scale = length(frame.model[0].xyz);
	vec3 center = (frame.model * vec4(m.sphere.xyz, 1.0)).xyz;
	float radius = m.sphere.w * scale;

	if ((frame.params.y & 1u) != 0u) {
		for (int i = 0; i < 6; i++) {
			if (dot(frame.planes[i].xyz, center) - frame.planes[i].w > radius) {
				return false;
			}
		}
	}

	if ((frame.params.y & 2u) != 0u && m.cone.w < 1.0) {
		vec3 axis = normalize(mat3(frame.model) * m.cone.xyz);
		vec3 to_center = center - frame.camera_pos.xyz;
		if (dot(to_center, axis) >= m.cone.w * length(to_center) + radius) {
			return false;
		}
	}
	return true;
}

void main() {
	if (gl_LocalInvocationIndex == 0u) {
		visible_count = 0u;
	}
	memoryBarrierShared();
	barrier();

	uint id = gl_GlobalInvocationID.x;
	if (id < frame.params.x && meshlet_visible(meshlets.items[id])) {
		uint slot = atomicAdd(visible_count, 1u);
		payload.ids[slot] = id;
	}

	memoryBarrierShared();
	barrier();

	// Must be called by every invocation of the group with the same arguments.
	EmitMeshTasksEXT(visible_count, 1u, 1u);
}
