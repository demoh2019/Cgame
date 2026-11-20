// Client-only plant interaction: the player (or any mover) pushes grass and bushes aside, and a hit or harvested
// plant shakes. Both are single global vec4s (x, z, radius, strength) written by plant_interaction.gd; strength 0
// costs one comparison. World-space result, project it to local space with aa_wind_world_to_local_xz.
global uniform vec4 aa_plant_bend;
global uniform vec4 aa_plant_shake;

vec2 aa_plant_displacement(vec2 root, float height_k, float time) {
	vec2 result = vec2(0.0);
	if (aa_plant_bend.w > 0.001) {
		vec2 away = root - aa_plant_bend.xy;
		float dist = length(away);
		float falloff = 1.0 - smoothstep(0.0, max(aa_plant_bend.z, 0.01), dist);
		result += (away / max(dist, 0.001)) * falloff * aa_plant_bend.w * height_k;
	}
	if (aa_plant_shake.w > 0.001) {
		float falloff = 1.0 - smoothstep(0.0, max(aa_plant_shake.z, 0.01), length(root - aa_plant_shake.xy));
		vec2 osc = vec2(sin(time * 17.0 + root.x * 3.1), cos(time * 13.0 + root.y * 2.3));
		result += osc * falloff * aa_plant_shake.w * height_k;
	}
	return result;
}

// Objects resting in the grass (campfires, shelters, walls, bags, traps, other walkers): up to 8 nearby
// footprints (x, z, radius, strength) chosen on the CPU. Blades inside are squashed flat instead of growing
// through the object. aa_plant_crush_count = 0 costs a single comparison.
global uniform float aa_plant_crush_count;
global uniform vec4 aa_plant_crush_0;
global uniform vec4 aa_plant_crush_1;
global uniform vec4 aa_plant_crush_2;
global uniform vec4 aa_plant_crush_3;
global uniform vec4 aa_plant_crush_4;
global uniform vec4 aa_plant_crush_5;
global uniform vec4 aa_plant_crush_6;
global uniform vec4 aa_plant_crush_7;

float aa_plant_crush_one(vec2 root, vec4 c) {
	if (c.w <= 0.001) {
		return 0.0;
	}
	float d = length(root - c.xy);
	return (1.0 - smoothstep(c.z * 0.75, c.z * 1.15, d)) * c.w;
}

// 0 = untouched, 1 = flattened to the ground.
float aa_plant_crush(vec2 root) {
	if (aa_plant_crush_count < 0.5) {
		return 0.0;
	}
	float f = aa_plant_crush_one(root, aa_plant_crush_0);
	f = max(f, aa_plant_crush_one(root, aa_plant_crush_1));
	f = max(f, aa_plant_crush_one(root, aa_plant_crush_2));
	f = max(f, aa_plant_crush_one(root, aa_plant_crush_3));
	if (aa_plant_crush_count > 4.5) {
		f = max(f, aa_plant_crush_one(root, aa_plant_crush_4));
		f = max(f, aa_plant_crush_one(root, aa_plant_crush_5));
		f = max(f, aa_plant_crush_one(root, aa_plant_crush_6));
		f = max(f, aa_plant_crush_one(root, aa_plant_crush_7));
	}
	return clamp(f, 0.0, 1.0);
}
