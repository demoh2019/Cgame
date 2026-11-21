shader_type spatial;
// Acid/poison puddle: the CC0 green liquid texture, slowly swirling, with a soft toxic glow,
// bubbling spots and a feathered edge so it soaks into the ground instead of being a disc.
render_mode blend_mix, depth_draw_never, cull_back, shadows_disabled;

uniform sampler2D liquid : source_color, filter_linear_mipmap, repeat_enable;
uniform vec4 tint : source_color = vec4(0.42, 0.62, 0.14, 1.0);
uniform float glow = 0.25;
uniform float radius = 2.4;

varying vec2 disc;

void vertex() {
	disc = VERTEX.xz / max(radius, 0.01); // -1..1 across the puddle, independent of mesh UVs.
}

float hash(vec2 p) { return fract(sin(dot(p, vec2(41.3, 289.1))) * 15731.743); }

void fragment() {
	vec2 centred = disc;
	float r = length(centred);
	vec2 uv = disc * 0.5 + 0.5;
	vec2 swirl = vec2(sin(TIME * 0.21 + r * 3.0), cos(TIME * 0.17 + r * 2.0)) * 0.03;
	vec3 a = texture(liquid, uv * 1.6 + swirl + vec2(TIME * 0.01, 0.0)).rgb;
	vec3 b = texture(liquid, uv * 2.3 - swirl.yx + vec2(0.0, TIME * 0.013)).rgb;
	vec3 col = mix(a, b, 0.5) * tint.rgb * 1.4;
	// Bubbles pop in random cells.
	vec2 cell = floor(uv * 14.0);
	float phase = fract(TIME * 0.6 + hash(cell));
	vec2 jitter = vec2(hash(cell + 3.1), hash(cell + 7.7)) * 0.5 - 0.25;
	float alive = step(0.82, hash(cell + floor(TIME * 0.6 + hash(cell)))); // Few cells bubble at a time.
	float bubble = alive * smoothstep(0.22, 0.0, length(fract(uv * 14.0) - 0.5 - jitter)) * smoothstep(0.0, 0.2, phase) * (1.0 - phase);
	col += vec3(0.55, 1.0, 0.25) * bubble * 0.5;
	ALBEDO = col;
	EMISSION = col * glow;
	ROUGHNESS = 0.08;
	SPECULAR = 0.8;
	ALPHA = clamp((1.0 - smoothstep(0.7, 1.0, r + (hash(floor(uv * 40.0)) - 0.5) * 0.08)) * 0.85, 0.0, 1.0);
}
