# Graphics quality (Godot 4)

The online client uses a configurable graphics profile. Press **Ctrl+F11** on the title screen or in-game to cycle **Performance → Balanced → High → Ultra**. The option persists in `user://albion_after_graphics.cfg`.

- **Performance**: FXAA, no dynamic sun shadow or tilt-shift blur.
- **Balanced** (default): FXAA, near sun shadows and 5-tap edge blur.
- **High**: 2× MSAA, farther shadows, 9-tap blur and glow where the renderer supports it.
- **Ultra**: 4× MSAA, longest shadows, enhanced bloom and SSAO on Forward+.

The desktop project now starts with the **Forward+** renderer; Mobile and Web default to Compatibility. Forward+-only effects (SSAO, SSIL, volumetric fog and SSR) are disabled gracefully when the running renderer does not support them. Game/network simulation and deterministic world generation are unchanged.

Grass tiles are already drawn as MultiMeshes. Their build-time CPU budget is reduced from 10 ms to 2.5 ms per frame across chunks to reduce hitching while streaming. A single tile may still exceed the budget because tile construction is synchronous.

Benchmark representative scenes at native 720p and 1080p on the target devices; compare frame-time percentiles, GPU time, and draw calls rather than inferring real FPS gains from shader sample counts.

## Rendering-aware improvements

Forward+ now uses FSR 2.2 at 0.59/0.77 scale for Performance/Balanced. Mobile uses FSR 1 spatial scaling; the default Compatibility renderer remains at native resolution, without unsupported temporal upscaling. High and Ultra use native resolution and their configured MSAA. Ultra optionally enables screen-space indirect lighting on Forward+ only.

The quality presets also tune the existing procedural grass LOD pipeline: streaming radius, shared per-frame build budget, and shader fade range. Switching quality updates the visibility range of already generated grass tiles without regenerating meshes. Compatible renderers and distant foliage must be visually verified on actual GPU hardware.


## Water shading budget

The water shader uses **analytic slopes from two crossing wave trains** rather than sampling a three-octave noise function at three nearby pixels to calculate its normal. The existing `water_ripples` preset still selects the detail budget:

- Performance (0.0): flat, inexpensive water normal and no animated foam noise; depth tint and Fresnel remain.
- Balanced (0.22): animated analytic wave normals and one shoreline-foam noise lookup.
- High/Ultra (0.35/0.48): the waves plus three microdetail-noise evaluations and up to two shore-foam noise evaluations.

The previous full ripple path used up to **11 calls to `value_noise` per water pixel** (3 octaves × 3 normal samples + 2 foam samples); the new high-detail path uses up to **5**, and the mid-tier uses **1**. These counts describe shader work, **not** measured FPS. Changes also add subtle emissive wave-crest highlights while preserving the original shoreline depth transitions.

For validation, capture the same water-heavy view and camera angle at the same time of day under each preset, warm up shader compilation, compare median/p95 GPU frame times, and inspect shallow-water foam and highlights during a storm and at dusk.

## Automatic graphics adjustment

The graphics selector includes **Auto (adapts to FPS)**. It starts at Balanced and changes between Performance, Balanced and High in response to sustained frame time, with 45/55 FPS hysteresis. It reduces detail after 3.5 seconds of low FPS and restores it after 9 seconds of good FPS. Single frames slower than 200 ms are ignored as likely loading stalls. **Ultra stays manual** to avoid uncontrolled GPU load. The automatic preference is stored alongside the manual level in `user://albion_after_graphics.cfg`; choosing a manual quality or Ctrl+F11 disables automation.

## Procedural terrain material LOD

When the 13-layer Poly Haven texture arrays are not installed, chunks render through the procedural `ChunkView.GROUND_SHADER` fallback. It now shares the same `aa_terrain_detail_radius` global uniform already used by textured terrain.

* Near the camera: high-frequency soil/pebble noise and fine mountain strata stay visible. Variations in dry soil roughness reuse the existing noise, without extra texture fetches.
* Over a 24-meter transition beyond the profile's terrain detail radius: fine detail fades to neutral values, while distant cliffs retain broad striation from the macro noise. Fine-noise evaluations and four-octave strata calculations are then skipped.
* Moving cloud shadows use the existing common cloud-field functions, but sample in the **vertex stage**, interpolating over terrain faces. This is a cheap approximation suitable for broad cloud shadows and the default OpenGL Compatibility renderer; it does not replace real-time directional shadows or contact AO.

The existing WorldGen seed, server authority and chunk geometry remain unchanged. These are shader-level changes only. Profile radii are 24 / 42 / 68 / 96 meters, with smooth 24-meter fade zones. Shader call counts and gains are theoretical until measured with the game running.

**Visual acceptance:** compare low/high presets around cliffs, roads, forests, rain puddles and snow transitions; sweep the camera slowly across the LOD radius looking for popping; inspect cloud alignment with grass, buildings and foliage. Benchmark p50/p95 GPU frame time in the same scene before interpreting the computational savings as actual FPS improvement.

## Foliage gust coherence and distance LOD

Nature-kit tree/bush meshes now keep their canopy motion spatially coherent: each MultiMesh instance derives a shared gust phase from its **root's world position**, with quadratic height weighting so trunks remain steadier than tips. An extra per-plant material-roughness variation makes repeated models react less uniformly to highlights without extra texture fetches.

The vertex shader smoothly reduces wind between **48 m and 120 m** from the camera and skips costly wind-wave trigonometry beyond that range. Each plant's colour variation now derives its second hash from the first rather than evaluating a second sine. This follows the broad practice of distance-aware detail and instanced variation in large-world terrain pipelines; it is deliberately implemented in Godot's existing ShaderMaterial/MultiMesh path rather than attempting to transplant Unreal Nanite.

The LOD is client-only and needs no changes to combat, collisions or server state. The regression suite checks the wind shader's budget gates and the conversion/caching of material-bearing meshes. Measure a dense nature scene on actual graphics hardware and watch for animation freezing near the 120 m threshold; the shader change itself does not establish a measured FPS improvement.

## Shared cloud occlusion and scenic LOD (November 2026)

The cloud shader now uses a **one-time 128×128 L8 tileable GPU texture** shared by terrain, grass and foliage, instead of computing three sine/hash fBM octaves for each fragment. Cloud contrast fades with nighttime and heavy storm cover; Performance disables the texture lookup altogether. No new CPU work occurs during normal frame rendering.

Quality levels also adjust the draw distance and imported mesh `lod_bias` for streamed **tree / rock / bush / decorative** MultiMeshes. Settlement structures remain uncapped. Existing batches update on the active preset change, without rebuilding world data. Dense decorative meshes already use the existing 32 m spatial partitions. See [CLOUD_HLOD_2026_11.md](CLOUD_HLOD_2026_11.md) for implementation, test commands, and the GPU benchmarking plan.

## Bounded terrain layer sampling

Based on Unreal Landscape layer blending and Unity Terrain Layers, the Poly Haven textured ground now selects only the strongest **2 / 3 / 4 / 13** layers per fragment on Performance / Balanced / High / Ultra. All 13 surfaces still participate in biome, road, snow and settlement weight calculations. The remaining layers contribute their existing artist-targeted average color, so limiting texture samples does not erase coastlines or the underlying biome palette.

The shader chooses the dominant weighted layers before making costly array texture fetches. Their PBR albedo and normal detail is sampled exactly as before; Ultra samples the entire blend for maximum visual fidelity. Cliff triplanar samples now use explicit gradients, preventing unstable mip selection within the conditional blending path. The new integer global `aa_terrain_layer_budget` is shared by all streamed terrain chunks and updated by the existing quality selector.

The palette approximation trades off subtle texture detail in weakly weighted layers on lower presets. It does not reduce the full weight calculation, so improvements must be confirmed with a GPU profile and 1% lows rather than assumed. Benchmark wooded trails, shorelines, ruined towns and cliffs at equal camera distance and weather; compare Ultra versus High to check blend quality and ensure there are no visible seams when ranked layers change.


## Imported foliage PBR preservation

The wind-animated nature kit now copies each imported `BaseMaterial3D` surface's **roughness, metallic, specular and opt-in vertex color** to its runtime `ShaderMaterial` instead of replacing all surfaces with a fixed roughness. For authored texture maps, the shader additionally preserves:

- `StandardMaterial3D` roughness and metallic texture channels (including non-red channel packing).
- `ORMMaterial3D` occlusion/roughness/metallic packing, sampled from a single texture as R/G/B.
- Normal maps and their strength, **only when the source surface has normals and tangents**; a missing tangent stream falls back to the imported vertex normal to avoid dark/invalid shading.

Optional PBR texture sampling (normal, roughness, metallic and packed ORM) fades smoothly between the per-preset `aa_terrain_detail_radius` and that distance plus 24 metres. Beyond the fade, the shader uses source material constants instead of fetching subpixel texture detail, saving bandwidth on distant foliage. Explicit texture derivatives are computed ahead of conditional samples to keep mip levels stable. The existing wind, storm wetness, alpha scissor, cloud-shadow alignment and MultiMesh color variation are retained. No gameplay collision, world seed or networking behavior changes.

This applies the same principle as layered HDRP materials: retain authored PBR response without paying full microdetail cost at a distance. It is **not** a clone of Unreal's Nanite or Unity HDRP. Validate dense trees and bushes, scanned nature meshes and fallback assets in daylight, wet weather and at night, and compare GPU frame-time percentiles on actual hardware. The source tests check texture bindings and channel masks but cannot replace a rendered screenshot or GPU benchmark.

Tests: `godot --headless --path game --script res://tests/run_all.gd`, including `test_foliage_wind_lod.gd`.

## Thin-leaf light transmission

Inspired by Unreal Engine's **Two Sided Foliage** and Unity HDRP's **Transmission**, the game's animated leaf material now writes Godot's native `BACKLIGHT` channel. Sunlight can pass gently through thin leaves instead of making the whole crown look opaque.

This shader-level approximation uses the existing leaf albedo, tint, alpha-cutout and direct lighting; **no screen-space blur, depth texture, ray tracing or additional texture sampling** is required. Leaf brightness creates a low-cost transmission mask, leaving dark veins less translucent. Only alpha-cutout nature surfaces enable the effect; bark, tree trunks and opaque geometry preserve their PBR shading. Existing wind, cloud shadows, wetness, normal/ORM maps and MultiMesh instancing remain unchanged.

A shared float `aa_leaf_transmission` is set by the existing quality profiles: **0.0 (Performance), 0.28 (Balanced), 0.48 (High), 0.68 (Ultra)**. The zero-strength Performance branch skips the leaf-mask calculation. The approximation uses Godot's built-in backlighting rather than full volumetric/subsurface scattering; it must be checked at dawn/dusk, in dense forests and in storms, on Forward+ and Compatibility backends.

For actual performance validation, compare GPU median/p95 frame time on representative forest views at identical time-of-day and leaf density. Counts of texture samples alone do not establish FPS gains.

## Cinematic, renderer-aware volumetric lighting

The live day/night/weather rig now creates a cheap low-level **height fog** on every renderer (including default Compatibility) and adds short-range, physically based **volumetric sunlight scattering** only on Forward+ High (48 m) and Ultra (72 m). Lower tiers and renderer fallbacks never allocate the volumetric pass. Density is clamped, smoothly animated with storms and low sun, and temporal reprojection is tuned to reduce ghosting. The existing shadow-cascade module uses the same shared fog policy instead of overriding its settings. See [CINEMATIC_FOG_RENDERING.md](CINEMATIC_FOG_RENDERING.md) for GPU budgets, testing and limitations.


## Budgeted screen-space reflections (Forward+)

The live `graphics_lighting.gd` pipeline now enables **Godot-native SSR** for the reflective parts of ruined settlements, worn pavement and rain-wet ground. This is a view-dependent specular reflection pass, not a replacement for the existing sky radiance/reflection fallback, and it does not affect translucent ocean water in the same way as opaque PBR surfaces.

| Tier | SSR pass | Max ray steps | Renderer |
| --- | --- | ---: | --- |
| Performance | Off | 0 | All |
| Balanced | Off | 0 | All |
| High | On | 24 | Forward+ only |
| Ultra | On | 48 | Forward+ only |

The defaults use the engine's normal **half-resolution SSR** setting to avoid a full-resolution screen-wide raymarch. Depth tolerance is 0.20 and edge fade-in/out are 0.14/1.8 to limit typical screen-edge artifacts. An unsupported backend, or a lower preset selected at runtime, immediately disables the SSR flag. The effect is applied only on quality changes, not on each gameplay frame.

This copies the *budgeting strategy*, not the renderer implementation, from HDRP-style screen-space reflections. Performance must be measured in the same scene at the same graphics scale with SSR off/High/Ultra, including wet ruined streets at sunset and indoor metallic equipment. Watch for screen-edge disappearance, ghost-like reflections and increased GPU frame time. SSR is a screen-space approximation and cannot reflect objects outside the camera view. The headless test suite checks profile limits, backend fallback and live property assignment; it cannot validate visual quality or actual GPU speed.

Reference: [Godot environment SSR documentation](https://docs.godotengine.org/en/4.5/tutorials/3d/environment_and_post_processing.html).

## MSAA leaf alpha-to-coverage (native resolution)

Like Unity HDRP alpha clipping, the animated cutout foliage material now has a shared **Alpha-to-Coverage** shader variant. This smooths hard silhouettes on sunlit tree crowns and bushes without adding draw calls, material texture samples or transparency sorting. Godot's spatial `alpha_to_coverage` render mode and `ALPHA_ANTIALIASING_EDGE`/`ALPHA_TEXTURE_COORDINATE` outputs are used in the variant, retaining the original `ALPHA_SCISSOR_THRESHOLD`, wet-leaf PBR and translucency logic.

**Important:** Coverage is enabled only when the actual viewport MSAA is active on a renderer that supports alpha-to-coverage (Forward+ or Vulkan Mobile). With the current graphics profiles, manually selected High/Ultra on Forward+ use 2x/4x MSAA, while Forward+ FSR2, dynamic resolution, and GL Compatibility continue to use the original efficient cutout shader. Runtime quality changes swap shared shader references on the already-cached meshes; imported materials, instances, collision and network state are untouched.

Check moving foliage against bright sky and strong directional backlight at 720p and 1080p. Look for reduced stair-stepping/shimmering, preserved cutout density (no see-through thinning), stable distant mip levels and unchanged shadow rendering. Actual GPU cost must be measured; no FPS improvement is implied by the shader change.
