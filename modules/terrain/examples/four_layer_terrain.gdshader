shader_type spatial;
render_mode cull_back, depth_draw_opaque;

// TerrainHeightmap writes four normalized splat weights into the vertex COLOR.
uniform sampler2D layer_0 : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D layer_1 : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D layer_2 : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D layer_3 : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float texture_tiles : hint_range(1.0, 128.0) = 16.0;
uniform float roughness : hint_range(0.0, 1.0) = 0.9;

varying vec4 splat_weights;

void vertex() {
    splat_weights = COLOR;
}

void fragment() {
    vec4 weights = max(splat_weights, vec4(0.0));
    float total = dot(weights, vec4(1.0));
    weights = total > 0.00001 ? weights / total : vec4(1.0, 0.0, 0.0, 0.0);

    vec2 tiled_uv = UV * texture_tiles;
    vec3 albedo =
            texture(layer_0, tiled_uv).rgb * weights.r +
            texture(layer_1, tiled_uv).rgb * weights.g +
            texture(layer_2, tiled_uv).rgb * weights.b +
            texture(layer_3, tiled_uv).rgb * weights.a;

    ALBEDO = albedo;
    ROUGHNESS = roughness;
}
