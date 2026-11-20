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
* Feedback: banners for captured outposts and sieges, rings and bursts for restoration pulses, flashes, pinning bolts, knockback
  and smashed barricades; music stings on death, level-ups and victories.

* Cloud-shadow LUT: `scripts/client/cloud_shadow_lut.gd` bakes one seamless grayscale texture for coherent moving sun shadows on terrain, grass and trees. `atmosphere.gd` suppresses expensive cloud shading at night and in Performance mode.
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
