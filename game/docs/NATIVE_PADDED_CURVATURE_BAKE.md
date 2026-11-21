# Cgame native padded heightfield curvature baking

Cgame provides a geometry primitive that converts a sampled heightfield into precomputed terrain-color attributes:

```gdscript
var colors: PackedColorArray = Geometry2D.bake_heightfield_curvature_colors(
    padded_heights, Vector2i(width, height), spacing,
    cavity_start, cavity_end, ridge_start, ridge_end)
```

The input buffer is row-major with a **one-sample halo** along each of the four sides. For output size `(width,height)`, supply exactly `(width+2)*(height+2)` finite floats. The four outer corners are unused. Each interior sample computes the discrete four-neighbor Laplacian (left + right + up + down - 4×center) divided by squared sample spacing. Positive curvature marks cavities (R), negative marks ridges (G); configurable smoothstep ramps produce independent 0..1 channels. B and A are always 1. This is an O(width × height) *native CPU batch* that returns `PackedColorArray` suitable for procedural mesh vertex colors. It is **not** SSAO, Lumen, Nanite, or UE Landscape rendering.

Constraints: output dimensions 1..2046; finite positive spacing with positive finite inverse square; finite nonnegative increasing cavity/ridge ranges; correct input count and finite input heights. Invalid arguments return an empty color array without modifying input. No GPU-side upload is implicit.

## Direct integration in Albion After

`game/scripts/client/terrain_curvature.gd` now builds the one-sample halo using the existing authoritative `world_height` callable **only along the four outer strips** of a chunk. The script calls Cgame's native baker once and retains an equivalent scalar fallback for stock Godot, with identical thresholds `[0.015,0.32]` for cavities and `[0.015,0.42]` for ridges.

The canonical `game/scripts/client/chunk_view.gd` already invokes `TerrainCurvature.build` when updating a streamed `ChunkedTerrain3D`; therefore the new native batch is exercised by live world chunks, and the returned RGBA values continue into `ChunkedTerrain3D.set_color_data`. Its blue channel remains available for the existing terrain horizon AO, and no shader remapping, draw call, texture allocation, collision geometry, save format or multiplayer protocol changes are necessary.

Unreal's PCG framework also passes landscape spatial properties, density and slope attributes into generation flows, including biome filtering. [PCG Biome Core & Sample Plugins Reference](https://dev.epicgames.com/documentation/unreal-engine/procedural-content-generation-pcg-biome-core-and-sample-plugins-reference-guide-in-unreal-engine). The narrower Cgame change is reusable curvature baking on the existing height data; the UE PCG graph system is not implemented here.

## Tests

- Engine: `tests/core/math/test_geometry_2d.cpp` validates cavity/ridge/flat outputs, custom spacing, no source mutation and rejected invalid shape/spacing/ramp/nonfinite values.
- Game: extended `game/tests/test_terrain_curvature.gd` compares native and scalar RGBA colors for concave, convex, and flat samplers across spacings, plus tests direct API contracts and the live chunk source integration.
- Existing game tests already register `test_terrain_curvature.gd` in `run_all.gd`.

Validation commands with a built engine:

```sh
godot --headless --test --test-case="*padded terrain curvature*"
godot --headless --path game --script res://tests/run_all.gd
```

Compile/test and compare actual terrain screenshots before claiming measured performance or pixel parity.
