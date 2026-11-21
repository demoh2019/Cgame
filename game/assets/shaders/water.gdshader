shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, diffuse_burley, specular_schlick_ggx;
global uniform float aa_weather_wetness;
global uniform float aa_weather_rain;
// Sun vector/radiance are cached with the sky, so water never asks the CPU
// to update a material per pixel or per streamed ocean mesh.
global uniform vec3 aa_sun_to_light;
global uniform vec3 aa_sun_radiance;
// Shared smoothed regional weather wind, uploaded at 10 Hz by Atmosphere.
// xy is the wind direction, z is normalized wind strength (0..1).
global uniform vec3 aa_vegetation_wind;

// Open water: colour from the depth under the surface, a soft foam line along the shore, scrolling ripples
// and a Fresnel sheen that picks up the sky.
uniform sampler2D depth_tex : hint_depth_texture, repeat_disable, filter_nearest;
// The screen sampler only exists in the dedicated high-end Forward+ variant.
#ifdef WATER_REFRACTION
uniform sampler2D scene_color_tex : hint_screen_texture, repeat_disable, filter_linear;
uniform float refraction_strength = 0.0;
uniform float refraction_fade_start = 25.0;
uniform float refraction_fade_end = 74.0;
#endif
uniform vec3 shallow_color : source_color = vec3(0.16, 0.5, 0.52);
uniform vec3 deep_color : source_color = vec3(0.02, 0.15, 0.3);
uniform float clarity = 5.0;
// Single-scattering approximation for translucent shoreline water.
// Performance sets zero, skipping all optical scattering work.
uniform float shallow_scattering_strength = 0.0;
uniform float ripple_strength = 0.35;
// Optional near-camera wind-aligned wave response. Zero on low-end tiers.
uniform float wind_wave_strength = 0.0;
#ifdef WATER_REFRACTION
// Forward+ high-end only: stretch GGX highlights along the real wind fetch.
// Godot's built-in anisotropic BRDF handles direct lights and IBL without
// another reflection pass or any new texture sample.
uniform float wind_anisotropy_strength = 0.0;
// Premium water only: wind-advected foam ribbons share the existing wave
// slope, depth, and weather fields. Disabled in low-end compiled variants.
uniform float wind_foam_strength = 0.0;
// Sun-aligned small wave glints are exclusive to the premium Forward+ shader.
uniform float sun_glitter_strength = 0.0;
#endif
uniform float detail_fade_start = 65.0;
uniform float detail_fade_end = 125.0;
// Near-shore light filaments are enabled only on high-end presets and only in shallow water.
uniform float shore_glimmer_strength = 0.0;
// Animated depth-following swash; disabled on Performance/Balanced without
// extra samplers, draw passes or a mesh simulation.
uniform float shore_surf_strength = 0.0;
uniform float shore_glimmer_fade_start = 28.0;
uniform float shore_glimmer_fade_end = 62.0;

varying vec3 world_position;
varying vec2 gerstner_slope;
varying float gerstner_crest;

// Open-sea swell (Gerstner waves). Zero on rivers and lakes (their own material instances).
uniform float gerstner_amplitude = 0.0;
// Tessendorf FFT chop: two CPU-evaluated tiles cross-faded per frame (sea_fft_detail.gd).
uniform sampler2D fft_height_a : filter_linear, repeat_enable;
uniform sampler2D fft_height_b : filter_linear, repeat_enable;
uniform float fft_blend = 0.0;
uniform float fft_patch_size = 48.0;
uniform float fft_strength = 0.0;
// Island depth map (R = metres of water under the sea level, 0 on land), covering shore_map_rect:
// waves shrink and steepen into surf where the sea gets shallow.
uniform sampler2D shore_map : filter_linear, repeat_disable;
uniform vec4 shore_map_rect = vec4(-3200.0, -3200.0, 6400.0, 6400.0);
uniform float has_shore_map = 0.0;
// Underside of the surface, seen while diving.
uniform vec3 underside_color : source_color = vec3(0.03, 0.2, 0.24);
uniform vec3 snell_window_color : source_color = vec3(0.55, 0.78, 0.82);

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

// One Gerstner wave: direction, wavelength (m), steepness Q, speed scale. Adds displacement and slope.
void gerstner(vec2 dir, float wavelength, float steepness, float amp, vec2 p, float t,
		inout vec3 offset, inout vec2 slope) {
	float k = 6.2831853 / wavelength;
	float c = sqrt(9.81 / k);
	float a = steepness / k * amp * 0.28; // Calm ~0.5 m swell, ~1.3 m in a storm.
	float f = k * (dot(dir, p) - c * t);
	offset.xz += dir * a * cos(f);
	offset.y += a * sin(f);
	slope += dir * k * a * cos(f);
}

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	gerstner_slope = vec2(0.0);
	gerstner_crest = 0.0;
	if (gerstner_amplitude > 0.001) {
		vec2 p = world_position.xz;
		float shallow = 1.0;
		if (has_shore_map > 0.5) {
			float depth = texture(shore_map, (p - shore_map_rect.xy) / shore_map_rect.zw).r;
			shallow = smoothstep(0.4, 7.0, depth);
		}
		float storm = clamp(aa_weather_rain, 0.0, 1.0);
		vec2 wind = length(aa_vegetation_wind.xy) > 0.01 ? normalize(aa_vegetation_wind.xy) : vec2(0.8, 0.6);
		float power = gerstner_amplitude * (0.6 + 0.8 * clamp(aa_vegetation_wind.z, 0.0, 1.0) + storm * 1.2) * (0.25 + 0.75 * shallow);
		vec3 offset = vec3(0.0);
		vec2 slope = vec2(0.0);
		gerstner(wind, 41.0, 0.32, power, p, TIME, offset, slope);
		gerstner(normalize(wind + vec2(0.45, -0.3)), 23.0, 0.28, power, p, TIME * 1.07, offset, slope);
		gerstner(normalize(wind + vec2(-0.5, 0.35)), 13.0, 0.24, power, p, TIME * 0.93, offset, slope);
		gerstner(normalize(vec2(-wind.y, wind.x) + wind), 7.0, 0.18, power, p, TIME * 1.11, offset, slope);
		if (fft_strength > 0.001) {
			vec2 fuv = p / fft_patch_size;
			float texel = 1.0 / 32.0;
			float h = mix(textureLod(fft_height_a, fuv, 0.0).r, textureLod(fft_height_b, fuv, 0.0).r, fft_blend);
			float hx = mix(textureLod(fft_height_a, fuv + vec2(texel, 0.0), 0.0).r, textureLod(fft_height_b, fuv + vec2(texel, 0.0), 0.0).r, fft_blend);
			float hz = mix(textureLod(fft_height_a, fuv + vec2(0.0, texel), 0.0).r, textureLod(fft_height_b, fuv + vec2(0.0, texel), 0.0).r, fft_blend);
			float chop = fft_strength * power;
			offset.y += h * chop;
			slope += vec2(hx - h, hz - h) * chop / (fft_patch_size * texel);
		}
		VERTEX += (inverse(mat3(MODEL_MATRIX)) * offset);
		world_position += offset;
		gerstner_slope = slope;
		gerstner_crest = clamp(offset.y * 0.9 / max(power, 0.05), 0.0, 1.0);
	}
#ifdef WATER_REFRACTION
	// Horizontal water plane: provide a stable world-aligned tangent frame.
	// Imported meshes need no tangent data and low-end variants skip it.
	TANGENT = vec3(1.0, 0.0, 0.0);
	BINORMAL = vec3(0.0, 0.0, 1.0);
#endif
}

void fragment() {
	if (!FRONT_FACING) {
		// Looking up from below: dark teal water, and the bright Snell's window straight overhead where
		// the sky shows through; beyond ~48 degrees the surface reflects the depths (total internal reflection).
		vec3 view_world = normalize((INV_VIEW_MATRIX * vec4(VIEW, 0.0)).xyz);
		float up = clamp(-view_world.y, 0.0, 1.0); // VIEW points at the camera, which is below.
		float window = smoothstep(0.62, 0.78, up);
		float ripple = value_noise(world_position.xz * 0.8 + vec2(TIME * 0.3, TIME * -0.2));
		ALBEDO = vec3(0.0);
		EMISSION = mix(underside_color, snell_window_color * (0.8 + 0.4 * ripple), window);
		ALPHA = mix(0.92, 0.55, window);
		ROUGHNESS = 0.2;
	} else {
	float t = TIME;
	vec2 p = world_position.xz;
	float storm = clamp(aa_weather_rain, 0.0, 1.0);
	float storm_wave_strength = 1.0 + storm * 0.65;
	// Analytic wave slopes avoid recomputing three octaves of noise at three nearby
	// pixel positions. Two opposing wave trains preserve motion and sun glints.
	// High/Ultra add fine noise only where their visual budget allows it.
	float crest = 0.0;
#ifdef WATER_REFRACTION
	vec3 wave_world_normal = vec3(0.0, 1.0, 0.0);
	vec2 refract_slope = vec2(0.0);
#endif
	// Only high-quality fine noise needs camera distance. Balanced/Performance
	// skip this calculation and all expensive high-frequency noise octaves.
	float detail_fade = 0.0;
	if (ripple_strength > 0.30) {
		detail_fade = 1.0 - smoothstep(detail_fade_start, detail_fade_end,
			distance(p, CAMERA_POSITION_WORLD.xz));
	}
	if (ripple_strength > 0.001) {
		float wave_a = dot(p, vec2(0.85, 0.52)) * 1.6 + t * 0.8;
		float wave_b = dot(p, vec2(-0.42, 0.91)) * 3.2 - t * 1.2;
		vec2 slope = vec2(0.85, 0.52) * cos(wave_a) * 0.065
			+ vec2(-0.42, 0.91) * cos(wave_b) * 0.04;
		if (ripple_strength > 0.30 && detail_fade > 0.001) {
			vec2 flow = p * 0.65 + vec2(t * 0.07, -t * 0.06);
			float e = 0.3;
			float h = value_noise(flow);
			slope += vec2(value_noise(flow + vec2(e, 0.0)) - h,
				value_noise(flow + vec2(0.0, e)) - h) * (0.13 / e) * detail_fade;
		}
		// High/Ultra wind fetch: one analytic travelling wave, oriented by
		// the already smoothed regional weather vector. Use the same slope
		// for PBR normals, screen refraction and storm whitecaps.
		// Near-only and preset-gated: no additional work offshore in the
		// distance, in calm weather, or on Performance/Balanced.
		if (wind_wave_strength > 0.001 && detail_fade > 0.001
				&& aa_vegetation_wind.z > 0.001) {
			vec2 wind_dir = normalize(aa_vegetation_wind.xy);
			float wind_power = clamp(aa_vegetation_wind.z, 0.0, 1.0);
			float flow_phase = dot(p, wind_dir) * 1.25
				- t * (0.7 + 0.9 * wind_power);
			vec2 wind_slope = wind_dir * cos(flow_phase) * (0.035 + storm * 0.025);
			slope += wind_slope * wind_wave_strength * wind_power * detail_fade;
		}
		// Amplify the existing waves rather than adding costly new noise samples.
		slope *= storm_wave_strength;
		slope += gerstner_slope * 0.6; // Swell from the Gerstner waves (normals follow the displaced surface).
#ifdef WATER_REFRACTION
		refract_slope = slope;
#endif
		vec3 world_normal = normalize(vec3(-slope.x * ripple_strength * 2.5, 1.0,
			-slope.y * ripple_strength * 2.5));
		NORMAL = normalize((VIEW_MATRIX * vec4(world_normal, 0.0)).xyz);
#ifdef WATER_REFRACTION
		// Reuse the exact normal driving lit waves and refraction.
		wave_world_normal = world_normal;
#endif
		crest = max(smoothstep(0.04, 0.11, length(slope)), smoothstep(0.75, 1.0, gerstner_crest) * 0.8);
	}

	float depth = textureLod(depth_tex, SCREEN_UV, 0.0).r;
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, depth * 2.0 - 1.0);
#else
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, depth);
#endif
	vec4 scene = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	scene.xyz /= scene.w;
	float thickness = max(-scene.z + VERTEX.z, 0.0);

	// Beer-Lambert-inspired depth attenuation: red disappears first, then green.
	// One exponential and a few ALU operations replace three expensive per-channel exponentials.
	float transmission = exp(-thickness / max(clarity, 0.1));
	vec3 spectral_transmission = vec3(transmission * transmission, transmission, sqrt(transmission));
	float depth_mix = 1.0 - transmission;
	vec3 color = deep_color + (shallow_color - deep_color) * spectral_transmission;
	// Most ocean pixels have no shoreline. Avoid even coarse foam noise when
	// the depth difference says foam cannot contribute to the final color.
	float edge = 1.0 - smoothstep(0.0, 0.9, thickness);
	// Evaluate derivatives in uniform control flow before shoreline branching.
	// Only high-end presets pay for the filtered surf footprint.
	float surf_footprint = 0.0;
	if (shore_surf_strength > 0.001) {
		surf_footprint = clamp(fwidth(thickness) * 0.42, 0.025, 0.16);
	}
	float foam = 0.0;
	if (edge > 0.001) {
		float foam_noise = 0.6;
		if (ripple_strength > 0.001) {
			foam_noise = value_noise(p * 3.2 + vec2(t * 0.2, -t * 0.15));
			if (ripple_strength > 0.30 && detail_fade > 0.001) {
				foam_noise = mix(foam_noise,
					value_noise(p * 7.0 - vec2(t * 0.3)), 0.4 * detail_fade);
			}
		}
		foam = smoothstep(0.35, 0.75, foam_noise + edge * 0.9 - 0.55) * edge;
		// Travelling surf follows the scene-depth coastline instead of a
		// screen-space stripe. Reuse foam noise for organic breakup.
		if (shore_surf_strength > 0.001 && detail_fade > 0.001) {
			float surge_phase = t * (0.95 + storm * 0.30)
				+ dot(p, vec2(0.37, -0.25) + aa_vegetation_wind.xy * 0.04);
			float surge_depth = 0.34 + 0.18 * sin(surge_phase)
				+ (foam_noise - 0.5) * 0.18;
			float surf_distance = abs(thickness - surge_depth);
			float surf_band = 1.0 - smoothstep(0.055,
				0.055 + surf_footprint, surf_distance);
			float breakup = 0.55 + 0.45 * smoothstep(0.15, 0.85, foam_noise);
			float surf_foam = surf_band * breakup * shore_surf_strength
				* detail_fade * (0.75 + 0.25 * storm);
			foam = max(foam, surf_foam * edge);
		}
	}
	// Small storm whitecaps extend over deep water, with zero extra texture reads.
	float storm_whitecaps = crest * storm * min(ripple_strength * 1.2, 0.55)
		* smoothstep(0.2, 1.2, thickness);
	foam = clamp(foam + storm_whitecaps, 0.0, 1.0);
#ifdef WATER_REFRACTION
	// Long, broken foam ribbons appear in windy water, as in high-end
	// water rendering. One low-cost analytic pattern, no new textures,
	// depth samples, transparencies or simulation buffers.
	// World-space wind direction guarantees streaks travel with weather
	// rather than moving when the camera or screen resolution changes.
	if (wind_foam_strength > 0.001 && detail_fade > 0.001
			&& aa_vegetation_wind.z > 0.22 && thickness > 0.65) {
		vec2 foam_wind_dir = normalize(aa_vegetation_wind.xy);
		float foam_wind_power = smoothstep(0.20, 0.85,
			clamp(aa_vegetation_wind.z, 0.0, 1.0));
		float along_wind = dot(p, foam_wind_dir);
		float across_wind = dot(p, vec2(-foam_wind_dir.y, foam_wind_dir.x));
		float advect_phase = along_wind * 2.4
			- t * (1.4 + 0.7 * foam_wind_power);
		float ribbon_wave = sin(advect_phase + 0.44 * sin(across_wind * 1.5));
		float breakup_wave = sin(across_wind * 6.6
			+ along_wind * 0.4 - t * 0.25);
		float ribbon_mask = smoothstep(0.62, 0.88, ribbon_wave)
			* smoothstep(-0.2, 0.5, breakup_wave);
		float wind_foam = ribbon_mask * (0.3 + 0.7 * crest)
			* foam_wind_power * wind_foam_strength * detail_fade
			* (0.45 + 0.55 * storm) * smoothstep(0.65, 2.0, thickness);
		foam = clamp(foam + wind_foam, 0.0, 1.0);
	}
#endif
	color = mix(color * (1.0 - storm * 0.10), vec3(0.95, 0.98, 1.0), foam);
	// Low-cost animated shallow-water glints. No screen-texture, extra render pass,
	// caustic texture or per-pixel shoreline noise on Performance/Balanced.
	float shore_glimmer = 0.0;
	if (shore_glimmer_strength > 0.001 && thickness < 3.2) {
		float near_fade = 1.0 - smoothstep(shore_glimmer_fade_start, shore_glimmer_fade_end,
			distance(p, CAMERA_POSITION_WORLD.xz));
		if (near_fade > 0.001) {
			float strand_a = sin(p.x * 2.1 + sin(p.y * 1.3 + t * 0.65) + t * 0.45);
			float strand_b = sin(p.y * 2.6 - p.x * 0.75 - t * 0.55);
			float filaments = pow(max(strand_a * strand_b, 0.0), 7.0);
			shore_glimmer = filaments * (1.0 - smoothstep(0.35, 3.2, thickness))
				* near_fade * shore_glimmer_strength * (1.0 - foam);
		}
	}
	color += vec3(0.06, 0.12, 0.11) * shore_glimmer;
	// Near-shore subsurface scattering: light penetrates the water, then
	// escapes toward the camera. Reuse the Beer-Lambert transmission above:
	// one scattering probability (1 - T²) times the surviving light (T).
	// Unlike a ray-marched volume, this costs NO screen reads or extra exp().
	if (shallow_scattering_strength > 0.001 && thickness > 0.08 && thickness < 8.0
			&& aa_sun_radiance.y > 0.001) {
		float single_scatter = (1.0 - transmission * transmission) * transmission;
		float shoreline = 1.0 - smoothstep(4.2, 8.0, thickness);
		vec3 to_eye = normalize(CAMERA_POSITION_WORLD - world_position);
		// Forward scattering is brightest when sunlight enters along the
		// viewing direction, but shallow ambient fill remains soft at noon.
		float phase = 0.58 + 0.42 * pow(max(dot(to_eye,
			normalize(aa_sun_to_light)), 0.0), 2.0);
		vec3 spectral_scatter = vec3(0.06, 0.24, 0.22) * aa_sun_radiance;
		color += spectral_scatter * (shallow_scattering_strength * single_scatter
			* shoreline * phase * (1.0 - foam) * (1.0 - storm * 0.25));
	}
#ifdef WATER_REFRACTION
	// Thin-water transmission with actual screen-space refraction:
	// clipped geometry, depth discontinuities and screen edges fade to base
	// water instead of creating the halos typical of naïve refraction.
	float refraction_mix = 0.0;
	// Difference between warped and straight opaque scene color. Never add
	// the absolute scene color: that would double-count transmission and
	// make shorelines look unnaturally emissive.
	vec3 refraction_delta = vec3(0.0);
	if (refraction_strength > 0.001 && thickness > 0.08 && thickness < 3.8) {
		float near_fade = 1.0 - smoothstep(refraction_fade_start,
			refraction_fade_end, distance(p, CAMERA_POSITION_WORLD.xz));
		if (near_fade > 0.001) {
			// The analytic wave is already computed for NORMAL: no extra noise.
			vec2 shift = refract_slope * refraction_strength * 0.062
				* min(thickness * 0.7, 1.0);
			vec2 refracted_uv = clamp(SCREEN_UV + shift,
				vec2(0.006), vec2(0.994));
			vec2 margins = min(refracted_uv, vec2(1.0) - refracted_uv);
			float edge_guard = smoothstep(0.006, 0.024,
				min(margins.x, margins.y));
			if (edge_guard > 0.001) {
				float warped_depth = textureLod(depth_tex,
					refracted_uv, 0.0).r;
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
				vec3 warped_ndc = vec3(refracted_uv * 2.0 - 1.0,
					warped_depth * 2.0 - 1.0);
#else
				vec3 warped_ndc = vec3(refracted_uv * 2.0 - 1.0,
					warped_depth);
#endif
				vec4 warped_scene = INV_PROJECTION_MATRIX *
					vec4(warped_ndc, 1.0);
				float warped_thickness = max(
					-warped_scene.z / warped_scene.w + VERTEX.z, 0.0);
				float depth_guard = smoothstep(0.08, 0.35,
					warped_thickness) * (1.0 - smoothstep(
					0.48, 1.65, abs(warped_thickness - thickness)));
				float shallow_guard = 1.0 - smoothstep(
					2.2, 3.8, thickness);
				refraction_mix = refraction_strength * near_fade
					* edge_guard * depth_guard * shallow_guard
					* sqrt(transmission);
				if (refraction_mix > 0.001) {
					vec3 refracted_scene = textureLod(scene_color_tex,
						refracted_uv, 0.0).rgb;
					vec3 straight_scene = textureLod(scene_color_tex,
						SCREEN_UV, 0.0).rgb;
					refraction_delta = refracted_scene - straight_scene;
				}
			}
		}
	}
#endif

	// Schlick Fresnel for the 2%-reflective water/air interface, instead of
	// a stylized cubic approximation that over-brightens front-facing water.
	float ndotv = clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
	float fresnel = 0.02 + 0.98 * pow(1.0 - ndotv, 5.0);
	ALBEDO = color;
	ALPHA = clamp(mix(0.28, 0.93, smoothstep(0.0, 2.5, thickness)) + foam * 0.5 + fresnel * 0.25, 0.0, 1.0);
	// Preserve the base physical water opacity and sky/foam lighting.
	// Only the background contribution should bend through refraction.
	ROUGHNESS = mix(0.06 + storm * 0.05, 0.4 + storm * 0.05, foam);
#ifdef WATER_REFRACTION
	// Anisotropic specular lobes align with the existing weather wind, not
	// with camera motion. Only premium near-field, visible wavelets contribute.
	ANISOTROPY = 0.0;
	ANISOTROPY_FLOW = vec2(1.0, 0.0);
	if (wind_anisotropy_strength > 0.001 && detail_fade > 0.001
			&& aa_vegetation_wind.z > 0.03 && foam < 0.95) {
		vec2 wind_flow = aa_vegetation_wind.xy;
		if (dot(wind_flow, wind_flow) > 0.0001) {
			ANISOTROPY_FLOW = normalize(wind_flow);
			ANISOTROPY = clamp(wind_anisotropy_strength
				* clamp(aa_vegetation_wind.z, 0.0, 1.0)
				* detail_fade * (1.0 - foam), 0.0, 0.45);
		}
	}
#endif
	SPECULAR = 0.7;
	METALLIC = 0.0;
	EMISSION = vec3(0.01, 0.04, 0.05) * (1.0 - depth_mix)
		+ vec3(0.08, 0.12, 0.16) * fresnel
		+ vec3(0.015, 0.025, 0.028) * crest * (1.0 - foam)
		+ vec3(0.07, 0.13, 0.12) * shore_glimmer;
#ifdef WATER_REFRACTION
	// Sun glitter reuses the *same* animated waves and cached sky lighting.
	// One bounded microfacet-inspired view/sun lobe represents subpixel
	// sparkling wavelets. It is not a second sun, SSR pass or texture.
	if (sun_glitter_strength > 0.001 && detail_fade > 0.001 &&
			aa_sun_radiance.y > 0.001 && foam < 0.95 && aa_sun_to_light.y > 0.04) {
		vec3 to_view = normalize(CAMERA_POSITION_WORLD - world_position);
		vec3 reflected_sun = reflect(-normalize(aa_sun_to_light), wave_world_normal);
		float alignment = max(dot(reflected_sun, to_view), 0.0);
		float lobe = pow(alignment, 48.0);
		float daylight_visible = smoothstep(0.04, 0.20, aa_sun_to_light.y);
		float sparkle = 0.40 + 0.60 * crest;
		float glint = min(0.16, lobe * sparkle * sun_glitter_strength
			* detail_fade * daylight_visible * (1.0 - foam) * 0.12);
		EMISSION += aa_sun_radiance * glint;
	}
#endif
#ifdef WATER_REFRACTION
	// Source alpha blending is: lit_water * ALPHA + scene * (1 - ALPHA).
	// Add only the changed, already-lit transmitted background. Dividing by
	// alpha compensates for how Godot blends the water fragment, ensuring
	// the original scene is not counted twice and the surface does not glow.
	float transmission_weight = refraction_mix * (1.0 - ALPHA) / max(ALPHA, 0.20);
	EMISSION += refraction_delta * transmission_weight;
#endif
	} // front face
}
