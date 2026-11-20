# Terrain noise LOD: move distant macro detail from pixels to vertices

The Albion After world terrain uses 13 photo-based PBR layers, weather effects,
biome/road masks, triplanar cliffs, near-puddle ripples and a 33×33 input
height grid per 64 m world chunk. The terrain already evaluates broad-scale
noise and cloud occlusion at vertices, but medium-frequency 3-octave noise
still ran in **every fragment**, including far terrain where details are
smaller than a screen pixel.

## Design

Taking inspiration from Unreal's distance-faded material details and
quality-dependent material cost, this update introduces a second
interpolated vertex noise field, `aa_vertex_mid`, for distant terrain.

- **Near the player (within `aa_terrain_detail_radius`):** the existing
  pixel-level 3-octave FBM produces the exact same authored material
  weights, moss, dirt, puddles, slope variation and roughness.
- **Between radius and radius + 24 m:** blend smoothly to vertex
  mid-frequency noise. The transition already exists for ground detail
  textures and normals, so terrain does not gain another LOD threshold.
- **Farther away:** a cheap interpolated varying replaces the costly
  pixel FBM. The pixel-level material tile-mixer noise is also skipped
  altogether, because its contribution is multiplied by the same
  zero detail factor.

This is **not** a new terrain draw pass, compute job, texture, or allocation.
No gameplay terrain, water, physics, world save, or server world generation
has changed. Shader derivatives remain outside dynamic branches so
textureGrad mip selection stays correct for nearby cliffs and ground.

## Visual and performance trade-offs

On distant, coarse meshes, interpolated mid-noise is intentionally smoother
than a fully sampled field; at a far camera distance this can reduce
moiré and over-detailed landscape colors. The per-vertex FBM does add
vertex ALU; expected benefits come when a terrain triangle covers many
pixels, so GPU p50/p95 timing is required to verify the result.

All four existing profiles independently control the effect through their
already registered `aa_terrain_detail_radius` budget:
Performance 24 m, Balanced 42 m, High 68 m, Ultra 96 m. No new settings
or texture variants to manage.

## Verification

Headless: `godot --headless --path game --script res://tests/run_all.gd`.
`test_terrain_noise_lod.gd` covers near/far bounds, smooth transition,
shared FBM frequency, stable gradient ordering, shader source wiring,
and weather/PBR coexistence.

Visual: use a reproducible camera walk/zoom over plains, roads, forest
and ruined sites at 720p and 1080p on Forward+ and Compatibility.
Check the 24 m blend for Performance and 96 m for Ultra, LOD transitions,
chunk borders, road edges, rain-puddle visibility and distant shimmer.
Compare median and p95 GPU frame times, plus vertex invocation counts;
no FPS improvements are claimed without a hardware run.

References:
- https://dev.epicgames.com/documentation/unreal-engine/adding-detail-textures-to-unreal-engine-materials
- https://dev.epicgames.com/documentation/en-us/unreal-engine/scalability-reference-for-unreal-engine
- https://docs.godotengine.org/en/stable/tutorials/shaders/introduction_to_shaders.html
