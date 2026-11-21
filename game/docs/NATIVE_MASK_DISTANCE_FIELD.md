# Native 8-connected raster distance transform

Cgame extends the built-in `Geometry2D` singleton:

```gdscript
var distances: PackedByteArray = Geometry2D.distance_transform_8(
    mask: PackedByteArray, size: Vector2i, max_distance: int)
```

The input is a row-major binary raster: any nonzero byte marks a feature pixel. The result is a row-major unsigned byte *chessboard / Chebyshev* distance field, whose value equals `max(abs(x - target_x), abs(y - target_y))` to the closest feature. A feature has value 0; 255 means no feature within `max_distance` (0–254 inclusive). No feature positions are inferred beyond image borders. The engine checks that each dimension is 1–2048 and the mask has precisely width × height elements. Invalid input returns an empty array without modifying the mask.

The implementation uses forward and backward eight-neighbor dynamic-programming raster sweeps, O(width × height) time and one byte of output memory per pixel. The result is **not Euclidean SDF or a 3D mesh distance field**. It is well suited to coastline bands, binary terrain masks, editor outlines and lightweight proximity stencils. Unity's SDF image/glyph workflows and Unreal's mesh distance fields are broader related technologies, not equivalent implementations.

## Albion After world atlas

`game/scripts/client/world_map.gd` now waits until its 384 × 384 height sampling is complete, thresholds the heightmap into a binary land mask, then builds a single coast distance field with a seven-pixel search radius. Water pixels use the precomputed distance for the existing depth tint and ripple overlays, replacing the former eight straight-ray queries per water pixel. Compared with the straight-ray search, the eight-connected transform reaches the nearest land through *any* sequence of diagonal/cardinal steps, which creates more consistent coastline bands. This may deliberately alter shore tint/ripple locations slightly; it leaves the world height data, server simulation and network/save formats unchanged.

`game/scripts/client/mask_distance_field.gd` provides a **parity-matched two-pass scalar fallback** on stock Godot, alongside `from_heights` to build a binary mask safely. The game test `game/tests/test_mask_distance_field.gd` checks native fallback against an independent brute-force distance oracle, field radius clipping, uniform all-land/all-water masks, invalid inputs and conversion of sampled heights.

## Testing

```sh
godot --headless --test --test-case="*binary 8-connected distance transform*"
godot --headless --path game --script res://tests/run_all.gd
```

Visual compare of world map shorelines on native Cgame and stock Godot is recommended; benchmark the chart paint pass before claiming a speedup.

Related technical references:
- https://www.mathworks.com/help/images/ref/bwdist.html (chessboard distance metric and two-pass algorithm)
- https://dev.epicgames.com/documentation/en-us/unreal-engine/mesh-distance-fields-in-unreal-engine (broader 3D distance-field applications)
- https://docs.unity.com/en-us/engine/6000.0/script-reference/unityengine/textcore/lowlevel/glyphrendermode/sdf32 (2D SDF font rendering; different distance semantics)
