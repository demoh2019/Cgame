shader_type sky;
// Compatible with Godot 4 sky processors: sky() must not early-return.
// No TIME builtin: radiance is not needlessly rebuilt every rendered frame.

uniform vec3 zenith_color : source_color = vec3(0.035, 0.16, 0.36);
uniform vec3 horizon_color : source_color = vec3(0.60, 0.74, 0.90);
uniform vec3 cloud_color : source_color = vec3(0.93, 0.95, 1.0);
uniform float cloud_coverage : hint_range(0.15, 0.85) = 0.48;
uniform float cloud_opacity : hint_range(0.0, 1.0) = 0.6;
uniform float cloud_density : hint_range(0.5, 8.0) = 2.5;
uniform float cloud_time = 0.0;
uniform float sun_intensity : hint_range(0.0, 5.0) = 1.2;
uniform float night_amount : hint_range(0.0, 1.0) = 0.0;
uniform vec3 night_color : source_color = vec3(0.004, 0.009, 0.03);
uniform float stars_intensity : hint_range(0.0, 1.0) = 0.0;

float hash21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
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

float cloud_noise(vec2 p) {
	float n = value_noise(p) * 0.57;
	n += value_noise(p * 2.03) * 0.29;
	n += value_noise(p * 4.07) * 0.14;
	return n;
}

void sky() {
	vec3 dir = normalize(EYEDIR);
	if (AT_CUBEMAP_PASS) {
		float sky_amount = pow(clamp(max(dir.y, 0.0), 0.0, 1.0), 0.55);
		vec3 sky_color = mix(horizon_color, zenith_color, sky_amount);
		sky_color = mix(sky_color, night_color, night_amount * 0.50);

		if (dir.y > 0.025 && cloud_opacity > 0.001) {
			vec2 cloud_uv = dir.xz / max(dir.y + 0.28, 0.3);
			cloud_uv = cloud_uv * cloud_density + vec2(cloud_time, cloud_time * 0.4);
			float cloud = smoothstep(cloud_coverage - 0.08, cloud_coverage + 0.12, cloud_noise(cloud_uv));
			float fade = smoothstep(0.025, 0.16, dir.y);
			sky_color = mix(sky_color, cloud_color, cloud * cloud_opacity * fade);
		}

		if (LIGHT0_ENABLED) {
			float sun_dot = max(dot(dir, LIGHT0_DIRECTION), 0.0);
			float disk = pow(sun_dot, 1024.0);
			float glow = pow(sun_dot, 24.0) * 0.10;
			sky_color += LIGHT0_COLOR * LIGHT0_ENERGY * sun_intensity * (disk + glow);
		}
		if (night_amount > 0.01 && stars_intensity > 0.01 && dir.y > 0.10) {
			vec2 star_uv = dir.xz / max(dir.y + 0.4, 0.5);
			vec2 star_id = floor(star_uv * 310.0);
			float star = step(0.9985, hash21(star_id));
			sky_color += vec3(0.75, 0.85, 1.0) * star * night_amount * stars_intensity * 0.6;
		}
		COLOR = sky_color;
	} else {
		// Reuse the already-computed cubemap in the visible-sky pass.
		// Using RADIANCE during the cubemap pass would be invalid.
		COLOR = texture(RADIANCE, dir).rgb;
	}
}
