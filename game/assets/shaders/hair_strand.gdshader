// Strand hair: Kajiya-Kay dual shifted specular (Marschner-lite R + TRT lobes).
// Kajiya & Kay, "Rendering Fur with Three Dimensional Textures", SIGGRAPH 1989;
// shifted highlights per Scheuermann, "Hair Rendering and Shading", GDC 2004 (concepts only).
// Original shader written for this project; no third-party code.
// Mesh contract (hair_strands.gd build_mesh): NORMAL = strand tangent, UV = (side, t),
// COLOR = (half width, per-strand random, t, 1). Ribbons are expanded toward the camera here.
shader_type spatial;
render_mode cull_disabled, depth_draw_opaque;

uniform vec4 base_color : source_color = vec4(0.22, 0.13, 0.07, 1.0);
uniform vec4 tip_color : source_color = vec4(0.42, 0.28, 0.15, 1.0);
uniform float gradient_power : hint_range(0.2, 4.0) = 1.2;
uniform float root_darken : hint_range(0.0, 1.0) = 0.55;
uniform vec4 spec_color_primary : source_color = vec4(1.0, 0.97, 0.92, 1.0);
uniform vec4 spec_color_secondary : source_color = vec4(0.9, 0.55, 0.3, 1.0);
uniform float shift_primary : hint_range(-1.0, 1.0) = -0.08;
uniform float shift_secondary : hint_range(-1.0, 1.0) = 0.22;
uniform float shift_noise : hint_range(0.0, 1.0) = 0.15;
uniform float exp_primary : hint_range(1.0, 512.0) = 90.0;
uniform float exp_secondary : hint_range(1.0, 512.0) = 28.0;
uniform float spec_strength : hint_range(0.0, 4.0) = 0.8;
uniform float tip_thin_start : hint_range(0.0, 1.0) = 0.6;
uniform float alpha_scissor : hint_range(0.0, 1.0) = 0.5;
uniform float tip_width_scale : hint_range(0.0, 1.0) = 0.35;

varying vec3 v_tan;
varying vec2 v_info;

void vertex() {
	float side = UV.x * 2.0 - 1.0;
	float t = UV.y;
	float half_w = COLOR.r * mix(1.0, tip_width_scale, t);
	vec3 vpos = (MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 tv = normalize((MODELVIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vec3 side_v = cross(tv, normalize(vpos));
	float sl = length(side_v);
	side_v = sl > 0.0001 ? side_v / sl : vec3(1.0, 0.0, 0.0);
	VERTEX += (inverse(MODELVIEW_MATRIX) * vec4(side_v * side * half_w, 0.0)).xyz;
	v_tan = tv;
	v_info = vec2(t, COLOR.g);
}

void fragment() {
	float t = v_info.x;
	vec3 T = normalize(v_tan);
	// Cylinder-ish normal facing the viewer, perpendicular to the strand.
	vec3 n = VIEW - T * dot(VIEW, T);
	NORMAL = length(n) > 0.0001 ? normalize(n) : vec3(0.0, 0.0, 1.0);
	float grad = pow(clamp(t, 0.0, 1.0), gradient_power);
	ALBEDO = mix(base_color.rgb, tip_color.rgb, grad) * mix(root_darken, 1.0, smoothstep(0.0, 0.25, t));
	ROUGHNESS = 1.0;
	// Alpha-scissor thinning: each strand ends at its own random length near the tip.
	float life = mix(tip_thin_start, 1.0, v_info.y);
	float edge = 1.0 - abs(UV.x * 2.0 - 1.0);
	ALPHA = (1.0 - smoothstep(life - 0.12, life, t)) * smoothstep(0.0, 0.3, edge + 0.15);
	ALPHA_SCISSOR_THRESHOLD = alpha_scissor;
}

void light() {
	vec3 T = normalize(v_tan);
	vec3 N = NORMAL;
	vec3 L = normalize(LIGHT);
	vec3 H = normalize(L + VIEW);
	float jitter = (v_info.y - 0.5) * shift_noise;
	vec3 t1 = normalize(T + N * (shift_primary + jitter));
	vec3 t2 = normalize(T + N * (shift_secondary + jitter));
	float d1 = dot(t1, H);
	float d2 = dot(t2, H);
	float s1 = pow(sqrt(max(1.0 - d1 * d1, 0.0)), exp_primary);
	float s2 = pow(sqrt(max(1.0 - d2 * d2, 0.0)), exp_secondary);
	float dir_atten = smoothstep(-1.0, 0.0, dot(T, H));
	float tl = dot(T, L);
	float diff = sqrt(max(1.0 - tl * tl, 0.0));
	DIFFUSE_LIGHT += ATTENUATION * LIGHT_COLOR * diff;
	vec3 spec = spec_color_primary.rgb * s1 + spec_color_secondary.rgb * ALBEDO * s2 * 2.0;
	SPECULAR_LIGHT += ATTENUATION * LIGHT_COLOR * spec * dir_atten * spec_strength * max(dot(N, L) + 0.35, 0.0);
}
