shader_type canvas_item;
// The finishing pass over the 3D view (under the HUD): a gentle tilt-shift that softens the top and bottom of the frame so
// the world reads like a miniature diorama, split toning (warm highlights, cool shadows), a touch of contrast and a
// soft vignette. Everything subtle: it should be felt, not noticed.

uniform sampler2D screen : hint_screen_texture, filter_linear;
uniform float focus_center = 0.52; // Screen height (0 top, 1 bottom) that stays sharp: where the player stands.
uniform float focus_width = 0.24;
uniform float blur_radius = 2.6; // In pixels at the very edge.
uniform float vignette = 0.28;
uniform float grade = 1.0;
uniform int blur_quality = 1; // 0: no blur, 1: 4 extra samples, 2: 8 extra samples.

void fragment() {
	vec2 uv = SCREEN_UV;
	float away = smoothstep(focus_width, focus_width + 0.32, abs(uv.y - focus_center));
	vec3 color = texture(screen, uv).rgb;
	if (away > 0.01 && blur_quality > 0) {
		// Four taps for balanced hardware; four more for the high-quality diorama look.
		vec2 r = SCREEN_PIXEL_SIZE * blur_radius * away;
		vec3 sum = color;
		sum += texture(screen, uv + vec2(r.x, 0.0)).rgb;
		sum += texture(screen, uv - vec2(r.x, 0.0)).rgb;
		sum += texture(screen, uv + vec2(0.0, r.y)).rgb;
		sum += texture(screen, uv - vec2(0.0, r.y)).rgb;
		if (blur_quality > 1) {
			sum += texture(screen, uv + r * 0.7).rgb;
			sum += texture(screen, uv - r * 0.7).rgb;
			sum += texture(screen, uv + vec2(r.x, -r.y) * 0.7).rgb;
			sum += texture(screen, uv + vec2(-r.x, r.y) * 0.7).rgb;
			color = sum / 9.0;
		} else {
			color = sum / 5.0;
		}
	}
	// Split toning: shadows lean blue-teal, highlights lean warm gold.
	float luma = dot(color, vec3(0.299, 0.587, 0.114));
	vec3 toned = color + mix(vec3(-0.012, 0.0, 0.025), vec3(0.03, 0.015, -0.02), smoothstep(0.2, 0.8, luma));
	// A soft S-curve for a little more depth.
	toned = mix(toned, toned * toned * (3.0 - 2.0 * toned), 0.18);
	color = mix(color, toned, grade);
	// Vignette.
	vec2 centered = uv - vec2(0.5, focus_center);
	float edge = smoothstep(0.45, 0.95, length(centered * vec2(1.0, 1.25)));
	color *= 1.0 - edge * vignette;
	COLOR = vec4(color, 1.0);
}
