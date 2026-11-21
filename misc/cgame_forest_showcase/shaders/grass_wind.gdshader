shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform vec3 grass_base : source_color = vec3(0.055, 0.15, 0.045);
uniform vec3 grass_tips : source_color = vec3(0.29, 0.37, 0.10);
uniform float speed = 1.7;

varying float height_mask;

void vertex() {
    height_mask = clamp(UV.y, 0.0, 1.0);
    float sway = sin(TIME * speed + INSTANCE_CUSTOM.r * 6.28 + VERTEX.x * 5.0);
    VERTEX.x += sway * height_mask * height_mask * 0.13;
}

void fragment() {
    ALBEDO = mix(grass_base, grass_tips, height_mask * (0.75 + INSTANCE_CUSTOM.g * 0.25));
    ROUGHNESS = 1.0;
    SPECULAR = 0.2;
}
