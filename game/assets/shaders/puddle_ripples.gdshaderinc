// Camera-local rain impact rings for shallow puddles. The same world-space
// coordinates produce the same ring across neighboring streamed chunks.
// No textures, particles, memory allocation, scene nodes or CPU per-frame work.
// Called ONLY for nearby wet, puddled pixels by the terrain's quality-gated branch.
// Ring dies inside its 2.6-metre cell, so no seams are visible at the cell edges.
vec2 aa_puddle_ripple_tilt(vec2 world_xz, float seconds) {
	const float CELL = 2.6;
	vec2 cell = floor(world_xz / CELL);
	// Arithmetic world-space hash. No trigonometry and no texture read.
	vec2 h = fract(cell * vec2(0.1031, 0.11369));
	h += vec2(dot(h, h.yx + vec2(19.19)));
	float phase = fract(h.x * h.y);
	// Small position jitter prevents a visible checkerboard of identical
	// drop centres. Max offset is 0.1m; waves fade by radius 1.18m,
	// before the nearest possible tile edge (1.2m).
	vec2 jitter = (vec2(phase, fract(phase * 7.37 + 0.19))
		- vec2(0.5)) * 0.20;
	vec2 center = (cell + vec2(0.5)) * CELL + jitter;
	vec2 offset = world_xz - center;
	float distance_from_drop = length(offset);
	// One spreading ring per cell. Different cells begin at different times.
	float age = fract(seconds * 0.67 + phase);
	float radius = age * 1.08;
	float ring = 1.0 - smoothstep(0.028, 0.14, abs(distance_from_drop - radius));
	// Fully zero by 1.18m; cell half width is 1.3m.
	float edge_fade = 1.0 - smoothstep(0.85, 1.18, distance_from_drop);
	return offset / max(distance_from_drop, 0.025)
		* ring * edge_fade * (1.0 - age) * 0.18;
}
