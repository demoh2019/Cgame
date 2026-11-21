# pcg_graph terrain nodes

Extra PCG nodes (`pcg_terrain_nodes.h/.cpp`, registered by `register_pcg_terrain_nodes()`).
All follow the core rules: inputs are never mutated, randomness comes from world-space
coordinates + the node seed, bounds are half-open `[min, max)`, so any tiling of the world
produces identical points.

| Node | Unreal PCG / Houdini / Unity equivalent | What it does |
| --- | --- | --- |
| `PCGHeightfieldNode` | Unreal Procedural Terrain Graph source; Houdini HeightField Noise + Erode; Unity Terrain Tools noise/terrace/thermal erosion | Regular grid over the bounds; y from fractal value noise (`octaves`, `frequency`, `amplitude`, `ridged`, `terrace_steps`); `erosion_iterations` thermal smoothing (talus angle) on a padded grid so halves equal the whole. Normals from finite differences, attribute `height01`. |
| `PCGTerrainSampleNode` | Unreal Surface/Landscape Sampler (project to landscape); Houdini HeightField Project | Replaces y/normal with the context `height_sampler`; adds `slope` (degrees) and `height`. |
| `PCGBiomeClassifyNode` | Unreal Procedural Biome Graph / biome data layers; Houdini attribute-from-ramp; Unity Terrain layer rules | Temperature + moisture value noise with altitude lapse rate; first matching rule of `{index, min_temp, max_temp, min_moisture, max_moisture}` -> `biome` (also `temperature`, `moisture`). `use_context_biome` + `biome_names` maps the game biome sampler to indices. |
| `PCGVegetationNode` | Unreal Procedural Vegetation Graph (canopy/understory/ground cover); Unity Terrain tree/detail painting; Houdini scatter + attribute rules | Layers `{density, min_spacing, avoid_radius, assets, scale_min, scale_max}` placed in order, per-layer spacing (spatial hash), later layers avoid earlier ones. Attributes `asset`, `layer`. |
| `PCGCaveNode` | Unreal Procedural Cave Generation; Houdini Volume VOP + cellular automata; Unity community voxel caves | 3D cellular automaton (26 neighbours, `birth_limit`, `survival_limit`, `iterations`) seeded per world voxel + optional worm tunnels anchored on a world lattice (`worms_per_region`, `worm_length`, `worm_radius`). Outputs surface voxels with `cave_floor` / `cave_wall`, normal toward open space. Tiles exactly. |
| `PCGDungeonNode` | Unreal Procedural Dungeon Generation; Houdini Labs Dungeon/BSP; Unity ProBuilder/Tilemap dungeon generators | BSP rooms (min/max size, depth, padding) and L-shaped corridors joining sibling subtrees (every room reachable). Tiles with `room` id and `kind` (0 floor, 1 door, 2 corridor). `PCGDungeonNode.generate_layout(seed, rect, ...)` is static (also callable from GDScript) and returns `{rooms: Array[Rect2i], corridors: Array[PackedVector2Array]}`. One dungeon per bounds (not streamed across cells). |
| `PCGGpuDensityNode` | Unreal GPU Procedural Generation (PCG GPU compute); Houdini OpenCL; Unity compute-shader scatter | Value-noise density for all input points on a local `RenderingDevice` compute shader (GLSL, 64-bit hash emulated on `uvec2`). Falls back to `PCGDensityNoiseNode::value_noise` on the CPU when no device exists (headless, no Vulkan) or on any failure. GPU results are float32 and may differ in the last bits from the CPU: use for cosmetic layers only. |

Notes

* Heightfield erosion is a Jacobi (gather) thermal step; the grid is padded by `iterations + 1`
  cells, which is what makes the output independent of the tile.
* Caves and heightfields share the lattice anchored at world origin; spacing/voxel size must be the
  same for neighbouring tiles.
* Tests: `modules/pcg_graph/tests/test_pcg_terrain_nodes.h`
  (`bin/godot.* --headless --test --test-case="*PCGTerrain*"`).
