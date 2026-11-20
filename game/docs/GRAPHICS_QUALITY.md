# Graphics quality (Godot 4)

The online client uses a configurable graphics profile. Press **Ctrl+F11** on the title screen or in-game to cycle **Performance → Balanced → High → Ultra**. The option persists in `user://albion_after_graphics.cfg`.

- **Performance**: FXAA, no dynamic sun shadow or tilt-shift blur.
- **Balanced** (default): FXAA, near sun shadows and 5-tap edge blur.
- **High**: 2× MSAA, farther shadows, 9-tap blur and glow where the renderer supports it.
- **Ultra**: 4× MSAA, longest shadows, enhanced bloom and SSAO on Forward+.

The project remains on the Compatibility renderer. SSAO and glow can be unavailable there; these flags take effect with a compatible Forward+ build. Game/network simulation and deterministic world generation are unchanged.

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
