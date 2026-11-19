shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform sampler2D layer_0 : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D layer_1 : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D layer_2 : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D layer_3 : source_color, filter_linear_mipmap, repeat_enable;
uniform float texture_repeat = 12.0;
uniform vec4 tint_0 : source_color = vec4(0.37, 0.54, 0.28, 1.0);
uniform vec4 tint_1 : source_color = vec4(0.55, 0.37, 0.19, 1.0);
uniform vec4 tint_2 : source_color = vec4(0.58, 0.59, 0.61, 1.0);
uniform vec4 tint_3 : source_color = vec4(0.92, 0.92, 0.96, 1.0);

void fragment() {
	vec4 weights = max(COLOR, vec4(0.0));
	float total = dot(weights, vec4(1.0));
	weights = total > 0.00001 ? weights / total : vec4(1.0, 0.0, 0.0, 0.0);
	vec2 uv = UV * texture_repeat;
	vec3 albedo = texture(layer_0, uv).rgb * tint_0.rgb * weights.r;
	albedo += texture(layer_1, uv).rgb * tint_1.rgb * weights.g;
	albedo += texture(layer_2, uv).rgb * tint_2.rgb * weights.b;
	albedo += texture(layer_3, uv).rgb * tint_3.rgb * weights.a;
	ALBEDO = albedo;
	ROUGHNESS = 0.9;
}