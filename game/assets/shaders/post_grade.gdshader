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
// Two color-grade controls replace the previous fixed split tones at no extra GPU taps.
uniform vec3 shadow_tone = vec3(-0.012, 0.0, 0.025);
uniform vec3 highlight_tone = vec3(0.03, 0.015, -0.02);
uniform int blur_quality = 1; // 0: no blur, 1: 4 extra samples, 2: 8 extra samples.
uniform float sharpen_strength = 0.0; // High/Ultra only: local contrast enhancement of the sharp player band.

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
	// Native-resolution detail enhancement inspired by contrast-adaptive sharpening.
	// The focus mask never overlaps the tilt-shift blur: peripheral bokeh stays soft.
	// Performance/Balanced and adaptive Forward+ FSR2 skip all four extra taps.
	float sharp_focus = 1.0 - smoothstep(focus_width * 0.38, focus_width * 0.80,
		abs(uv.y - focus_center));
	if (sharpen_strength > 0.001 && sharp_focus > 0.001) {
		vec2 pixel = SCREEN_PIXEL_SIZE;
		vec3 left = texture(screen, clamp(uv - vec2(pixel.x, 0.0), vec2(0.0), vec2(1.0))).rgb;
		vec3 right = texture(screen, clamp(uv + vec2(pixel.x, 0.0), vec2(0.0), vec2(1.0))).rgb;
		vec3 up = texture(screen, clamp(uv - vec2(0.0, pixel.y), vec2(0.0), vec2(1.0))).rgb;
		vec3 down = texture(screen, clamp(uv + vec2(0.0, pixel.y), vec2(0.0), vec2(1.0))).rgb;
		vec3 average = (left + right + up + down) * 0.25;
		vec3 min_neighbor = min(color, min(min(left, right), min(up, down)));
		vec3 max_neighbor = max(color, max(max(left, right), max(up, down)));
		vec3 contrast = max_neighbor - min_neighbor;
		float local_contrast = max(contrast.r, max(contrast.g, contrast.b));
		// Suppress severe outlines, then clamp the result to the current 5-pixel range.
		float edge_limit = 1.0 - smoothstep(0.24, 0.70, local_contrast);
		vec3 enhanced = color + (color - average) * sharpen_strength * sharp_focus * edge_limit;
		color = clamp(enhanced, min_neighbor, max_neighbor);
	}
	// Split toning: shadows lean blue-teal, highlights lean warm gold.
	float luma = dot(color, vec3(0.299, 0.587, 0.114));
	vec3 toned = color + mix(shadow_tone, highlight_tone, smoothstep(0.2, 0.8, luma));
	// A soft S-curve for a little more depth.
	toned = mix(toned, toned * toned * (3.0 - 2.0 * toned), 0.18);
	color = mix(color, toned, grade);
	// Vignette.
	vec2 centered = uv - vec2(0.5, focus_center);
	float edge = smoothstep(0.45, 0.95, length(centered * vec2(1.0, 1.25)));
	color *= 1.0 - edge * vignette;
	COLOR = vec4(color, 1.0);
}
