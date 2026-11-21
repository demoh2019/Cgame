# Native periodic scalar grid sampler for PCG and cloud fields

Cgame extends the built-in `Geometry2D` singleton:

```gdscript
var samples: PackedFloat32Array = Geometry2D.sample_scalar_grid_wrapped(
    grid: PackedFloat32Array, size: Vector2i, uvs: PackedVector2Array, smooth: bool = true)
```

This batched CPU operation samples a row-major scalar *lattice* grid at normalized UV positions. Each grid index (x,y) is located at (x / width, y / height), and both axes wrap across 0/1 boundaries. The four neighboring lattice values are interpolated bilinearly. Optional `smooth=true` remaps the fraction within each cell through `t*t*(3-2*t)` before interpolation, matching Albion After's pre-existing smooth noise sampler; `false` provides ordinary bilinear interpolation.

- Input dimensions 1..2048 each, grid size exactly width × height, finite grid values, finite UVs.
- At most 65,536 query UVs per call. Every output is a packed 32-bit float; invalid dimensions/nonfinite values/overflow return an empty array. Source data is immutable.
- Per-batch work O(grid size + query count), with a single script-to-C++ call for many queries. No GPU readback or texture allocation in the engine API.

## Unreal comparison

Epic's Unreal PCG supports texture-derived point attributes and configurable point/bilinear texture filtering; see [EPCGTextureFilter](https://dev.epicgames.com/documentation/unreal-engine/API/Plugins/PCG/EPCGTextureFilter) and [PCG Texture Sampler](https://dev.epicgames.com/documentation/en-us/unreal-engine/API/Plugins/PCG/UPCGSampleTextureSettings). Cgame's implementation is **not** a full PCG graph, virtual-texture sampling system, or a GPU texture sampler: it is a reusable CPU primitive for generated scalar fields with periodic coordinates.

## Immediate Albion After integration

`game/scripts/client/cloud_shadow_lut.gd` previously evaluated three periodic noise octaves for each pixel of the 128×128 cached cloud-shadow image from GDScript: `128×128×3` individual scalar lattice samples. Now it builds the UV query array once, sends one native batch **per octave**, and combines the weighted outputs before applying the unchanged shadow smoothstep, filling the unchanged L8 image using `ImageBatch.set_row`. This does not alter per-frame weather motion, GPU shader sampler, terrain, network/saves or server simulation. All work occurs once when creating the cached image.

`game/scripts/client/scalar_grid_sampler.gd` implements identical scalar wrapping and smooth interpolation for stock Godot. `CloudShadowLut.build_image(true)` is a test-only path to generate an uncached fallback image for pixel comparisons.

## Regression tests

- Engine: `tests/core/math/test_geometry_2d.cpp`: periodic UVs, linear vs smooth weights, single-pixel grids, empty queries, wrong dimensions, NaN/overflow and query count bounds.
- Game: `game/tests/test_scalar_grid_sampler.gd`: native/script parity, input immutability, scalar references and cached-vs-fallback cloud-image byte closeness.
- Registered with the existing `game/tests/run_all.gd`.

Expected local validation:
```sh
godot --headless --test --test-case="*wrapped scalar grid*"
godot --headless --path game --script res://tests/run_all.gd
```

No native compilation, actual Godot headless tests, GPU screenshot comparison, or speed benchmark has been run as part of this change.
