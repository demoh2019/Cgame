# Albion After — cloud-shadow LUT and scalable scenery LOD

This is integrated into the canonical `game/` client, not a rendering
mockup. The new visual systems leave dedicated-server simulation, physics,
loot, navigation and account saves unchanged. **GPU frame-time improvements
have not been measured; benchmark on target devices before assigning FPS
numbers.**

## Techniques applied from other engines

- **Unreal Engine HLOD/Nanite:** aggressively reduce far-away geometry
  and group distant instances rather than sending all high-detail assets
  to the GPU. This implementation is **not Nanite**: Godot keeps imported
  mesh LODs, existing MultiMeshes and visibility-range culling.
- **Unity GPU instancing and LODGroup:** draw repeated vegetation in
  batches and choose detail by view distance. Our `ChunkView` already
  instances scenery by mesh, and `SceneryBatches` partitions dense
  decoration into smaller, cullable cells. We now scale each scene
  instance's `lod_bias` and draw range with the current graphics preset.
- **Godot 4.7 shader globals:** replace expensive repeated per-pixel
  fBM noise with a single shared cached texture, so terrain, grass and
  trees show one coherent, drifting cloud-shadow pattern.

## Cloud shadow texture

`scripts/client/cloud_shadow_lut.gd` generates a **128 × 128, single-channel
L8** tileable cloud field once, from three deterministic value-noise
frequencies. The game uploads it to a global GPU shader texture only
once per client session. `assets/shaders/cloud_shadow.gdshaderinc`
now performs **one filtered lookup per fragment**, instead of three
procedural noise octaves, each requiring multiple sin/hash computations.

Coordinates are world-aligned and wrap every 1024 metres, so adjacent
terrain chunks and decorative meshes receive matching shadows, with no
visible boundary jump. Uniform drift is animated by shader `TIME`;
there is no CPU-side image generation every frame.

`scripts/client/atmosphere.gd` gates opacity using the actual
server-synchronized daylight and storm transition: full contrast in
direct midday sun, soft shadows beneath heavy overcast, and **no cloud
lookup at night**. The **Performance** preset also disables cloud
shadows entirely, saving even the texture read; other presets retain
the animated effect.

The shared `aa_cloud_shadow_map` (sampler2D) and
`aa_cloud_shadow_strength` (float) resources are registered in
`project.godot`. The existing client ShaderMaterial resources,
`ground.gdshader`, `grass_field.gd` and `foliage.gd`, all use the
same include and need no extra render pass, imported models, or
additional full-screen effect.

## Draw-distance LOD for instanced scenery

`scripts/client/scenery_lod.gd` centralizes four local visual budgets:

| Preset | Trees | Rocks / ore | Bushes | Props | Imported mesh LOD bias | Decoration scale |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Performance | 112 m | 94 m | 66 m | 72 m | 0.70 | 0.55× |
| Balanced | 160 m | 136 m | 104 m | 118 m | 1.00 | 0.80× |
| High | 205 m | 184 m | 145 m | 160 m | 1.20 | 1.00× |
| Ultra | 260 m | 224 m | 185 m | 205 m | 1.50 | 1.20× |

Visual ranges operate on **MultiMesh batches**, not individual
instances. Existing `SceneryBatches` already splits dense decorations
into 32-metre cullable subgroups. Critical structures, landmarks,
monuments, walls, towers and workshops have **unlimited range** in this
LOD system, and all gameplay positions and resources remain server-owned.

`ChunkView.register_scenery` configures both freshly streamed objects
and decorations. `GraphicsQuality.apply` changes the ranges and LOD
bias on already loaded batches by scanning the render-only group
`aa_scenery_multimeshes` **only during a preset change**, never on
every frame. Geometry switches use a 12-metre visibility hysteresis
instead of alpha-blended crossfade, avoiding increased overdraw.

Higher LOD bias preserves fine imported geometry where mesh LODs
exist; it does not invent new polygon detail for meshes without
precomputed LODs. Draw-range culling is meaningful for objects farther
away; populated close-up scenes retain existing texture quality.

## Validate appearance and GPU cost

Run the standard authoritative smoke suite:

```bash
godot --headless --path game --script res://tests/run_all.gd
godot --headless --path game --script res://tests/smoke_client_scene.gd
```

`tests/test_cloud_shadow_lut.gd` checks repeatability, cloud lookup
size, normalization, seamless tiling, daylight/storm gating, global
uniform declarations and shared shader code.

`tests/test_scenery_lod.gd` checks monotonic graphic detail, real
`MultiMeshInstance3D` properties, essential landmark visibility and
dynamic preset updates.

For a performance comparison, capture the same **forest**, **open
meadow**, **ruined city** and **storm coastline** screenshots with
identical camera/time and warm shaders first. On actual GPU hardware
record median/p95 frame times, GPU time, frame-to-frame draw calls,
visible geometry/triangles and RAM/VRAM. Test Compatibility and
Forward+ separately; do not claim Nanite, Lumen, virtual textures or
FSR2 are natively implemented by these GDScript changes.

Useful upstream references:

- https://docs.godotengine.org/en/4.7/tutorials/performance/using_multimesh.html
- https://docs.godotengine.org/en/4.7/tutorials/3d/visibility_ranges.html
- https://dev.epicgames.com/documentation/unreal-engine/hierarchical-level-of-detail-in-unreal-engine
- https://docs.unity.com/en-us/engine/6000.0/manual/analysis/graphics-performance-profiling/reduce-draw-calls/gpuinstancing/gpuinstancing
