#[vertex]

#version 450

#VERSION_DEFINES

void main() {
	vec2 base_arr[3] = vec2[](vec2(-1.0, -1.0), vec2(-1.0, 3.0), vec2(3.0, -1.0));
	gl_Position = vec4(base_arr[gl_VertexIndex], 0.0, 1.0);
}

#[fragment]

#version 450

#VERSION_DEFINES

// Cgame foveated rendering: the opaque pass and the sky were drawn with a Metal rasterization rate map into
// smaller "physical" colour and depth targets. Each full-resolution pixel reads back its source through the
// map's exact per-column and per-row screen-to-physical mapping (the rates are separable per axis).

layout(set = 0, binding = 0) uniform sampler2D source_color;
layout(set = 0, binding = 1) uniform sampler2D source_depth;
layout(set = 0, binding = 2) uniform sampler2D mapping; // R32F: row 0 = physical x per screen column, row 1 = physical y per screen row.

layout(push_constant, std430) uniform Params {
	vec2 physical_size;
	vec2 pad;
}
params;

layout(location = 0) out vec4 frag_color;

void main() {
	ivec2 p = ivec2(gl_FragCoord.xy);
	vec2 physical = vec2(texelFetch(mapping, ivec2(p.x, 0), 0).r, texelFetch(mapping, ivec2(p.y, 1), 0).r);
	frag_color = textureLod(source_color, physical / params.physical_size, 0.0);
	gl_FragDepth = texelFetch(source_depth, clamp(ivec2(physical), ivec2(0), ivec2(params.physical_size) - 1), 0).r;
}
