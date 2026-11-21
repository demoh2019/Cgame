# path_tracer.gd

> CPU path tracer for light baking (per-vertex lighting, ambient occlusion) and an offline photo/movie render mode, on top of the BVH in bvh.gd.

`res://scripts/shared/path_tracer.gd`

## Overview

```text
CPU path tracer for light baking (per-vertex lighting, ambient occlusion) and an offline
photo/movie render mode, on top of the BVH in bvh.gd.

Technique references (concepts re-implemented, no source text copied):
 - Peter Shirley, "Ray Tracing in One Weekend" / "The Next Week" / "The Rest of Your Life"
   (CC0 1.0): https://raytracing.github.io/  -- diffuse bounce, cosine-weighted sampling.
 - Pharr/Jakob/Humphreys, "Physically Based Rendering" 4th ed. (online, BSD-2 code):
   https://pbr-book.org/  -- next-event estimation, Russian roulette, path integrator.
 - Jacco Bikker, BVH/path tracing articles (public domain / ZLIB-style): https://jacco.ompf2.com/
No Apache-2.0, GPL or LGPL code is included.

Conventions: sun_dir is the direction the sunlight TRAVELS (like a DirectionalLight's forward).
sun_color is the radiance a white diffuse surface facing the sun returns (irradiance / pi
already folded in), sky_color is a constant-radiance environment. Output colours are linear.
```

## Constants

- `const Bvh = preload("res://scripts/shared/bvh.gd")`
- `const EPS := 0.001`
- `const FAR := 1.0e20`

## Classes

- `class Progressive extends RefCounted:` - Accumulating image state for progressive rendering.

## Functions

### `make_light`

```gdscript
static func make_light(sun_dir: Vector3, sun_color: Color, sky_color: Color, albedo_per_tri: PackedColorArray = PackedColorArray(), bounces: int = 3) -> Dictionary
```

Light/material description for render_image and accumulate.

### `bake_vertex_lighting`

```gdscript
static func bake_vertex_lighting(bvh: Bvh, vertices: PackedVector3Array, normals: PackedVector3Array, albedo_per_tri: PackedColorArray, sun_dir: Vector3, sun_color: Color, sky_color: Color, samples: int, bounces: int, seed: int) -> PackedColorArray
```

Per-vertex baked lighting for a triangle soup (vertices/normals are per vertex, three per
triangle; albedo_per_tri has one colour per triangle). Alpha is 1.

### `bake_ambient_occlusion`

```gdscript
static func bake_ambient_occlusion(bvh: Bvh, vertices: PackedVector3Array, normals: PackedVector3Array, samples: int, max_dist: float, seed: int) -> PackedFloat32Array
```

Ambient visibility per vertex: 1.0 fully open, 0.0 fully enclosed within max_dist.

### `accumulate`

```gdscript
static func accumulate(bvh: Bvh, prog: Progressive, camera: Transform3D, fov_deg: float, spp: int, light: Dictionary = {}) -> void
```

Adds `spp` samples per pixel to `prog` (call repeatedly for progressive refinement).
camera looks down its -Z axis; fov_deg is the vertical field of view.

### `render_image`

```gdscript
static func render_image(bvh: Bvh, camera: Transform3D, fov_deg: float, size: Vector2i, spp: int, light: Dictionary = {}, seed: int = 1) -> Image
```

One-shot offline render (photo / movie frame).

_4 private function(s) starting with `_` are not listed._
