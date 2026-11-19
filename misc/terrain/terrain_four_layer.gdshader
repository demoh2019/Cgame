shader_type spatial;
render_mode cull_back, depth_draw_opaque;

// Sample shader for HeightmapTerrainMesh. Its COLOR channels are layer masks.
uniform sampler2D layer0 : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D layer1 : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D layer2 : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D layer3 : source_color, filter_linear_mipmap_anisotropic;
uniform vec2 texture_repeat = vec2(16.0, 16.0);

void fragment() {
	vec4 weights = max(COLOR, vec4(0.0));
	weights /= max(dot(weights, vec4(1.0)), 0.00001);
	vec2 tile_uv = UV * texture_repeat;
	ALBEDO =
			texture(layer0, tile_uv).rgb * weights.r +
			texture(layer1, tile_uv).rgb * weights.g +
			texture(layer2, tile_uv).rgb * weights.b +
			texture(layer3, tile_uv).rgb * weights.a;
	ROUGHNESS = 1.0;
}
