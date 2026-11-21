shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform vec3 leaf_dark : source_color = vec3(0.045, 0.16, 0.10);
uniform vec3 leaf_light : source_color = vec3(0.18, 0.38, 0.18);
uniform float wind_strength : hint_range(0.0, 0.4) = 0.095;
uniform float wind_speed : hint_range(0.0, 4.0) = 1.18;

varying float tint_factor;

void vertex() {
    tint_factor = INSTANCE_CUSTOM.g;
    float phase = TIME * wind_speed + INSTANCE_CUSTOM.r * 6.283185;
    // Animate only the outer part of each canopy. Trunk bases do not move.
    float tip = smoothstep(-0.55, 0.75, VERTEX.y);
    VERTEX.x += sin(phase + VERTEX.x * 2.1) * wind_strength * tip;
    VERTEX.z += cos(phase * 0.77 + VERTEX.z * 1.7) * wind_strength * tip;
}

void fragment() {
    ALBEDO = mix(leaf_dark, leaf_light, clamp(tint_factor, 0.0, 1.0));
    ROUGHNESS = 0.88;
    SPECULAR = 0.23;
}
