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
// Advect the daytime panorama using the same wind integration as ground cloud shadows.
// Updated only alongside the cached sky radiance: no realtime cubemap rebuilds.
uniform float cloud_wind_rotation = 0.0;
// Updated at a bounded cadence by Atmosphere; avoids forcing radiance rebuilds every frame.
uniform float sky_time = 0.0;
uniform vec3 sun_direction = vec3(0.0, 0.4, 0.9165);
uniform vec3 sun_color : source_color = vec3(1.0, 0.95, 0.82);
// Performance/Balanced reuse the radiance cubemap as the background.
// Cubemap rendering always evaluates the full sky to avoid feedback loops.
uniform bool use_cached_radiance = false;
// Natural sunlight scattering in thin atmospheric dust; no extra textures.
uniform float aerosol_scattering_strength = 0.0;
// The native engine generates one 128x64 RGBAH optical-depth LUT on demand.
// X: view elevation [-0.08,1], Y: solar elevation [-0.15,1].
// RGB: linear spectral in-scattering, A: medium transmittance.
uniform sampler2D atmospheric_lut : filter_linear, repeat_disable;
uniform bool has_atmospheric_lut = false;
uniform float atmospheric_lut_strength = 0.0;
uniform float solar_elevation = 0.7;
// Moon phases reuse the existing night directional light and sky cubemap.
uniform float moon_phase = 0.5;
uniform float moon_detail_strength = 0.0;
// Reuse the existing 128x128 R8 wind-cloud LUT as a wispy upper sky layer.
// High/Ultra sample at most two texels; Performance never samples it.
uniform sampler2D cirrus_lut : filter_linear, repeat_enable;
uniform vec2 cirrus_wind_offset = vec2(0.0);
uniform int cirrus_detail = 0;
uniform float cirrus_opacity = 0.0;
// Native cloud LUT: R density, G/B horizontal slopes, A soft self-shadow.
// Prebaked once from the SAME field as moving ground cloud shadows.
uniform sampler2D cloud_lighting_lut : filter_linear, repeat_enable;
uniform bool has_cloud_lighting_lut = false;
uniform float cloud_lighting_strength = 0.0;
// Raymarched cumulus layer (Unreal Volumetric Clouds / Nubis-style). 0 steps = off.
uniform int volumetric_cloud_steps = 0;
uniform float volumetric_cloud_coverage = 0.45;

float hash(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float vnoise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i), hash(i + vec3(1, 0, 0)), f.x),
			mix(hash(i + vec3(0, 1, 0)), hash(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash(i + vec3(0, 0, 1)), hash(i + vec3(1, 0, 1)), f.x),
			mix(hash(i + vec3(0, 1, 1)), hash(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

// Cumulus density in a unit slab (h: 0 bottom .. 1 top). Rounded bottoms, wispy tops.
float cloud_density(vec3 p, float h, float coverage) {
	float base = vnoise(p) * 0.55 + vnoise(p * 2.03 + 3.1) * 0.28 + vnoise(p * 4.1 + 7.7) * 0.17;
	float profile = smoothstep(0.0, 0.18, h) * (1.0 - smoothstep(0.45, 1.0, h));
	float d = clamp((base - (1.0 - coverage)) / max(coverage, 0.05), 0.0, 1.0) * profile;
	// Erode edges with high-frequency detail (HZD "detail noise").
	d -= vnoise(p * 9.0 + 1.3) * 0.18 * (1.0 - d);
	return max(d, 0.0);
}

float hg_phase(float c, float g) {
	float g2 = g * g;
	return (1.0 - g2) / (4.0 * PI * pow(1.0 + g2 - 2.0 * g * c, 1.5));
}

void sky() {
	vec3 dir = EYEDIR;
	// Godot's documented sky background fast path: reuse cached sky lighting.
	// Preserve high-resolution panorama and pinpoint stars on High/Ultra.
	if (use_cached_radiance && !AT_CUBEMAP_PASS) {
		COLOR = texture(RADIANCE, dir).rgb;
	} else {
		float up = dir.y;
		// Below the horizon: a dark ground haze (the camera rarely sees it, the reflections do).
		vec3 gradient = mix(day_horizon, day_top, clamp(up * 1.6, 0.0, 1.0));
		vec3 day = gradient;
		// Full-screen night pixels never sample the daytime panorama or evaluate
		// spherical UV atan/acos; the discarded contribution is below 0.5%.
		if (has_panorama && daylight > 0.005) {
			float u = atan(dir.x, -dir.z) / (2.0 * PI) + 0.5 + cloud_wind_rotation;
			float v = acos(clamp(dir.y, -1.0, 1.0)) / PI;
			day = texture(day_panorama, vec2(u, min(v, 0.499))).rgb * 1.08;
		}
		day = mix(day, day * 0.55 + dusk_color * 0.45, dusk * (1.0 - smoothstep(0.0, 0.5, up)));
		float grey = dot(day, vec3(0.3, 0.59, 0.11));
		day = mix(day, vec3(grey) * storm_color * 1.8, storm * 0.85);
		day *= 1.0 - storm * 0.35;
		// HDRP/Unreal-style baked optical depth: one bilinear lookup rather
		// than expensive atmosphere raymarches at every sky pixel.
		// A cubemap rebuild evaluates the same branch for coherent reflections.
		if (has_atmospheric_lut && atmospheric_lut_strength > 0.001 && daylight > 0.025 && up > -0.08) {
			vec2 optical_uv = vec2(
				clamp((up + 0.08) / 1.08, 0.0, 1.0),
				clamp((solar_elevation + 0.15) / 1.15, 0.0, 1.0));
			vec4 optical = texture(atmospheric_lut, optical_uv);
			float optical_weight = atmospheric_lut_strength * (1.0 - storm * 0.88);
			day = mix(day, day * optical.a + optical.rgb, optical_weight);
		}

		vec3 night = mix(night_horizon, night_top, clamp(up * 1.4, 0.0, 1.0));
		// A few hundred tiny point stars, distributed on stable spherical UVs.
		// Evaluate hash/twinkle ONLY in darkness; use derivatives to anti-alias
		// the circular core instead of flashing entire pixel-sized square cells.
		if (daylight < 0.95 && up > 0.02 && storm < 0.98) {
			vec2 star_uv = SKY_COORDS * vec2(480.0, 240.0);
			vec2 star_cell = floor(star_uv);
			float pick = hash(vec3(star_cell, 7.0));
			// Evaluate derivatives before the non-uniform star selection branch.
			float footprint = clamp(length(fwidth(star_uv)) * 0.38, 0.02, 0.50);
			if (pick > 0.9975) {
				vec2 shift = vec2(hash(vec3(star_cell, 13.0)),
					hash(vec3(star_cell, 29.0))) * 0.5 - 0.25;
				vec2 within_cell = fract(star_uv) - 0.5 - shift;
				float radius = mix(0.065, 0.18, hash(vec3(star_cell, 41.0)));
				float point_star = 1.0 - smoothstep(radius,
					radius + footprint, length(within_cell));
				float twinkle = 0.85 + 0.15 * sin(
					sky_time * 0.6 + hash(vec3(star_cell, 53.0)) * 23.0);
				float strength = point_star * twinkle *
					(1.0 - smoothstep(0.04, 0.58, daylight)) *
					smoothstep(0.02, 0.25, up) * (1.0 - storm);
				vec3 tint = mix(vec3(0.74, 0.83, 1.0),
					vec3(1.0, 0.88, 0.73), hash(vec3(star_cell, 61.0)));
				night += tint * strength * 1.4;
			}
		}

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
		// Dawn transitions from the lunar body into the sun: never paint the
		// same hot solar disc at night as though it were a full white moon.
		float day_disc = smoothstep(0.04, 0.20, daylight);
		color += sun_color * (disc * 2.5 + glow) * visible * day_disc;

		// Physically-inspired lunar phase without a texture/mesh/second light.
		// Only execute the expensive surface detail inside a tiny cone around
		// the night directional light; the entire rest of the sky skips it.
		if (daylight < 0.20 && facing > 0.9992 && up > 0.0) {
			vec3 lunar_direction = normalize(sun_direction);
			vec3 stable_up = abs(lunar_direction.y) > 0.96
				? vec3(1.0, 0.0, 0.0) : vec3(0.0, 1.0, 0.0);
			vec3 lunar_right = normalize(cross(stable_up, lunar_direction));
			vec3 lunar_up = normalize(cross(lunar_direction, lunar_right));
			vec2 lunar_uv = vec2(dot(dir, lunar_right), dot(dir, lunar_up)) / 0.012;
			float lunar_radius = length(lunar_uv);
			float pixel_width = clamp(length(fwidth(lunar_uv)) * 0.40, 0.012, 0.22);
			float lunar_disc = 1.0 - smoothstep(1.0 - pixel_width,
				1.0 + pixel_width, lunar_radius);
			float angle = fract(moon_phase) * 2.0 * PI;
			float terminator = cos(angle) * sqrt(max(1.0 - lunar_uv.y * lunar_uv.y, 0.0));
			float side = moon_phase < 0.5 ? 1.0 : -1.0;
			float lunar_light = smoothstep(-pixel_width, pixel_width,
				side * lunar_uv.x - terminator);
			float illuminated = 0.5 - 0.5 * cos(angle);
			float crater_shading = 1.0;
			if (moon_detail_strength > 0.001 && lunar_disc > 0.001) {
				// Three broad maria, evaluated only on the moon disc. Soft craters
				// preserve silhouette at zoom without requiring imported art.
				vec2 crater_a = lunar_uv - vec2(-0.32, 0.24);
				vec2 crater_b = lunar_uv - vec2(0.24, -0.31);
				vec2 crater_c = lunar_uv - vec2(0.39, 0.27);
				float maria = exp(-8.0 * dot(crater_a, crater_a)) * 0.21
					+ exp(-13.0 * dot(crater_b, crater_b)) * 0.18
					+ exp(-17.0 * dot(crater_c, crater_c)) * 0.12;
				crater_shading -= maria * moon_detail_strength;
			}
			float lunar_visibility = (1.0 - day_disc) * (1.0 - storm * 0.85);
			vec3 earthshine = vec3(0.04, 0.06, 0.12) * lunar_disc
				* (1.0 - lunar_light) * (1.0 - illuminated * 0.7);
			vec3 moon_surface = vec3(0.70, 0.77, 0.91) * lunar_disc
				* lunar_light * crater_shading * 1.85;
			float lunar_halo = pow(max(facing, 0.0), 1450.0)
				* (0.04 + illuminated * 0.12);
			color += (earthshine + moon_surface + vec3(0.30, 0.39, 0.61) * lunar_halo)
				* lunar_visibility;
		}
		// Single-scattering-inspired warm horizon halo reuses the existing glow term.
		// No additional noise lookups or texture taps on low-end hardware.
		float horizon_halo = 1.0 - smoothstep(0.04, 0.42, abs(up));
		// Transition from the original narrow painted halo toward directional haze.
		color += vec3(0.9, 0.31, 0.10) * (glow * 0.38) * horizon_halo
			* dusk * visible * (1.0 - aerosol_scattering_strength * 0.65);
		// Henyey-Greenstein-inspired aerosol lobe for sunset aerial perspective.
		// Sun orientation affects both visible sky and the reflected sky cubemap.
		if (aerosol_scattering_strength > 0.001 && daylight > 0.025 && up > -0.06 && storm < 0.98) {
			float anisotropy = 0.67;
			float denom = max(1.0 + anisotropy * anisotropy
				- 2.0 * anisotropy * clamp(facing, -1.0, 1.0), 0.10);
			float aerosol_phase = (1.0 - anisotropy * anisotropy)
				* inversesqrt(denom) / denom;
			float sunward = clamp(aerosol_phase * 0.074, 0.0, 1.0);
			float horizon_air = 1.0 - smoothstep(0.06, 0.63, max(up, 0.0));
			float twilight = clamp(dusk, 0.0, 1.0) * smoothstep(0.08, 0.40, daylight);
			vec3 aerosol_color = mix(vec3(0.42, 0.64, 0.86),
				vec3(1.0, 0.48, 0.21), twilight);
			float atmospheric_visibility = daylight * (1.0 - storm * 0.88);
			color += aerosol_color * sunward * horizon_air * 0.42
				* atmospheric_visibility * aerosol_scattering_strength;
		}
		// The same cached cloud field shades distant terrain and the upper sky.
		// Do not use the camera position or built-in TIME: Godot would refresh
		// sky radiance on every camera move/frame instead of the chosen cadence.
		if (cirrus_detail > 0 && cirrus_opacity > 0.001 && up > 0.08) {
			// Project directions onto a fixed-height cloud plane. Avoid its
			// horizon singularity and fade the layer out before the clamp.
			vec2 cloud_uv = dir.xz * (0.18 / max(up, 0.16))
				+ cirrus_wind_offset / 1024.0;
			// The native RGBA field REPLACES the L8 lookup on premium
			// renderers: no extra sky texture samples, just a few ALU ops.
			vec4 cloud_profile;
			if (has_cloud_lighting_lut && cloud_lighting_strength > 0.001) {
				cloud_profile = texture(cloud_lighting_lut, cloud_uv);
			} else {
				cloud_profile = vec4(texture(cirrus_lut, cloud_uv).r, 0.5, 0.5, 1.0);
			}
			float cloud_shape = cloud_profile.r;
			if (cirrus_detail > 1) {
				// Ultra adds a second scale to break up broad cloud patches.
				float filaments = texture(cirrus_lut,
					cloud_uv * 2.4 + vec2(0.17, 0.43)).r;
				cloud_shape *= mix(0.68, 1.08, filaments);
			}
			float cloud_alpha = clamp(cloud_shape * cirrus_opacity
				* smoothstep(0.08, 0.32, up), 0.0, 0.65);
			// Broad skylight and a directional warm edge from the existing sun.
			vec3 lit_cloud = mix(vec3(0.76, 0.83, 0.92),
				vec3(1.0, 0.61, 0.38), dusk * 0.82);
			float forward_light = pow(max(facing, 0.0), 12.0);
			lit_cloud += sun_color * (0.16 * forward_light * daylight);
			if (has_cloud_lighting_lut && cloud_lighting_strength > 0.001
					&& daylight > 0.025) {
				// The encoded gradient gives a coarse cloud-facing normal,
				// lit by the actual moving sun. Dense cores occlude skylight
				// while sunward edges have a warm silver lining.
				vec2 gradient = (cloud_profile.gb - vec2(0.5)) / 0.75;
				vec3 cloud_normal = normalize(vec3(-gradient.x * 3.0, 1.0, -gradient.y * 3.0));
				float incidence = max(dot(cloud_normal, normalize(sun_direction)), 0.0);
				float ambient = mix(0.40, 0.91, cloud_profile.a);
				float rim = min(length(gradient) * 3.0, 1.0)
					* pow(max(facing, 0.0), 7.0);
				vec3 sculpted_cloud = lit_cloud * (ambient + incidence * 0.38)
					+ sun_color * rim * daylight * 0.45;
				lit_cloud = mix(lit_cloud, sculpted_cloud, cloud_lighting_strength);
			}
			lit_cloud = mix(lit_cloud, storm_color, storm * 0.9);
			// Nighttime cloud cover dims stars instead of glowing white.
			vec3 dark_cloud = mix(night_horizon * 0.55, night_top * 0.8,
				clamp(up, 0.0, 1.0));
			vec3 cloud_color = mix(dark_cloud, lit_cloud, daylight);
			color = mix(color, cloud_color, cloud_alpha * (1.0 - storm * 0.2));
		}
		if (volumetric_cloud_steps > 0 && up > 0.03) {
			// March a flat slab (scaled units). Fixed-height projection keeps the result
			// independent of camera position so sky radiance stays cached.
			int steps = AT_CUBEMAP_PASS ? max(volumetric_cloud_steps / 2, 8) : volumetric_cloud_steps;
			float coverage = clamp(volumetric_cloud_coverage + storm * 0.4, 0.0, 1.0);
			float t0 = 1.0 / up;
			float t1 = 1.6 / up;
			float dt = (t1 - t0) / float(steps);
			vec3 wind = vec3(cirrus_wind_offset.x, 0.0, cirrus_wind_offset.y) / 256.0
				+ vec3(sky_time * 0.004, 0.0, sky_time * 0.0025);
			vec3 sun_dir = normalize(sun_direction);
			float cos_theta = dot(dir, sun_dir);
			// Dual-lobe phase: forward silver lining + soft back scatter.
			float phase = mix(hg_phase(cos_theta, 0.6), hg_phase(cos_theta, -0.25), 0.3) * 4.0 * PI;
			vec3 sky_amb = mix(day_horizon, day_top, 0.5) * mix(1.0, 0.45, storm);
			vec3 amb = mix(night_horizon * 0.6, sky_amb, daylight);
			vec3 sun_l = sun_color * daylight * (1.0 - storm * 0.7);
			sun_l = mix(sun_l, sun_l * dusk_color * 1.4, dusk * 0.6);
			float trans = 1.0;
			vec3 scat = vec3(0.0);
			float jitter = hash(dir * 431.0 + sky_time);
			for (int i = 0; i < steps; i++) {
				float t = t0 + (float(i) + jitter) * dt;
				vec3 pos = dir * t;
				float h = (pos.y - 1.0) / 0.6;
				float d = cloud_density(pos * vec3(0.9, 1.6, 0.9) + wind, h, coverage);
				if (d > 0.01) {
					// Three short taps towards the sun for self-shadowing.
					float ls = 0.0;
					for (int k = 1; k <= 3; k++) {
						vec3 lp = pos + sun_dir * (0.08 * float(k));
						ls += cloud_density(lp * vec3(0.9, 1.6, 0.9) + wind, (lp.y - 1.0) / 0.6, coverage);
					}
					float beer = exp(-ls * 1.6);
					float powder = 1.0 - exp(-d * 4.0); // Beer-Powder (Schneider 2015)
					vec3 lum = sun_l * beer * mix(1.0, powder, 0.5) * phase + amb * (0.35 + 0.5 * h);
					float st = exp(-d * dt * 9.0);
					scat += trans * lum * (1.0 - st);
					trans *= st;
					if (trans < 0.02) {
						break;
					}
				}
			}
			float horizon_fade = smoothstep(0.03, 0.18, up);
			trans = mix(1.0, trans, horizon_fade);
			color = color * trans + scat * horizon_fade;
		}
		COLOR = color;
	}
}
