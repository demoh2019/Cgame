shader_type spatial;
// Corpse burn-away (Diablo / Destiny dissolve feel) as an overlay pass: a noise
// front chars the body to black while an HDR ember rim glows along the front.
// `progress` 0..1 is driven by the client while the corpse sinks.
render_mode unshaded, depth_draw_never, cull_back, shadows_disabled, fog_disabled;

uniform float progress = 0.0;

varying vec3 obj_pos;

float h3(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float n3(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(h3(i), h3(i + vec3(1, 0, 0)), f.x), mix(h3(i + vec3(0, 1, 0)), h3(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(h3(i + vec3(0, 0, 1)), h3(i + vec3(1, 0, 1)), f.x), mix(h3(i + vec3(0, 1, 1)), h3(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

void vertex() {
	obj_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float n = n3(obj_pos * 3.5) * 0.65 + n3(obj_pos * 9.0) * 0.35;
	float front = progress * 1.25 - 0.1;
	float charred = 1.0 - smoothstep(front - 0.02, front, n);
	float rim = smoothstep(front - 0.12, front - 0.02, n) * (1.0 - smoothstep(front - 0.02, front + 0.02, n));
	vec3 ember = mix(vec3(1.0, 0.35, 0.05), vec3(1.0, 0.8, 0.3), rim) * 4.0;
	ALBEDO = mix(vec3(0.02, 0.015, 0.01), ember, rim);
	ALPHA = clamp(max(charred * 0.92, rim), 0.0, 1.0);
}
