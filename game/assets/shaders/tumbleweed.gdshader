shader_type spatial;
// Tangled dry-brush ball: 3D noise threshold carves a sparse twig lattice out of a
// sphere (alpha scissor), so a single low-poly sphere reads as a tumbleweed.
render_mode cull_disabled;

uniform vec3 twig_color : source_color = vec3(0.55, 0.45, 0.3);

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

varying vec3 obj_pos;

void vertex() {
	obj_pos = VERTEX;
}

void fragment() {
	float twigs = abs(n3(obj_pos * 9.0) - 0.5) * 2.0;
	ALPHA = 1.0 - smoothstep(0.0, 0.14, twigs);
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	ALBEDO = twig_color * (0.75 + 0.25 * n3(obj_pos * 30.0));
	ROUGHNESS = 0.95;
}
