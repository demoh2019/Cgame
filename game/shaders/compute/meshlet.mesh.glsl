#[mesh]
#version 450
#extension GL_EXT_mesh_shader : require

// Meshlet mesh stage: one work group per visible meshlet (selected by meshlet.task.glsl).
// The group transforms the meshlet's vertices and emits its triangles straight to the rasterizer.
//
// Original implementation (project license). Meshlet layout concepts follow meshoptimizer
// (Arseny Kapoulkine, MIT): a per-meshlet vertex list indexing the global vertex array plus
// compact local triangle indices (here one uint per triangle: a | b << 8 | c << 16).
// Mesh stage structure follows the Khronos GL_EXT_mesh_shader specification examples.
//
// Output limits: 64 vertices / 124 triangles (RenderingDevice meshlet convention, see
// MeshletRenderer.MAX_MESHLET_VERTICES / MAX_MESHLET_TRIANGLES).

layout(local_size_x = 32, local_size_y = 1, local_size_z = 1) in;
layout(triangles, max_vertices = 64, max_primitives = 124) out;

struct Meshlet {
	uvec4 counts; // vertex_offset, triangle_offset, vertex_count, triangle_count
	vec4 sphere;
	vec4 cone;
};

layout(set = 0, binding = 0, std430) restrict readonly buffer Positions {
	vec4 data[];
}
positions;

layout(set = 0, binding = 1, std430) restrict readonly buffer MeshletVertices {
	uint data[];
}
meshlet_vertices;

layout(set = 0, binding = 2, std430) restrict readonly buffer MeshletTriangles {
	uint data[];
}
meshlet_triangles;

layout(set = 0, binding = 3, std430) restrict readonly buffer Meshlets {
	Meshlet items[];
}
meshlets;

layout(set = 0, binding = 4, std140) uniform Frame {
	mat4 view_proj;
	mat4 model;
	vec4 planes[6];
	vec4 camera_pos;
	uvec4 params;
}
frame;

struct TaskPayload {
	uint ids[32];
};

taskPayloadSharedEXT TaskPayload payload;

layout(location = 0) out vec3 v_world[];
layout(location = 1) perprimitiveEXT flat out uint v_meshlet[];

void main() {
	uint meshlet_id = payload.ids[gl_WorkGroupID.x];
	Meshlet m = meshlets.items[meshlet_id];
	uint vertex_count = m.counts.z;
	uint triangle_count = m.counts.w;

	SetMeshOutputsEXT(vertex_count, triangle_count);

	for (uint i = gl_LocalInvocationIndex; i < vertex_count; i += 32u) {
		uint vertex_id = meshlet_vertices.data[m.counts.x + i];
		vec4 world = frame.model * vec4(positions.data[vertex_id].xyz, 1.0);
		gl_MeshVerticesEXT[i].gl_Position = frame.view_proj * world;
		v_world[i] = world.xyz;
	}

	for (uint t = gl_LocalInvocationIndex; t < triangle_count; t += 32u) {
		uint packed_tri = meshlet_triangles.data[m.counts.y + t];
		gl_PrimitiveTriangleIndicesEXT[t] = uvec3(packed_tri & 0xFFu, (packed_tri >> 8u) & 0xFFu, (packed_tri >> 16u) & 0xFFu);
		v_meshlet[t] = meshlet_id;
	}
}

#[fragment]
#version 450
#extension GL_EXT_mesh_shader : require

// Debug-friendly shading: flat normal from screen-space derivatives, tinted per meshlet id.

layout(location = 0) in vec3 v_world;
layout(location = 1) perprimitiveEXT flat in uint v_meshlet;

layout(location = 0) out vec4 frag_color;

vec3 meshlet_tint(uint id) {
	uint h = id * 2654435761u;
	return vec3(float((h >> 16u) & 0xFFu), float((h >> 8u) & 0xFFu), float(h & 0xFFu)) / 255.0 * 0.6 + 0.4;
}

void main() {
	vec3 n = normalize(cross(dFdx(v_world), dFdy(v_world)));
	float lambert = clamp(dot(n, normalize(vec3(0.4, 0.8, 0.5))) * 0.5 + 0.5, 0.0, 1.0);
	frag_color = vec4(meshlet_tint(v_meshlet) * lambert, 1.0);
}
