shader_type canvas_item;
// Gameplay camera overlay (Unity URP Volume / Unreal Post Process Volume equivalent): damage vignette, low-health
// desaturation + heartbeat, hit chromatic aberration, radial speed blur and the death letterbox. Drawn above the
// grade pass and below the interface. Every effect is a uniform, so an idle frame is skipped by hiding the rect.
render_mode unshaded;

uniform sampler2D screen : hint_screen_texture, filter_linear;
uniform float hurt = 0.0;
uniform vec3 hurt_color = vec3(0.62, 0.02, 0.03);
uniform float low_health = 0.0;
uniform float heartbeat = 0.0;
uniform float aberration = 0.0;
uniform float radial_blur = 0.0;
uniform int blur_taps = 0; // 0 disables the blur loop entirely (Low quality).
uniform float letterbox = 0.0;

vec3 grab(vec2 p, vec2 o) {
	return vec3(texture(screen, p + o).r, texture(screen, p).g, texture(screen, p - o).b);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 d = uv - vec2(0.5);
	float r = length(d * vec2(1.0, 0.8));
	vec2 ab = d * aberration * 0.018;
	vec3 col;
	if (blur_taps > 0 && radial_blur > 0.001) {
		col = vec3(0.0);
		float edge = smoothstep(0.1, 0.6, r);
		for (int i = 0; i < 8; i++) {
			if (i >= blur_taps) {
				break;
			}
			float s = float(i) / float(blur_taps);
			col += grab(uv - d * radial_blur * 0.07 * edge * s, ab);
		}
		col /= float(blur_taps);
	} else if (aberration > 0.001) {
		col = grab(uv, ab);
	} else {
		col = texture(screen, uv).rgb;
	}
	float luma = dot(col, vec3(0.299, 0.587, 0.114));
	col = mix(col, vec3(luma) * vec3(0.92, 0.97, 1.05), low_health * 0.75);
	float vig = smoothstep(0.22, 0.85, r);
	col = mix(col, hurt_color, clamp(vig * hurt * 0.7, 0.0, 0.85));
	col = mix(col, hurt_color * 0.3, vig * heartbeat * 0.5);
	float bar = letterbox * 0.11;
	if (uv.y < bar || uv.y > 1.0 - bar) {
		col = vec3(0.0);
	}
	COLOR = vec4(col, 1.0);
}
