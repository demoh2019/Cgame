shader_type spatial;
render_mode blend_mix, cull_disabled, depth_draw_opaque;

uniform vec4 wave_0 = vec4(1.0, 0.0, 0.35, 14.0);
uniform vec4 wave_1 = vec4(0.6, 0.8, 0.14, 8.0);
uniform vec4 wave_2 = vec4(-0.98, 0.196, 0.07, 4.0);
uniform vec4 wave_3 = vec4(1.0, 0.0, 0.0, 1.0);
uniform vec2 motion_0 = vec2(1.1, 0.0);
uniform vec2 motion_1 = vec2(1.6, 1.0);
uniform vec2 motion_2 = vec2(2.0, 2.0);
uniform vec2 motion_3 = vec2(0.0, 0.0);

uniform float water_time = 0.0;
uniform vec4 water_tint : source_color = vec4(0.07, 0.35, 0.48, 1.0);
uniform float water_opacity : hint_range(0.0, 1.0) = 0.85;

const float TAU_VALUE = 6.283185307179586;

vec3 wave_sample(vec2 world_xz, vec4 params, vec2 motion) {
	vec2 direction = normalize(params.xy);
	float k = TAU_VALUE / max(params.w, 0.01);
	float angle = k * dot(direction, world_xz) + motion.y - motion.x * water_time;
	float height = params.z * sin(angle);
	float slope = params.z * k * cos(angle);
	return vec3(height, slope * direction.x, slope * direction.y);
}

vec3 combined_wave(vec2 world_xz) {
	return wave_sample(world_xz, wave_0, motion_0)
		+ wave_sample(world_xz, wave_1, motion_1)
		+ wave_sample(world_xz, wave_2, motion_2)
		+ wave_sample(world_xz, wave_3, motion_3);
}

void vertex() {
	vec2 world_xz = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
	vec3 wave = combined_wave(world_xz);
	VERTEX.y += wave.x;
	NORMAL = normalize(vec3(-wave.y, 1.0, -wave.z));
}

void fragment() {
	ALBEDO = water_tint.rgb;
	ROUGHNESS = 0.18;
	METALLIC = 0.05;
	SPECULAR = 0.85;
	ALPHA = water_opacity;
}
