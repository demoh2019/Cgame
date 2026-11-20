# How the game looks

* `scripts/client/atmosphere.gd`: procedural sky with a day/night/dusk/storm palette, a warm low sun and a blue moon, ACES tone mapping,
  glow, contrast, aerial fog, and a directional light with soft shadows that follow the camera (trees, houses and walls cast them).
  Compatibility renderer by default (it runs everywhere); SSAO is switched on for Forward+, see below.
* `assets/shaders/water.gdshader`: sea with depth-based colour, a foam line along the shore, scrolling ripples and a Fresnel sheen.
* `assets/shaders/ground.gdshader`: photographed ground (Poly Haven, CC0) blended from the biome map, height, slope and the road mask,
  each layer read at two scales so the tiling never shows; cracked asphalt under ruined cities and broken concrete under bunkers and
  depots, with weeds coming up through it. Without the textures, the painted noise shader in `chunk_view.gd` draws the ground.
* `scripts/client/hub_view.gd`: the hub plaza is cobblestone whose rim frays into the grass; the fountain is re-skinned as stone.
* Title screen: the sky panorama behind a vignette, the name in gold, the sign-in card (Enter submits).
* `scripts/client/foliage.gd`: trees, bushes, grass and ferns sway in the wind (a vertex shader that keeps the pack's textures).
* `scripts/client/effects.gd`: particles for hits, deaths, muzzle flashes, gathering, loot, level-ups, dust from running, and rain that
  follows the camera during storms (not under the settlement roofs).
* `scripts/client/ui_theme.gd`: one theme for the HUD: outlined text, rounded dark panels with a gold edge, rounded bars and buttons.

Screenshot a time of day: `... online_main.tscn -- --connect ... --demo forest --phase 0.22` (0 sunrise, 0.25 noon, 0.5 sunset, 0.75 midnight), `--storm` for rain.

Forward+ (`--rendering-method forward_plus`) adds SSAO but made the first frames stall for 3-4 s here (shader compilation), long enough for
the server to drop the connection, so it is not the default.

* Living world: cloud shadows (`assets/shaders/cloud_shadow.gdshaderinc`) on the ground, grass and foliage; pollen, butterflies,
  falling leaves and fireflies around the player (`effects.gd` `update_ambience`); moonlit nights; a diorama post pass under the
  HUD (`assets/shaders/post_grade.gdshader`: tilt-shift, split toning, vignette).
* Grass: `scripts/client/grass_field.gd`, a procedural carpet of thin blades in Voronoi patches of short, knee-high and tall
  grass, grown tile by tile near the camera. `chunk_view.gd` selects one of three cached geometry LODs every 0.35 s:
  18 blades per tuft nearby, 9 at medium range and 4 at the far edge. The transitions use 3 m of hysteresis.
  Close-up grass, coloring, wind and fading are unchanged. The medium and far meshes have 50% and ~78% fewer triangles
  per tuft; this reduces geometry cost, not pixel shading cost. Regression: `tests/test_grass_lod.gd`. Profile GPU frame
  time in forests and meadows before claiming an FPS increase.
* Screen-space grass quality: the game now scales its three cached LOD meshes **and**
  the existing distant-instance density from the camera's projected pixel budget:
  vertical FOV, viewport height, active 3D render scale (FSR2 where supported)
  and the selected graphics preset's grass fade range. The previous distance-only
  transition remains the 720p/38-degree reference. Narrow-angle/high-resolution
  views keep blade silhouettes farther away; Performance and low-resolution views
  thin grass earlier instead of burning vertices on subpixel plants. Extra geometry
  is capped at a 15% increase beyond each preset's fade-range budget, and mesh
  switches retain hysteresis. Nothing touches server gameplay, chunk placement
  or VRAM texture allocations. `tests/test_grass_lod.gd` checks screen-space
  behavior and density bounds. GPU/visual benchmark still required before
  quantifying frame-rate improvements. Tile LOD recalculation is also skipped
  for stationary cameras until they move at least 25 cm, a new tile appears,
  or the quality/FOV/pixel budget changes; wind remains GPU-animated.
* Native engine pixel-density LOD: our Godot fork adds
  `Camera3D.get_pixels_per_meter_at_position(world_point)` (C++ scene camera API).
  Grass in `chunk_view.gd` uses the actual camera projection and per-tile depth
  for smooth, angle/zoom/height-aware mesh and density selection. A conservative
  40% horizontal-distance mix retains the original grass-carpet composition.
  4K pixel budgets are bounded; native query work is amortized by the existing
  0.35s refresh and camera-motion cache. Upstream Godot safely keeps the old
  FOV/distance algorithm. The engine API, game integration and profiling recipe
  are detailed in `docs/CAMERA_SCREEN_SPACE_LOD.md`. Regression:
  `tests/test_camera_pixel_density.gd`.
* Feedback: banners for captured outposts and sieges, rings and bursts for restoration pulses, flashes, pinning bolts, knockback
  and smashed barricades; music stings on death, level-ups and victories.

* Cloud-shadow LUT: `scripts/client/cloud_shadow_lut.gd` bakes one seamless grayscale texture for coherent moving sun shadows on terrain, grass and trees. `atmosphere.gd` suppresses expensive cloud shading at night and in Performance mode.
* Directional sun shadow atlas: `scripts/client/graphics_shadow_atlas.gd` reuses
  Godot's single native directional shadow texture. Performance reserves 1024
  (sun shadows remain disabled); Balanced uses 2048/16-bit; High Forward+ uses
  4096/16-bit; Ultra Forward+ keeps 4096 but requests higher depth precision
  (32-bit) to reduce long-distance shadow acne. Compatibility/Mobile cap the
  atlas at 2048/16-bit. Texture and memory costs remain bounded and the atlas
  is changed only when the resolved preset/backend budget changes, not per frame.
  This complements existing PSSM splits, shadow-caster LOD, weather penumbrae
  and contact shadows without additional lights or full-screen passes.
  `project.godot` defaults to the Balanced 2048/16-bit atlas for startup.
  Regression: `tests/test_graphics_shadow_atlas.gd`. Validate actual GPU
  shadow aliasing and frame time on target GPUs before claiming a measured FPS
  improvement; Ultra necessarily uses more shadow depth memory.
* Terrain texture anisotropy: `scripts/client/terrain_anisotropy.gd` creates and caches sampler variants of
  the exact same 13-layer PBR ground shader. Performance/Balanced keep the original trilinear
  color and normal sampling; High switches only ground albedo to up to 8x anisotropic sampling
  (clearer roads and soil at an oblique isometric angle); Ultra also enables anisotropic
  ground normal maps. The expensive sampler budget is configured once at application startup
  by `project.godot`, but is active only in the selected shader variants. Existing streamed
  chunks swap shaders on quality changes while retaining their biome/road textures,
  patch layout, shared texture arrays and calibrated layer colors. No new geometry,
  additional passes, texture loading or VRAM texture copies are required. Variant
  compilation may occur on the first High/Ultra transition, so warm it up for
  benchmarks and compare GPU time before/after at oblique terrain viewpoints.
  Regression coverage: `tests/test_terrain_anisotropy.gd`.
* Scenery draw-range/mesh LOD: `scripts/client/scenery_lod.gd` and `chunk_view.gd` adjust visual culling and imported mesh LOD bias by graphics quality without hiding settlement landmarks or changing server gameplay. See `docs/CLOUD_HLOD_2026_11.md`.

* Camera-scale atmospheric fog: `scripts/client/cinematic_fog.gd` adds an inexpensive sea-level height haze to all supported renderers, and bounded physically based Forward+ volumetric shafts on High/Ultra. The same engine-native `Atmosphere` and `GraphicsLighting` now share one time-of-day, storm and quality budget; see `docs/CINEMATIC_FOG_RENDERING.md`.

* Instanced atmospheric detail: `scripts/client/ambient_motes.gd` and `assets/shaders/ambient_motes.gdshader` render light-catching pollen in clear daylight and golden forest/swamp fireflies at night, with weather, regional wind, stable seeded world tiles and four GPU-quality budgets. A single MultiMesh handles all visible motes in both clients. See `docs/ATMOSPHERIC_MOTES.md`.
* Screen-pixel atmospheric motes: the Cgame engine adds
  `Camera3D.get_world_size_for_pixel_diameter_at_position()`. `AmbientMotes`
  calibrates one world-to-pixel size every 0.25 seconds, then its existing GPU
  shader scales every pollen/firefly quad with depth to retain a narrow 3–4 px
  cinematic halo across camera zoom. FSR2 retains at least 1.75 internal pixels
  and extreme sizes are bounded. This replaces the former 1-meter glow cards
  without extra particles, draw calls or textures. Stock Godot keeps the
  FOV-based GDScript fallback; full details in `docs/SCREEN_SPACE_ATMOSPHERIC_MOTES.md`.

* Shallow-water light transport and RD renderer correctness: `assets/shaders/water.gdshader` now adds subtle, physically inspired underwater solar scattering using the existing depth transmission and real cached sun direction. Native Godot `servers/rendering/renderer_rd/storage_rd/mesh_storage.cpp` fixes re-showing dirty hidden MultiMesh instances on `visible_instance_count = -1`. See `docs/ENGINE_MULTIMESH_WATER_SCATTERING.md`.

* Ocean sun path and efficient weather fog: `assets/shaders/water.gdshader` produces subtle golden reflections from the existing animated wave normals using sky-cached sunlight, premium Forward+ only. `scripts/client/cinematic_fog.gd` sends a single fog transaction to our native `Environment.configure_weather_fog` when available; stock Godot falls back to the same property changes. See `docs/ATOMIC_WEATHER_FOG_OCEAN_GLITTER.md`.
