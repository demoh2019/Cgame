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
