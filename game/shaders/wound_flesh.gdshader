shader_type spatial;
// Openable body surface, after Valve's L4D2 wound technique (ellipsoid cut-outs) and the
// layered-anatomy idea of Dead Island 2's FLESH:
//  * every wound is a channel along the strike: inside it the skin is cut away, around it the
//    skin sinks into a crater whose wall shows torn skin -> yellow fat -> striated red muscle;
//  * through the opening you see the body's inside (back faces) as wet muscle;
//  * dismemberment cuts by BONE WEIGHTS: cut_mode 1 removes the masked limb from the body,
//    cut_mode 2 keeps ONLY that limb (the flying piece) — no bone scaling, so no stretching.
// Wounds live in the mesh's local (skinned) space and are refreshed from their bones by wound_fx.gd.
render_mode cull_disabled;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap, repeat_enable;
uniform vec4 albedo_color : source_color = vec4(1.0);
uniform float has_albedo_tex = 0.0;
uniform float has_normal_tex = 0.0;
uniform float alpha_scissor = -1.0; // >= 0 for hair/cloth cards that cut out by texture alpha.
uniform vec3 uv_scale = vec3(1.0);
uniform vec3 uv_offset = vec3(0.0);
uniform float base_roughness = 0.8;
uniform float base_metallic = 0.0;
uniform vec4 muscle_color : source_color = vec4(0.42, 0.04, 0.05, 1.0);
uniform vec4 fat_color : source_color = vec4(0.86, 0.72, 0.42, 1.0);
uniform vec4 deep_color : source_color = vec4(0.12, 0.0, 0.01, 1.0);
uniform vec4 flash_color : source_color = vec4(1.0, 0.96, 0.9, 1.0);
uniform float flash_energy = 0.0;
uniform int wound_count = 0;
uniform vec4 wounds[8];     // xyz centre (local), w hole radius
uniform vec4 wound_axes[8]; // xyz cut axis (local, unit), w elongation along it (1 = round hole)
uniform vec4 wound_dirs[8]; // xyz strike direction (local, unit), w dent depth
uniform int cut_mode = 0;   // 0 none, 1 hide masked bones (body), 2 show only masked bones (piece)
uniform int cut_mask[5];    // Bone indices in the severed limb, 30 bits per word (150 bones).

varying vec3 local_pos;
varying float cut_weight;

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

bool in_mask(uint bone) {
	int b = int(bone);
	int word = b / 30;
	return word < 5 && ((cut_mask[word] >> (b % 30)) & 1) == 1;
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void vertex() {
	local_pos = VERTEX;
	cut_weight = 0.0;
	if (cut_mode != 0) {
		for (int k = 0; k < 4; k++) {
			if (in_mask(BONE_INDICES[k])) {
				cut_weight += BONE_WEIGHTS[k];
			}
		}
	}
	for (int i = 0; i < wound_count; i++) {
		float m = wound_metric(VERTEX, i);
		if (m < 2.6) {
			float sink = (1.0 - smoothstep(0.5, 2.6, m)) * wound_dirs[i].w;
			VERTEX += wound_dirs[i].xyz * sink;
		}
	}
}

// Striated muscle: fibres along local y with wet highlights.
vec3 muscle(vec3 p, float shade) {
	float fibre = 0.55 + 0.45 * sin(p.y * 260.0 + hash(floor(p.xz * 90.0)) * 6.28);
	return mix(deep_color.rgb, muscle_color.rgb, shade) * (0.75 + 0.35 * fibre);
}

void fragment() {
	if (cut_mode == 1 && cut_weight > 0.5) {
		discard; // Severed: this limb is no longer part of the body.
	}
	if (cut_mode == 2 && cut_weight < 0.5) {
		discard; // The flying piece keeps only the limb.
	}
	vec2 uv = UV * uv_scale.xy + uv_offset.xy;
	vec4 base = albedo_color;
	if (has_albedo_tex > 0.5) {
		base *= texture(albedo_tex, uv);
	}
	if (alpha_scissor >= 0.0 && base.a < alpha_scissor) {
		discard;
	}
	float nearest = 99.0;
	for (int i = 0; i < wound_count; i++) {
		nearest = min(nearest, wound_metric(local_pos, i));
	}
	// Near a severing line the inside shows as a fresh cut face.
	float cut_edge = cut_mode != 0 ? 1.0 - smoothstep(0.0, 0.07, abs(cut_weight - 0.5)) : 0.0;
	if (nearest < 1.0 && FRONT_FACING) {
		discard; // The opening itself.
	}
	if (!FRONT_FACING) {
		// The inside of the body seen through a wound or a stump: wet, striated muscle.
		float lip = max(1.0 - smoothstep(1.0, 2.4, nearest), cut_edge);
		ALBEDO = muscle(local_pos, 0.35 + 0.65 * lip);
		ROUGHNESS = 0.22;
		SPECULAR = 0.65;
	} else {
		// Crater wall from the hole outward: muscle, a band of fat, the torn skin lip, then
		// skin soaked with blood.
		float t = clamp((nearest - 1.0) / 0.6, 0.0, 1.0);
		vec3 wall = muscle(local_pos, 1.0);
		wall = mix(wall, fat_color.rgb, smoothstep(0.25, 0.45, t) * (1.0 - smoothstep(0.55, 0.7, t)));
		wall = mix(wall, muscle_color.rgb * 0.8, smoothstep(0.65, 0.8, t));
		float soak = 1.0 - smoothstep(1.0, 3.4, nearest);
		vec3 skin = mix(base.rgb, base.rgb * vec3(0.5, 0.1, 0.08), soak * 0.85);
		float crater = 1.0 - smoothstep(0.85, 1.0, t);
		ALBEDO = mix(skin, wall, crater);
		ALBEDO = mix(ALBEDO, muscle_color.rgb, cut_edge * 0.8);
		ROUGHNESS = mix(base_roughness, 0.16, max(crater, max(soak * 0.7, cut_edge)));
		METALLIC = base_metallic * (1.0 - crater);
		if (has_normal_tex > 0.5) {
			NORMAL_MAP = texture(normal_tex, uv).rgb;
		}
	}
	EMISSION = flash_color.rgb * flash_energy;
}
