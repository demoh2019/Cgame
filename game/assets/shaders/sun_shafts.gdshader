shader_type spatial;
// Screen-space volumetric sun shafts ("god rays"), as used by Unreal's Light Shafts,
// CryEngine sun shafts and GPU Gems 3 ch.13: radial march from each pixel towards the
// projected sun, accumulating unoccluded sky. Occluders (terrain, trees, buildings)
// carve dark streaks; open sky bleeds warm light into hazy air. One fullscreen pass.
render_mode unshaded, blend_add, depth_test_disabled, depth_draw_never, cull_disabled, fog_disabled, shadows_disabled;

uniform sampler2D depth_tex : hint_depth_texture, filter_nearest, repeat_disable;
uniform vec3 sun_dir_world = vec3(0.0, 1.0, 0.0); // points TOWARDS the sun
uniform vec3 sun_color : source_color = vec3(1.0, 0.85, 0.6);
uniform float intensity = 0.35;
uniform float decay = 0.965;
uniform float density = 0.85;
uniform int samples = 32;

void vertex() {
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

float ign(vec2 p) {
	return fract(52.9829189 * fract(dot(p, vec2(0.06711056, 0.00583715))));
}

void fragment() {
	vec3 sun_view = (VIEW_MATRIX * vec4(normalize(sun_dir_world), 0.0)).xyz;
	float facing = -sun_view.z; // >0 when the sun is in front of the camera
	if (facing <= 0.02 || intensity <= 0.0) {
		discard;
	}
	vec4 clip = PROJECTION_MATRIX * vec4(sun_view, 0.0);
	vec2 sun_uv = clip.xy / clip.w * 0.5 + 0.5;
	vec2 delta = (sun_uv - SCREEN_UV) * density / float(samples);
	vec2 uv = SCREEN_UV + delta * ign(FRAGCOORD.xy); // jitter removes banding
	float w = 1.0;
	float acc = 0.0;
	for (int i = 0; i < samples; i++) {
		uv += delta;
		vec2 c = clamp(uv, vec2(0.001), vec2(0.999));
		// Reversed-Z: the far plane (sky) has depth 0.
		float sky = step(texture(depth_tex, c).r, 0.000001);
		acc += sky * w;
		w *= decay;
	}
	acc /= float(samples);
	float radial = 1.0 - smoothstep(0.0, 0.9, length((SCREEN_UV - sun_uv) * vec2(VIEWPORT_SIZE.x / VIEWPORT_SIZE.y, 1.0)));
	float fade = smoothstep(0.02, 0.35, facing);
	ALBEDO = sun_color * (acc * radial * fade * intensity);
}
