# Terrain geometric pixel-error LOD (engine + game)

## Why this is better than distance-only simplification

In the original `ChunkedTerrain3D` implementation, terrain chunks switched mesh detail at the same distance regardless of relief. A flat field that a coarse mesh can reproduce almost exactly used the same triangles as a rocky ridge where the coarse mesh might omit a peak. Modern game terrain uses a *screen-space geometric error* target; see Unity Terrain's Pixel Error and the analogous geometric error / screen-size controls in Unreal Engine.

This update implements that technique in the custom Godot engine and exposes it to Albion After. It does not attempt to reproduce Nanite or Unity Terrain internals.

## Native engine implementation

New property: `ChunkedTerrain3D.lod_pixel_error` (`set_lod_pixel_error(float)`, `get_lod_pixel_error()`).

At heightfield rebuild time, the engine evaluates each source height sample against the height interpolated by every coarser mesh. It uses the **same triangle diagonal** as actual mesh generation, including partial border chunks. The maximum vertical deviation in meters is cached per chunk and LOD. Error bounds are made monotonic from fine to coarse LOD to keep the selector stable. This happens once per heightfield rebuild, not per rendered frame.

During existing chunk visibility updates, the engine converts each cached deviation to approximate screen pixels using the current viewport's **3D rendering scale** (important under FSR), camera FOV or orthographic size, node vertical scale and the distance to the closest point of the chunk bounds. It picks the coarsest LOD whose error fits the budget. A ±10% hysteresis margin reduces repeated mesh switching near boundaries. Existing skirts still hide geometry cracks between different LODs.

Setting the property to **0** preserves legacy distance-driven LOD selection, including in other Godot projects using this custom engine. Changing it at runtime only reselects cached LOD meshes; it does not regenerate heights, source normals, PBR materials, collision or streamed world state. Nonexistent cameras use the safe fallback.

## In-game quality budgets

| Setting | Max approximate geometry error |
| --- | ---: |
| Performance | 6.0 screen pixels |
| Balanced | 3.5 screen pixels |
| High | 1.8 screen pixels |
| Ultra | 0.9 screen pixels |

Both Poly Haven textured ground and procedural fallback terrain use the same native engine setting. All newly streamed chunks inherit it, and changing quality updates already loaded chunks via the shared `aa_chunked_terrain_lod` group. This is independent of PBR layer count, anisotropic filters, cloud shadows, wind, water, and the server's gameplay collision.

## Benefits and tradeoffs

- Flat ground can use many fewer vertices at a given distance without losing its exact planar silhouette.
- Mountains and irregular terrain can retain more geometry than a fixed distance ring would, protecting visible ridges.
- The selector costs a handful of arithmetic operations per terrain *chunk* on the normal 0.5-second update cadence; there are no new shader samples, passes, textures, or draw calls.
- The cached metric costs extra CPU work when a chunk is initially built or the heightfield changes, especially for very large heightmaps with high `chunk_quads`. An unchanged world does not pay that cost every frame.
- This is still discrete mesh LOD; hysteresis limits flicker but does not mathematically eliminate all geometric popping. The existing skirts hide gaps. Profiling is required to confirm the net cost in mountain-heavy scenes.

## Acceptance tests

Run the native engine unit suites in `tests/scene/test_heightmap_terrain_geometry.cpp` and `tests/scene/test_chunked_terrain_3d.cpp` after rebuilding the fork, then:

`godot --headless --path game --script res://tests/run_all.gd`

The tests cover exact flat-plane simplification, a missing peak, partial boundary chunks, projection pixel/error thresholds, hysteresis, invalid parameters and quality-profile wiring.

For visual QA, view the same forest plains, snow ridge, rock cliff and settlement at 720p and 1080p; repeat with FSR2 and at different camera FOVs. Check silhouette transitions and seams with the earlier custom terrain-normal work. Compare median and p95 GPU frame time, CPU mesh update time and rendered triangle count against the previous distance-only method before claiming performance gains.

**Note:** The feature needs a rebuild of the customized Godot engine. Source-level review is not equivalent to a successful native compile or GPU benchmark.

The optional pixel-error selector also coexists with the native `lod_geomorph_enabled` and `screen_space_lod_enabled` features: under geometric LOD it derives each morph threshold from the actual projected error of the **next coarser** mesh, rather than the previous hard distance ring. Existing shader morph coordinates and distance-based fallback remain intact.
