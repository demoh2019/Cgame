# Seamless Terrain Normals — engine and game integration

## Problem

Each chunk of the open world is a separate `ChunkedTerrain3D` node using a 33 × 33 height grid (2 m/sample). The engine previously estimated source-grid edge normals with one-sided finite differences because a standalone heightmap does not know the next chunk's heights. Two adjacent heightfields could therefore agree on terrain height and geometry but have different surface normals across their shared border. This is particularly visible as a vertical lighting seam in cliffs and snow with PBR materials, directional sun and screen-space ambient effects.

## Engine extension

The forked engine adds:

- `ChunkedTerrain3D.set_normal_data(PackedVector3Array)`
- `ChunkedTerrain3D.get_normal_data()`
- An optional normalized source-grid normal pointer inside `HeightmapTerrainGeometry::Params`

Normals are row-major with exactly the same width × depth as `set_height_data`. The setter checks dimensions and validity and normalizes input **once**. `build_chunk()` and `sample_normal_bilinear()` automatically use the supplied normals for all LOD meshes, skirts and normal queries. When no override is present, original engine-generated heightfield normals are unchanged. Replacing height data and clearing the heightfield invalidate old custom normals, preventing stale shading.

The visual normal override does not alter physics collision, height sampling, vertex positions or gameplay. There are no extra shader uniforms, shadow-map passes or texture allocations.

## World integration

`game/scripts/client/terrain_seam_normals.gd` calculates central differences from the same deterministic height function already used for world geometry. Interior samples reuse the cached height grid; **only boundary samples** query one additional grid interval outside the chunk. Clipping matches the engine's normalized height range before differentiation. Two neighbouring streamed chunks therefore compute the same normal at the same border coordinates, without loading one another.

`ChunkView._build_terrain()` sets heights, then custom normals, before adding the terrain to the scene. The same result is reused across its three LOD levels; the imported PBR terrain and procedural fallback both inherit it.

## Quality and performance trade-off

For a 33 × 33 heightfield the override holds 1,089 vector normals (~13 KiB of float data) in addition to existing terrain heights. It is calculated once when a terrain chunk is built. The CPU samples the world generator only at the edge halo, not for every 2D height-neighbour pair, and mesh generation reuses normal data rather than computing another gradient on every LOD. The feature does not increase pixel shader ALU, texture reads, or draw calls. It reduces *shading discontinuities*, not mesh LOD geometric cracks (which remain handled by skirts).

## Validation

Run the engine C++ tests for `test_chunked_terrain_3d` and `test_heightmap_terrain_geometry` after recompiling the fork. Then run the game suite:

`godot --headless --path game --script res://tests/run_all.gd`

Compare neighbouring 64 m chunks across forest, coast, mountains and snow at low and high viewing elevations. Rotate the directional sun and switch between native High/Ultra MSAA and FSR2 while inspecting border lines. Teleport across chunk boundaries and allow independent chunk streaming, then verify matching edge illumination at LOD 0, 1 and 2. Benchmark streaming CPU spikes and normal-buffer memory; no FPS claim is made without profiling.

See the native method reference in `doc/classes/ChunkedTerrain3D.xml`. This feature **requires rebuilding the customized Godot engine**; stock Godot does not expose `set_normal_data`.
