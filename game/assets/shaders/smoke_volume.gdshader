// Ray-marched smoke / fire volume. Put on a unit BoxMesh (scaled by the node); density (R)
// and temperature (G) come from an RGF ImageTexture3D produced by SmokeSim.to_image3d().
// Technique: front-to-back emission-absorption ray marching (standard volume rendering,
// cf. GPU Gems 3 ch.30). Original shader, no third-party code.
shader_type spatial;
render_mode unshaded, cull_front, depth_draw_never, blend_mix;

uniform sampler3D volume_tex : filter_linear, repeat_disable;
uniform int steps : hint_range(8, 128) = 48;
uniform float density_scale = 6.0;
uniform float absorption = 1.0;
uniform float temperature_scale = 1.0;
uniform float emission_strength = 3.0;
uniform float fire_threshold = 0.15;
uniform vec4 smoke_color : source_color = vec4(0.18, 0.18, 0.2, 1.0);
uniform float light_wrap = 0.35;

varying vec3 v_local;
varying vec3 v_cam_local;

// Blackbody-ish ramp: black -> deep red -> orange -> yellow -> white.
vec3 fire_ramp(float t) {
	t = clamp(t, 0.0, 1.0);
	vec3 c = mix(vec3(0.0), vec3(0.8, 0.08, 0.0), smoothstep(0.0, 0.3, t));
	c = mix(c, vec3(1.0, 0.45, 0.05), smoothstep(0.25, 0.55, t));
	c = mix(c, vec3(1.0, 0.85, 0.3), smoothstep(0.5, 0.8, t));
	c = mix(c, vec3(1.0, 1.0, 0.9), smoothstep(0.8, 1.0, t));
	return c;
}

void vertex() {
	v_local = VERTEX;
	v_cam_local = (inverse(MODEL_MATRIX) * vec4(INV_VIEW_MATRIX[3].xyz, 1.0)).xyz;
}

void fragment() {
	vec3 ro = v_cam_local;
	vec3 rd = normalize(v_local - v_cam_local);
	vec3 inv = 1.0 / rd;
	vec3 t0 = (vec3(-0.5) - ro) * inv;
	vec3 t1 = (vec3(0.5) - ro) * inv;
	vec3 tmin = min(t0, t1);
	vec3 tmax = max(t0, t1);
	float t_near = max(max(tmin.x, tmin.y), max(tmin.z, 0.0));
	float t_far = min(min(tmax.x, tmax.y), tmax.z);
	vec3 col = vec3(0.0);
	float trans = 1.0;
	if (t_far > t_near) {
		float dt = (t_far - t_near) / float(steps);
		float t = t_near + 0.5 * dt;
		for (int i = 0; i < steps; i++) {
			vec3 p = ro + rd * t;
			vec4 s = texture(volume_tex, p + 0.5);
			float dens = max(s.r, 0.0) * density_scale;
			float temp = max(s.g, 0.0) * temperature_scale;
			float sigma = dens * absorption * dt;
			float a = 1.0 - exp(-sigma);
			float heat = smoothstep(fire_threshold, 1.0, temp);
			vec3 lit = smoke_color.rgb * (light_wrap + (1.0 - light_wrap) * clamp(0.5 + p.y, 0.0, 1.0));
			vec3 emit = fire_ramp(heat) * emission_strength * heat;
			col += trans * a * (lit + emit);
			trans *= 1.0 - a;
			if (trans < 0.01) {
				break;
			}
			t += dt;
		}
	}
	ALBEDO = col / max(1.0 - trans, 0.001);
	ALPHA = 1.0 - trans;
}
