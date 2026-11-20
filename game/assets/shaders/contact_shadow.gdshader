shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

// Cheap analytical soft grounding shadows for the existing animated actors.
// All actors share ONE instanced draw with custom opacity; no depth samples,
// filtered shadow-map lookups, textures, lighting passes or CPU-generated images.
varying float instance_opacity;

void vertex() {
	instance_opacity = clamp(INSTANCE_CUSTOM.r, 0.0, 1.0);
}

void fragment() {
	vec2 centered = UV * 2.0 - vec2(1.0);
	// Elliptical, smooth penumbra. The fragment outside the footprint is
	// transparent without an expensive smooth texture fetch.
	float r2 = dot(centered, centered);
	float contact = pow(max(1.0 - r2, 0.0), 2.1);
	ALBEDO = vec3(0.019, 0.025, 0.032);
	ALPHA = instance_opacity * contact;
}
