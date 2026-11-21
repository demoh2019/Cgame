# Native heightfield gradients: landscape slope sampling

Cgame adds a reusable built-in engine primitive:

`Geometry2D.heightfield_gradients(heights: PackedFloat32Array, size: Vector2i, cell_spacing: float) -> PackedVector2Array`

The input is a row-major grid of finite heights; the output at each point is `Vector2(dH/dx, dH/dy)`. Both components are centered differences divided by `2*cell_spacing`. At raster edges, the missing neighbor is replaced by the border sample (exactly the old Albion After map's clamped `_h` semantics). Size dimensions 1..2048; finite positive spacing with representable inverse; exactly width*height finite height samples. Rejected input returns an empty packed array; the caller's heightmap is never modified. All work is CPU-side O(width*height), independent of any renderer.

A returned gradient can be converted to a terrain normal using `Vector3(-dx, 1, -dy).normalized()`, or to hillshade slope `atan(3*sqrt(dx*dx+dy*dy))` and aspect `atan2(dy,-dx)`. No modification is made to mesh normals, navmeshes, or GPU materials. This method is an independent engine primitive for CPU landscape analysis.

## Unreal comparison

Unreal Engine Landscape preserves X/Y slope information for lighting; Unreal PCG can obtain landscape normals and filter generated geometry by slope. See [Landscape Overview](https://dev.epicgames.com/documentation/unreal-engine/landscape-overview?lang=en-US) and [PCG Node Reference](https://dev.epicgames.com/documentation/unreal-engine/procedural-content-generation-framework-node-reference-in-unreal-engine?lang=en-US). Cgame implements a much narrower CPU batch for flat heightmap data, not UE Landscape's vertex/texture data structures or PCG graph execution.

## Immediate Albion After use

The canonical `game/scripts/client/world_map.gd` samples a 384×384 heightmap in eight-row frame budgets. Once height sampling finishes, it now computes gradients in one native call alongside its cached coastline distance field, then reads each gradient for hillshade illumination. Existing water colors, contour lines, shoreline ripples, parchment post-processing, CPU pixel block updates and GPU texture upload are unchanged. The edge math intentionally matches the previous 2D stencil, and no save, multiplayer or server changes are needed.

`game/scripts/client/heightfield_gradients.gd` validates input, uses the native engine method when available, and retains a matching scalar path for stock Godot. This preserves compatibility with environments that have no Cgame executable.

## Tests

- Engine: `tests/core/math/test_geometry_2d.cpp`: interior and edge derivatives, spacing scaling, flat/singleton heightfields, input preservation and invalid inputs.
- Game: `game/tests/test_heightfield_gradients.gd`: plane, randomized gradient parity, old atlas stencil equivalence, normal normalization and actual map integration. Registered in `run_all.gd`.

Run with a built Cgame executable:

```sh
godot --headless --test --test-case="*heightfield gradients*"
godot --headless --path game --script res://tests/run_all.gd
```

Compile, run scene tests, compare atlas screenshots and benchmark before claiming a measurable performance improvement.
