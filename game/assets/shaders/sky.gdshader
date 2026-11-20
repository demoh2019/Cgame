shader_type sky;

// Day: the Poly Haven cloud panorama (CC0), slowly drifting. Dusk: warmed toward orange near the horizon. Storm: greyed and
// darkened. Night: deep blue with stars and the moon. The sun disc follows the first directional light.

uniform sampler2D day_panorama : source_color, filter_linear, repeat_enable;
uniform bool has_panorama = false;
uniform float daylight = 1.0;
uniform float dusk = 0.0;
uniform float storm = 0.0;
uniform vec3 night_top : source_color = vec3(0.01, 0.015, 0.05);
uniform vec3 night_horizon : source_color = vec3(0.04, 0.05, 0.11);
uniform vec3 day_top : source_color = vec3(0.2, 0.4, 0.78);
uniform vec3 day_horizon : source_color = vec3(0.66, 0.78, 0.9);
uniform vec3 dusk_color : source_color = vec3(1.0, 0.55, 0.28);
uniform vec3 storm_color : source_color = vec3(0.32, 0.35, 0.4);
uniform float drift = 0.004;
// Updated at a bounded cadence by Atmosphere; avoids forcing radiance rebuilds every frame.
uniform float sky_time = 0.0;
uniform vec3 sun_direction = vec3(0.0, 0.4, 0.9165);
uniform vec3 sun_color : source_color = vec3(1.0, 0.95, 0.82);

float hash(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

void sky() {
	vec3 dir = EYEDIR;
	float up = dir.y;
	// Below the horizon: a dark ground haze (the camera rarely sees it, the reflections do).
	vec3 gradient = mix(day_horizon, day_top, clamp(up * 1.6, 0.0, 1.0));
	vec3 day = gradient;
	if (has_panorama) {
		float u = atan(dir.x, -dir.z) / (2.0 * PI) + 0.5 + sky_time * drift * 0.01;
		float v = acos(clamp(dir.y, -1.0, 1.0)) / PI;
		day = texture(day_panorama, vec2(u, min(v, 0.499))).rgb * 1.08;
	}
	day = mix(day, day * 0.55 + dusk_color * 0.45, dusk * (1.0 - smoothstep(0.0, 0.5, up)));
	float grey = dot(day, vec3(0.3, 0.59, 0.11));
	day = mix(day, vec3(grey) * storm_color * 1.8, storm * 0.85);
	day *= 1.0 - storm * 0.35;

	vec3 night = mix(night_horizon, night_top, clamp(up * 1.4, 0.0, 1.0));
	// Stars: sparse bright cells above the horizon.
	vec3 cell = floor(dir * 220.0);
	float star = step(0.9965, hash(cell)) * smoothstep(0.02, 0.25, up);
	night += vec3(star) * (0.6 + 0.4 * sin(sky_time * 2.0 + hash(cell + 3.0) * 30.0)) * (1.0 - storm);

	vec3 color = mix(night, day, daylight);
	if (up < 0.0) {
		color = mix(color, color * 0.35, clamp(-up * 4.0, 0.0, 1.0));
	}
	// A cached light direction preserves the sun/moon disc without LIGHT0_* dependency.
	// The directional light itself still moves every frame, so gameplay shadows stay smooth.
	float facing = dot(dir, normalize(sun_direction));
	float disc = smoothstep(0.9993, 0.9997, facing);
	float glow = pow(max(facing, 0.0), 220.0) * 0.6 + pow(max(facing, 0.0), 14.0) * 0.12;
	float visible = 1.0 - storm * 0.85;
	color += sun_color * (disc * 2.5 + glow) * visible * mix(0.35, 1.0, daylight);
	// Single-scattering-inspired warm horizon halo reuses the existing glow term.
	// No additional noise lookups or texture taps on low-end hardware.
	float horizon_halo = 1.0 - smoothstep(0.04, 0.42, abs(up));
	color += vec3(0.9, 0.31, 0.10) * (glow * 0.38) * horizon_halo * dusk * visible;
	COLOR = color;
}
