shader_type spatial;
render_mode cull_back;

uniform vec4 tint_0 : source_color = vec4(0.37, 0.47, 0.24, 1.0);
uniform vec4 tint_1 : source_color = vec4(0.45, 0.36, 0.27, 1.0);
uniform vec4 tint_2 : source_color = vec4(0.53, 0.51, 0.48, 1.0);
uniform vec4 tint_3 : source_color = vec4(0.82, 0.79, 0.65, 1.0);
uniform sampler2D texture_0 : source_color, repeat_enable;
uniform sampler2D texture_1 : source_color, repeat_enable;
uniform sampler2D texture_2 : source_color, repeat_enable;
uniform sampler2D texture_3 : source_color, repeat_enable;
uniform bool use_texture_0 = false;
uniform bool use_texture_1 = false;
uniform bool use_texture_2 = false;
uniform bool use_texture_3 = false;

void fragment() {
	vec4 weights = max(COLOR, vec4(0.0));
	float sum = dot(weights, vec4(1.0));
	weights = sum > 0.00001 ? weights / sum : vec4(1.0, 0.0, 0.0, 0.0);
	vec3 c0 = tint_0.rgb;
	vec3 c1 = tint_1.rgb;
	vec3 c2 = tint_2.rgb;
	vec3 c3 = tint_3.rgb;
	if (use_texture_0) { c0 *= texture(texture_0, UV).rgb; }
	if (use_texture_1) { c1 *= texture(texture_1, UV).rgb; }
	if (use_texture_2) { c2 *= texture(texture_2, UV).rgb; }
	if (use_texture_3) { c3 *= texture(texture_3, UV).rgb; }
	ALBEDO = c0 * weights.r + c1 * weights.g + c2 * weights.b + c3 * weights.a;
	ROUGHNESS = 0.94;
}
