# Native 2D segment mask rasterization in Cgame and Albion After

The engine now provides `Geometry2D.rasterize_segments_mask(segment_endpoints, size, half_width, softness) -> PackedByteArray`.

- `segment_endpoints`: pairs of local pixel coordinates (`[a0, b0, a1, b1, ...]`).
- `size`: 2D raster dimensions. Each pixel samples its center `(x + 0.5, y + 0.5)`.
- `half_width`: solid coverage radius in pixels; `softness`: additional linear fade radius.
- Output: L8 (0-255), x-major within each row, overlapping segments combined by **maximum**, not additive blending. A zero-length segment paints a round dab.
- Constraints: up to 8192 segments and 2048 pixels per dimension, finite endpoints, half-width >= 0, softness > 0. Invalid parameters return an empty array with an engine error. Valid empty input returns a zero-initialized mask.
- Complexity scales with segment **bounded pixel footprints**, not full image area per segment. No background threads, no GPU work, and no persistent state.

This extends the previous engine feature `Geometry2D.get_closest_point_on_segments` with a separate reusable terrain-weight/footprint mask rasterizer. Similar *purpose* to Unreal Engine Landscape Spline weightmap painting and Unity Splines' procedural road workflows, but no spline interpolation, brush authoring or editor toolchain is implied.

## Albion After integration

Canonical `game/scripts/client/chunk_view.gd` now calls `WorldRoads.rasterize_mask()` when constructing each chunk road shader L8 texture. On Cgame this calls the native geometry method once for all segments. On stock Godot (or if native input is rejected) the helper executes the original scalar per-segment pixel loop. This keeps the existing texture layout and the deterministic shader/grip behavior, while reducing interpreted GDScript loop overhead on native builds.

This optimization affects **rendering road masks**, not multiplayer authoritative movement, saves, or network data. The earlier server-side `WorldRoads.coverage_at` implementation remains independent.

## Verification

- Native tests in `tests/core/math/test_geometry_2d.cpp`: falloff, caps, crossing max-composition, degenerate and out-of-bounds segments, empty mask.
- `game/tests/test_world_roads.gd`: synthetic bitwise/tolerance parity and world-chunk offset coverage; included in `game/tests/run_all.gd`.
- Build and run (with an actual compiled Cgame binary):
  ```sh
  godot --headless --test --test-case="*rasterize segment masks*"
  godot --headless --path game --script res://tests/run_all.gd
  ```
- Compare with stock Godot. Benchmark chunk-load times before claiming a measured speedup.

References: https://dev.epicgames.com/documentation/en-us/unreal-engine/landscape-splines-in-unreal-engine and https://docs.unity.cn/Packages/com.unity.splines%40latest/
