# Terrain LOD geomorphing: normal interpolation

## Visual problem

The native `ChunkedTerrain3D` already morphs vertex **heights** on High/Ultra, following the landscape LOD techniques in Unreal Engine and Unity. However, the vertex normals had remained fixed at the fine LOD while heights gradually approached the coarse triangulation. On steep slopes, rocks and terrain transitions this can cause abrupt changes in lighting even when vertex positions move smoothly. Unity specifically documents LOD lighting artifacts caused by normals that no longer match the displayed geometry.

## Engine implementation

When `lod_geomorph_enabled` is active and a coarser LOD exists, `HeightmapTerrainGeometry::build_chunk` now prepares the **target normal of the next coarser triangle** for each generated vertex. It uses the same (+x, 0) to (0, +z) diagonal as the existing coarse height interpolation, and linearly interpolates the three coarse-grid **vertex normals** rather than deriving them from unrelated fine-grid heights. This is essential: at shared coarse vertices, the target normal exactly equals the next LOD's own normal, preventing lighting discontinuities when a mesh is replaced.

The new stream is stored in `ChunkMesh.morph_normal_xyz` and uploaded as `RenderingServer::ARRAY_CUSTOM0` with `ARRAY_CUSTOM_RGB_FLOAT`. Unlike quantized per-vertex colors, the normals preserve full signed float precision. The C++ code uses the existing native `normal_override` when available, so the previously implemented seamless-border normals also feed into the coarse targets. Source-grid lookups are clamped for partial final chunks, including custom normal data.

**No additional stream is allocated** for distance-only LOD meshes, the coarsest LOD, or Performance/Balanced where geomorphing is disabled. Skirt vertices copy their source's target normal, but their UV2 geomorph mask remains zero and they do not deform.

## Game integration

Both `assets/shaders/ground.gdshader` (the 13-layer PBR terrain) and the procedural fallback shader embedded in `chunk_view.gd` now apply the same interpolation weight to vertex height and normal:

```glsl
float morph = clamp(aa_lod_morph * UV2.y, 0.0, 1.0);
VERTEX.y = mix(VERTEX.y, UV2.x, morph);
if (morph > 0.001) {
    NORMAL = normalize(mix(NORMAL, CUSTOM0.xyz, morph));
}
```

The existing world-space normal calculation, PBR material selection, steep-slope classifications, cloud shadows, curvature, contact AO and water interaction naturally use the interpolated normal without any new fragment work.

## Performance and validation

The cost is three extra 32-bit floats per vertex of geomorph-enabled meshes and a few vertex ALU instructions in High/Ultra. No new pixel texture lookups, shader passes, shadow casters or full-screen buffers are added. Source normals are calculated only when each native LOD mesh is built and cached thereafter. Extra vertex memory is a deliberate high-tier tradeoff for higher image quality.

Native tests in `tests/scene/test_heightmap_terrain_geometry.cpp` cover exact shared-grid target normals, triangle diagonal interpolation, custom source normal overrides, skirt copying, absent streams for legacy LOD, and partial heightfield borders. `game/tests/test_terrain_geomorph.gd` checks both shader variants.

Build the **customized Godot engine**, then run native tests and:

`godot --headless --path game --script res://tests/run_all.gd`

For visual QA, rotate the midday directional sun around rocky and snowy terrain while crossing high/ultra LOD boundaries; inspect sunset light on slopes and compare shadow normals at streaming chunk borders. Profile vertex memory and GPU p50/p95 frame time. These tests have **not been executed on a GPU** in this environment, and the change does not imply a measured FPS gain.
