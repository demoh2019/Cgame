shader_type spatial;
render_mode cull_back, depth_draw_opaque;

uniform vec4 ground_color : source_color = vec4(0.25, 0.38, 0.19, 1.0);
uniform vec4 detail_color : source_color = vec4(0.45, 0.38, 0.31, 1.0);
uniform sampler2D ground_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D detail_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform bool use_ground_texture = false;
uniform bool use_detail_texture = false;
uniform float uv_repeats : hint_range(0.01, 128.0) = 4.0;

void fragment() {
    vec3 a = ground_color.rgb;
    vec3 b = detail_color.rgb;
    if (use_ground_texture) {
        a *= texture(ground_texture, UV * uv_repeats).rgb;
    }
    if (use_detail_texture) {
        b *= texture(detail_texture, UV * uv_repeats).rgb;
    }
    ALBEDO = mix(a, b, clamp(COLOR.r, 0.0, 1.0));
    ROUGHNESS = 0.9;
}