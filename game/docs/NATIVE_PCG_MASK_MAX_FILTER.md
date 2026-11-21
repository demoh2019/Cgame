# Native PCG mask morphology — grayscale max-filter

Unreal PCG supports spatial and binary exclusion from procedural generation, including biome graphs that exclude point data overlapping designated volumes, splines and primitives. Cgame now provides a compact CPU utility for expanding a sampled 8-bit exclusion mask while **retaining its grayscale coverage**.

## Engine API

```gdscript
var expanded: PackedByteArray = Geometry2D.max_filter_mask(
    mask: PackedByteArray, size: Vector2i, radius: int)
```

For every output pixel at (x,y), take the maximum source byte across the square Chebyshev-radius neighborhood `[x-radius,x+radius] × [y-radius,y+radius]`, clipped to the image. This produces standard 8-bit *grayscale dilation*, not Gaussian blur, feathering, Euclidean expansion or binary thresholding. `radius=0` yields the original values under copy-on-write; nonzero radius cannot decrease any input byte. An empty mask is allowed only for a matching raster size (dimensions are at least 1×1).

- Native CPU: two separable monotonic-deque passes, **O(width × height)** regardless of radius. Scratch memory O(width × height), deque memory O(max(width,height)).
- Allowed dimensions 1..2048 per side, radius 0..64, exact row-major byte count. Invalid arguments yield an empty array. Input never changes.
- Equivalent scalar GDScript fallback in `game/scripts/client/road_mask_max_filter.gd` uses separable sweeps with O(width × height × radius) work, acceptable for the game's tiny 64² road masks.

## Live integration in Albion After

`GrassField.Source` now computes a **two-pixel (2m)** expanded road mask when a streamed chunk has roads, once when the chunk's grass source is constructed. The original `Source.road` is not modified, so the road shader and motorcycle grip preserve their existing exact raster and gameplay semantics.

The new `Source.road_clearance` is consumed by both ground-plant sampling (used by `GroundPlants`, including rocks/bushes/flowers) and the procedural grass generator. Scanned plants cannot spawn on the visible road **or its 2m shoulder**. Existing 12%-chance grass on the old track itself remains, but outside the road's exact footprint, in its added shoulder, grass is retained with 35% probability instead of full density. No extra draw calls, terrain rebuilds, dynamic textures or multiplayer changes.

Important: this is a per-chunk approximation; the filter has no knowledge of a road mask belonging to adjacent chunks. Boundary continuity needs a halo if future road-related visual effects require exact cross-chunk clearance. Game test covers road mask preservation, exact radius, diagonal expansion and sampled ground-plant exclusion.

## Verification

- `tests/core/math/test_geometry_2d.cpp`: grayscale max, brute-force rectangular reference, boundary clipping, radius 0 and 64, all-zero/one-pixel masks, invalid dimensions/radii.
- `game/tests/test_road_mask_max_filter.gd`: native scalar parity and independent oracle for several radii, plus live source integration.
- Registered in `game/tests/run_all.gd`.

```sh
godot --headless --test --test-case="*grayscale mask max-filter*"
godot --headless --path game --script res://tests/run_all.gd
```

Full native C++ and headless Godot builds, visual rendering comparisons and performance benchmarks must be run before any speedup/quality claims.

See [Unreal PCG Biome Core and Sample Plugins Reference](https://dev.epicgames.com/documentation/unreal-engine/procedural-content-generation-pcg-biome-core-and-sample-plugins-reference-guide-in-unreal-engine?lang=en-US) for the broader reference approach.
