shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back, diffuse_burley, specular_schlick_ggx;

// Open water: colour from the depth under the surface, a soft foam line along the shore, scrolling ripples
// and a Fresnel sheen that picks up the sky.
uniform sampler2D depth_tex : hint_depth_texture, repeat_disable, filter_nearest;
uniform vec3 shallow_color : source_color = vec3(0.16, 0.5, 0.52);
uniform vec3 deep_color : source_color = vec3(0.02, 0.15, 0.3);
uniform float clarity = 5.0;
uniform float ripple_strength = 0.35;

varying vec3 world_position;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float ripples(vec2 p, float t) {
	float h = value_noise(p * 0.45 + vec2(t * 0.06, t * 0.035)) * 0.55;
	h += value_noise(p * 1.1 + vec2(-t * 0.09, t * 0.07)) * 0.3;
	h += value_noise(p * 2.7 + vec2(t * 0.15, -t * 0.12)) * 0.15;
	return h;
}

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float t = TIME;
	vec2 p = world_position.xz;
	float e = 0.25;
	float h = ripples(p, t);
	float dx = ripples(p + vec2(e, 0.0), t) - h;
	float dz = ripples(p + vec2(0.0, e), t) - h;
	vec3 world_normal = normalize(vec3(-dx * ripple_strength / e, 1.0, -dz * ripple_strength / e));
	NORMAL = normalize((VIEW_MATRIX * vec4(world_normal, 0.0)).xyz);

	float depth = textureLod(depth_tex, SCREEN_UV, 0.0).r;
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, depth * 2.0 - 1.0);
#else
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, depth);
#endif
	vec4 scene = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	scene.xyz /= scene.w;
	float thickness = max(-scene.z + VERTEX.z, 0.0);

	float depth_mix = clamp(thickness / clarity, 0.0, 1.0);
	vec3 color = mix(shallow_color, deep_color, depth_mix);
	// Foam where the water gets thin, broken up by moving noise.
	float edge = 1.0 - smoothstep(0.0, 0.9, thickness);
	float foam_noise = value_noise(p * 3.2 + vec2(t * 0.2, -t * 0.15)) * 0.6 + value_noise(p * 7.0 - vec2(t * 0.3)) * 0.4;
	float foam = smoothstep(0.35, 0.75, foam_noise + edge * 0.9 - 0.55) * edge;
	color = mix(color, vec3(0.95, 0.98, 1.0), foam);

	float fresnel = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), 3.0);
	ALBEDO = color;
	ALPHA = clamp(mix(0.28, 0.93, smoothstep(0.0, 2.5, thickness)) + foam * 0.5 + fresnel * 0.25, 0.0, 1.0);
	ROUGHNESS = mix(0.06, 0.4, foam);
	SPECULAR = 0.7;
	METALLIC = 0.0;
	EMISSION = vec3(0.01, 0.04, 0.05) * (1.0 - depth_mix) + vec3(0.08, 0.12, 0.16) * fresnel;
}
