# Open world and landscape — feature status

Status: **PRESENT** = in the engine and used by the game; **PARTIAL** = exists but incomplete or not used by the game; **MISSING** = not implemented. "Batch 1" marks what was added in the open-world pass of 2026-11-21.

How the game world is built: `WorldGen.height_at` (shared, deterministic, server-authoritative) → `ChunkView._build_terrain` → native `ChunkedTerrain3D` per 64 m chunk, streamed by the native `WorldStreamer` from `online_main.gd`. Terrain features plug into `WorldGen` (height/biome) or the chunk build.

## Streaming and world structure

| Feature | Status | Where |
|---|---|---|
| World Partition | PARTIAL | `modules/world_partition` (`WorldPartition3D`) — engine-side, the game streams with `WorldStreamer` |
| Automatic cell splitting | MISSING | — |
| World Partition Editor | MISSING | — |
| Data Layers | **PRESENT (batch 5)** | `data_layers.gd`: server-wide runtime layers chosen by the calendar or forced with `--layers winter,festival` / `--layers none`; sent to clients, applied live. `winter` settles snow on all low ground (`aa_snow_cover` in `ground.gdshader`, eased over 20 s); `festival` puts lantern posts, lights and pumpkins around settlements and camps (`ChunkView.set_data_layers`) |
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
| World Streaming Profiler | **PRESENT (batch 5)** | Ctrl+F3 overlay (`streaming_profiler.gd`): frame-time graph, FPS/draw calls, loaded/pending/queued cells, visual details pending, far-field and sea-map progress, active data layers, and a mini-map of loaded cells around you |

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
| Distant Landscape Rendering | **PRESENT (batch 2)** | `far_field.gd`: a 1.7 km far-terrain ring sampled from `WorldGen.ground_at`, coloured by biome (snow caps on peaks), sunk under the real chunks; rebuilt a few rows per frame and swapped in when the player moves 96 m |
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
| Ocean Simulation | **PRESENT (batch 3)** | `water.gdshader` vertex Gerstner swell (4 wave trains around the weather wind, stronger in wind and rain) on a radial LOD sea mesh (`sea_surface.gd`: dense rings near the camera, 900 m out); normals and whitecaps follow the swell |
| Shoreline Simulation | **PRESENT (batch 3)** | island depth map (`sea_surface.gd`, 256² over 6.4 km, filled a few rows per frame) shrinks the swell over shallows; depth-buffer surf and foam on every shore, river and lake |
| Water Buoyancy | **PRESENT (batch 4)** | `buoyancy.gd`: rigid bodies in the "buoyant" group (debris, severed limbs) get lift by submersion, water damping and wind drift; loot bags float and bob; **boats**: a craftable Driftwood Raft (workbench: 10 planks, 8 fiber) lets you paddle deep water at ~2.6x swim speed on the surface (server-authoritative in `Movement.step`, shown by `raft_visual.gd`) |
| Water Refraction / Caustics | PRESENT | `water_refraction.gd`, `water_caustics.gdshaderinc` |
| Underwater Rendering | **PRESENT (batch 3)** | the surface is drawn from below (`water.gdshader` back faces): dark teal ceiling with a bright Snell's window overhead and moving ripples, plus underwater fog |
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
| Vegetation Physics | **PRESENT (batch 4)** | `ChunkView.shake/_fell_tree`: a struck tree shudders about its base; a tree felled while you watch topples (gravity ease-in, bounce) and sinks away instead of vanishing |
| Foliage LOD | PRESENT | `scenery_lod.gd`, grass tiers |
| Foliage Impostors | **PRESENT (batch 2)** | `far_field.gd`: impostor pictures baked at start-up from the game's own tree models (off-screen ortho viewport, edge-bled, mipmapped `Texture2DArray`), drawn as cylindrical billboards |
| Foliage HLOD | **PRESENT (batch 2)** | distant woods as one MultiMesh of impostors beyond the real-tree radius (150 m). Density and species follow the biome; positions are a seeded scatter, not the exact far trees |
| Foliage Collision Streaming | MISSING | server-side collision circles only |

## Not done (from the original list)

Editor-side tools and offline pipelines that do not fit a procedurally generated, server-authoritative world: World Partition Editor, automatic cell splitting, One File Per Actor, automatic HLOD build for hand-placed levels, Landscape Edit Layers, Vegetation Painting, Virtual Heightfields, hardware Terrain Tessellation, async terrain collision. Their engine-side building blocks are listed above where they exist.
