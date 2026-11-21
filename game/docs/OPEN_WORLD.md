# Open world and landscape — feature status

Status: **PRESENT** = in the engine and used by the game; **PARTIAL** = exists but incomplete or not used by the game; **MISSING** = not implemented. "Batch 1" marks what was added in the open-world pass of 2026-11-21.

How the game world is built: `WorldGen.height_at` (shared, deterministic, server-authoritative) → `ChunkView._build_terrain` → native `ChunkedTerrain3D` per 64 m chunk, streamed by the native `WorldStreamer` from `online_main.gd`. Terrain features plug into `WorldGen` (height/biome) or the chunk build.

## Streaming and world structure

| Feature | Status | Where |
|---|---|---|
| World Partition | PARTIAL | `modules/world_partition` (`WorldPartition3D`) — engine-side, the game streams with `WorldStreamer` |
| Automatic cell splitting | MISSING | — |
| World Partition Editor | MISSING | — |
| Data Layers | MISSING | — |
| One File Per Actor | MISSING | — |
| Automatic HLOD build | MISSING | — |
| Hierarchical World Streaming | PARTIAL | `WorldPartition3D` tiers; game: one ring + staged scenery (`decor_streaming_policy.gd`) |
| Predictive World Streaming | PRESENT | `WorldStreamer` velocity/look-ahead, `world_streaming_policy.gd` |
| Multi-Source Streaming | PARTIAL | `WorldStreamer.set_auxiliary_source` (waypoint); named sources only in `WorldPartition3D` |
| Priority-Based Streaming | PRESENT | `world_streaming_grid.cpp`, view-weighted ordering |
| Async Scene Loading | PARTIAL | threaded loads exist; game chunks are generated on the main thread within a time budget |
| Async Scene Unloading | PARTIAL | hysteresis unload, main thread |
| Background Resource Loading | PARTIAL | `WorldStreamer` threaded loads, `modules/texture_streaming` |
| Streaming Cancellation | PARTIAL | stale requests dropped; no explicit cancel API |
| World Origin Rebasing | PARTIAL | `FloatingOrigin3D` (engine); not needed for the 6.4 km island |
| Double Precision / Large World Coordinates | PARTIAL | `precision=double` build option, `FloatingOrigin3D`; unused |
| Infinite World Streaming | PARTIAL | unbounded cells; the game world is a finite island |
| Seamless World Transitions | PARTIAL | hub ↔ wilderness without loading; dungeons are a far coordinate region |
| Streaming Dependencies | PARTIAL | two-phase residency (`chunk_visual_details_ready`) |
| World Streaming Profiler | PARTIAL | counters + `Performance` custom monitors |

## Terrain

| Feature | Status | Where |
|---|---|---|
| Terrain Editor / Sculpting / Painting | PARTIAL | `modules/heightmap_terrain`, `modules/terrain` editor brushes; the game's terrain is procedural |
| Chunk-Based Terrain | PRESENT | `ChunkedTerrain3D`, `chunk_view.gd` |
| Terrain Material Layers | PRESENT | `ground.gdshader`, 13 PBR layers by biome/slope |
| Splat Maps | PARTIAL | generated per-chunk biome map + road mask; not editable |
| Virtual Heightfields | MISSING | — |
| Terrain LOD / Geomorphing | PRESENT | `ChunkedTerrain3D` screen-space + geometric-error LOD, geomorph |
| Terrain Tessellation | MISSING | (close-range parallax only) |
| Terrain Collision Streaming | PARTIAL | engine supports it; the game resolves ground on the server via `height_at` |
| Async Terrain Collision | MISSING | — |
| Terrain Navigation Integration | PARTIAL | engine nav tiles in `WorldPartition3D`; the game has no navmesh |
| Terrain Erosion / Hydraulic / Thermal | **PRESENT (batch 1)** | `WorldGen._base_height`: analytic erosion — ridged-noise gullies and ravines on high ground (hydraulic-style) and slumping peaks (thermal-style). An approximation; `height_at` must stay a pure function, so no iterative simulation |
| Landscape Layers / Edit Layers | PARTIAL / MISSING | material layers only |
| Landscape Streaming | PRESENT | `WorldStreamer` + `ChunkedTerrain3D` |
| Distant Landscape Rendering | PARTIAL | terrain LOD + fog; no far-field mesh |
| Terrain Occlusion | PARTIAL | horizon AO; no occluders |
| Terrain Material Streaming | PARTIAL | texture mip streaming; layer arrays loaded up front |
| World Building Tools | PARTIAL | editor brushes, asset bake scripts |

## Water

| Feature | Status | Where |
|---|---|---|
| River Generation | **PRESENT (batch 1)** | `world_rivers.gd`: sources in the hills, steepest-descent flow, monotone falling surface, widening downstream, channels carved into `height_at` |
| Spline Rivers | **PRESENT (batch 1)** | Chaikin-smoothed polylines; ribbon meshes per chunk in `ChunkView._build_rivers_and_bridges` |
| Lake Generation | **PRESENT (batch 1)** | rivers trapped in hollows or circling flats pool into carved lakes (`world_rivers.gd`), drawn as water discs |
| Ocean Generation | PARTIAL | sea plane following the player; island edge sinks into it |
| Ocean Simulation | MISSING | shader waves only |
| Shoreline Simulation | PARTIAL | depth-based shore foam/surf in `water.gdshader` (now also along rivers and lakes) |
| Water Buoyancy | PARTIAL | swimming/diving logic; no rigid-body buoyancy |
| Water Refraction / Caustics | PRESENT | `water_refraction.gd`, `water_caustics.gdshaderinc` |
| Underwater Rendering | PARTIAL | tint + fog; no view of the surface from below |
| Underwater Fog | **PRESENT (batch 1)** | `online_main._apply_underwater_fog`: dense blue-green environment fog that thickens with depth, in the sea, rivers and lakes |

## Roads, splines, biomes, vegetation

| Feature | Status | Where |
|---|---|---|
| Procedural Roads | PRESENT | `world_roads.gd` |
| Spline Roads | PARTIAL | winding polylines, not `Curve3D` |
| Spline Bridges | **PRESENT (batch 1)** | `WorldRoads._find_bridges`: where a road crosses a river an arched timber bridge spans bank to bank; its deck is part of `height_at` (walkable, server-authoritative) while the terrain mesh uses `ground_at` |
| Spline Fences | PARTIAL | placed palisades around sites |
| Biome Generation | PRESENT | `WorldGen.biome_at` (climate noise + height); rivers/lakes count as water |
| Biome Blending | PARTIAL | blended in the ground shader; hard for vegetation |
| Climate Simulation | PARTIAL | static climate noise + dynamic weather/day cycle |
| Vegetation Painting | MISSING | procedural placement only |
| Procedural Forests | PRESENT | groves by biome |
| GPU Grass Rendering | PRESENT | `grass_field.gd` (now kept out of rivers and lakes) |
| GPU Foliage Simulation | PARTIAL | vertex-shader wind/bend |
| Interactive Vegetation | PRESENT | `plant_interaction.gd` |
| Vegetation Wind Simulation | PRESENT | `vegetation_wind.gd` |
| Vegetation Physics | MISSING | — |
| Foliage LOD | PRESENT | `scenery_lod.gd`, grass tiers |
| Foliage HLOD / Impostors | MISSING | — |
| Foliage Collision Streaming | MISSING | server-side collision circles only |

## Next batches (by player-visible value)

1. Foliage impostors + HLOD for distant forests (biggest frame-time win in the wild).
2. Distant landscape: a low-res far-field terrain ring beyond the streaming radius.
3. Ocean simulation (Gerstner waves with mesh LOD) and a view of the surface from below.
4. Vegetation physics (trees that sway/fall when hit), buoyancy for dropped loot and boats.
5. Data Layers (seasonal/event content toggles) and a streaming profiler panel.
