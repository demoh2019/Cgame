shader_type spatial;
// A body surface that can be opened: around each wound the skin is pushed in, the centre is
// cut away (discard), and the inside of the hollow body shows through as raw flesh, so a stab
// reads as a real hole and a slash as a gaping cut. Wounds are ellipsoids in the mesh's local
// (skinned) space, refreshed from their bones every frame by wound_fx.gd.
render_mode cull_disabled;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap, repeat_enable;
uniform vec4 albedo_color : source_color = vec4(1.0);
uniform float has_albedo_tex = 0.0;
uniform float has_normal_tex = 0.0;
uniform vec3 uv_scale = vec3(1.0);
uniform vec3 uv_offset = vec3(0.0);
uniform float base_roughness = 0.8;
uniform float base_metallic = 0.0;
uniform vec4 flesh_color : source_color = vec4(0.36, 0.03, 0.03, 1.0);
uniform vec4 deep_color : source_color = vec4(0.09, 0.0, 0.0, 1.0);
uniform vec4 flash_color : source_color = vec4(1.0, 0.96, 0.9, 1.0);
uniform float flash_energy = 0.0;
uniform int wound_count = 0;
uniform vec4 wounds[8];     // xyz centre (local), w hole radius
uniform vec4 wound_axes[8]; // xyz cut axis (local, unit), w elongation along it (1 = round hole)
uniform vec4 wound_dirs[8]; // xyz strike direction (local, unit), w dent depth

varying vec3 local_pos;

// A wound is a channel along the strike line: wherever that line crosses the skin, it opens.
// Cross-section is an ellipse (long along the cut axis); the channel ends a little past the bone.
float wound_metric(vec3 p, int i) {
	vec3 offset = p - wounds[i].xyz;
	vec3 dir = wound_dirs[i].xyz;
	float depth = dot(offset, dir);
	if (depth < -0.35 || depth > 0.12) {
		return 99.0;
	}
	vec3 flat_offset = offset - dir * depth;
	vec3 axis = wound_axes[i].xyz;
	float along = dot(flat_offset, axis);
	vec3 across = flat_offset - axis * along;
	float r = max(wounds[i].w, 0.001);
	return sqrt(pow(along / (r * wound_axes[i].w), 2.0) + dot(across, across) / (r * r));
}

void vertex() {
	local_pos = VERTEX; // Measure openings on the undisturbed skin, then sink it.
	for (int i = 0; i < wound_count; i++) {
		float m = wound_metric(VERTEX, i);
		if (m < 2.4) {
			// Skin sinks toward the hole along the strike: a crater, deepest at the edge of the cut.
			float sink = (1.0 - smoothstep(0.6, 2.4, m)) * wound_dirs[i].w;
			VERTEX += wound_dirs[i].xyz * sink;
		}
	}
}

void fragment() {
	vec2 uv = UV * uv_scale.xy + uv_offset.xy;
	vec4 base = albedo_color;
	if (has_albedo_tex > 0.5) {
		base *= texture(albedo_tex, uv);
	}
	float nearest = 99.0;
	for (int i = 0; i < wound_count; i++) {
		nearest = min(nearest, wound_metric(local_pos, i));
	}
	if (nearest < 1.0 && FRONT_FACING) {
		discard; // The opening itself.
	}
	if (!FRONT_FACING) {
		// The inside of the body, seen through an opening: dark, wet meat.
		float lip = 1.0 - smoothstep(1.0, 2.2, nearest);
		ALBEDO = mix(deep_color.rgb, flesh_color.rgb, lip * 0.6);
		ROUGHNESS = 0.25;
		SPECULAR = 0.6;
	} else {
		// Raw torn rim, then blood soaking into the skin around it.
		float rim = 1.0 - smoothstep(1.0, 1.35, nearest);
		float soak = 1.0 - smoothstep(1.0, 3.2, nearest);
		vec3 skin = mix(base.rgb, base.rgb * vec3(0.55, 0.12, 0.1), soak * 0.85);
		ALBEDO = mix(skin, flesh_color.rgb * 1.3, rim);
		ROUGHNESS = mix(base_roughness, 0.18, max(rim, soak * 0.7));
		METALLIC = base_metallic;
		if (has_normal_tex > 0.5) {
			NORMAL_MAP = texture(normal_tex, uv).rgb;
		}
	}
	EMISSION = flash_color.rgb * flash_energy;
}
