# occlusion_raster.gd

> Software occlusion culling: low-res depth rasteriser plus a max-depth Hi-Z pyramid.

`res://scripts/shared/occlusion_raster.gd`

## Overview

```text
Software occlusion culling: low-res depth rasteriser plus a max-depth Hi-Z pyramid.

Concepts (not code) follow:
 - Intel "Masked Software Occlusion Culling" (Hasselgren et al., HPG 2016; the reference
   library is Apache-2.0, https://github.com/GameTechDev/MaskedOcclusionCulling). This file is
   an independent GDScript implementation: occluders are rasterised into a tiny conservative
   depth buffer and occludees are tested by their screen-space bounding rectangle and nearest depth.
 - Hi-Z culling from the "GPU-driven rendering pipelines" talks (Haar & Aaltonen, SIGGRAPH 2015):
   a max-depth mip chain lets one test touch only a few texels whatever the box size.
No third-party source was copied.

Depth is view distance (clip-space w), so it is linear and independent of the engine's
reversed-Z / GL / D3D clip conventions. Perspective projections only. Larger = farther;
empty texels hold INF (nothing occludes). All results are conservative: when unsure, visible.

Usage per frame: begin(view_proj, w, h) -> rasterize_occluder(...)* -> is_visible / test_many.
```

## Constants

- `const NEAR_W := 0.05` - clip-space w below which geometry is clipped (occluders) or assumed visible (occludees)
- `const DEPTH_BIAS := 0.01` - relative push of occluder depth away from the camera (partial pixel coverage)

## Documented variables

- `var tested: int = 0` - Statistics, reset by begin().

## Functions

### `begin`

```gdscript
func begin(p_view_proj: Projection, p_width: int = 256, p_height: int = 128) -> void
```

### `rasterize_occluder`

```gdscript
func rasterize_occluder(triangles: PackedVector3Array) -> void
```

Rasterises triangles (world space, 3 vertices each, double sided) into the depth buffer.

### `temporal_reproject`

```gdscript
func temporal_reproject(prev_view_proj: Projection) -> void
```

Optional: seed the current buffer with last frame's depth reprojected through its matrix.
Call after begin() and before rasterize_occluder(). Approximate (disocclusions can leak stale
occluders), so depth is pushed 5% farther and only finite single texels are splatted.

### `build_hiz`

```gdscript
func build_hiz() -> void
```

Builds the max-depth mip pyramid. Called lazily by the tests when stale.

### `hiz_level_count`

```gdscript
func hiz_level_count() -> int
```

### `hiz_size`

```gdscript
func hiz_size(level: int) -> Vector2i
```

### `hiz_get`

```gdscript
func hiz_get(level: int, x: int, y: int) -> float
```

### `is_visible`

```gdscript
func is_visible(aabb: AABB) -> bool
```

True when the box may be visible (not provably hidden). Counts into tested/culled.

### `test_many`

```gdscript
func test_many(aabbs: Array) -> PackedByteArray
```

Batch test (GPU-instance-culling style): one byte per AABB, 1 = visible, 0 = occluded.

_5 private function(s) starting with `_` are not listed._
