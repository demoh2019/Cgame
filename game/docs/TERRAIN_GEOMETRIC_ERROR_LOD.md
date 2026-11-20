# Geometric-error-aware terrain LOD (engine + Albion After)

## Goal and references

The game already uses a camera-projected mesh LOD budget, heightmap
geomorphing, cached LOD meshes, seam-safe normals, and curvature-driven
material lighting. One remaining shortcoming was that a flat plain and a
rocky ridgeline at equal distance received the *same number of triangles*.
This update improves that trade-off using the principle of geometric error.

- Unreal Engine Nanite simplifies geometry according to screen-space error;
  the game does **not** implement Nanite, but reuses the LOD-error idea.
  https://dev.epicgames.com/documentation/en-us/unreal-engine/nanite-technical-details
- Unity Terrain provides a `heightmapPixelError` budget for the visible
  discrepancy introduced by terrain heightmap simplification.
  https://docs.unity.com/en-us/engine/6000.5/script-reference/unityengine/terrain/heightmappixelerror

## Native Godot fork

New `ChunkedTerrain3D.lod_geometric_error_strength`, float in [0, 1],
defaults to **0** to preserve old scenes and avoid extra CPU work.

For each visible chunk, only when enabled, the engine samples the original
heightmap once against the triangles of a coarser mesh (up to stride 4).
The largest measured height deviation is cached. The algorithm respects the
same diagonal used by the original mesh builder and gameplay height queries
and clamps partial chunks to the heightfield boundary.

At update time the engine reuses that cached metric to bias the existing
camera-relative distance threshold:

`lerp(1, clamp(0.72 + max_error_metres * 0.22, 0.72, 1.65), strength)`

- Flat, planar geometry has zero deviation and can change to lower-poly
  meshes earlier.
- High-error rocky peaks stay detailed longer to avoid losing their shape.
- The adjustment is strictly bounded (0.72–1.65 at full strength).
- The exact same adjusted threshold drives the existing geomorph uniforms,
  preventing screen-size and morphing from disagreeing.

No extra textures, GPU draws, shadow maps, render passes, per-frame
heightmap scans, physics bodies or serialized height data are added. When the native distance-based selector is active, height-deviation
calculations happen lazily, once per visible chunk, and are invalidated
only when its height data or LOD count changes. When the newer
`lod_pixel_error` selector is active, the controller **reuses the
per-LOD error array already cached when the heightfield was built**:
there is no second terrain scan. Ruggedness adjusts the permitted pixel
error (inverse to the bounded detail factor), and both pixel LOD and
geomorph thresholds use the same adjusted tolerance. Quality updates
change the weight without forcing a terrain rebuild.

## Game integration

The game configures all streamed `ChunkedTerrain3D` objects on creation
and updates existing ones on a graphics quality switch.

| Profile | Error-aware LOD strength |
| --- | ---: |
| Performance | 0.00 — legacy path, no deviation scan |
| Balanced | 0.25 |
| High | 0.65 |
| Ultra | 1.00 |

These settings complement the previous 55/70/90/112 m baseline distances
and projected-screen-height scaling. The terrain remains editable and the
server-authoritative gameplay collision is unchanged.

## Verification

C++ regression tests cover planar slopes, single narrow rocky spikes,
invalid inputs, strength limits and preserving legacy selection.
GDScript tests cover all four presets, native property wiring, streaming,
curvature, geomorphing and game collision behavior.

- Engine: build the fork and run the tests tagged `[HeightmapTerrain]`
  and `[SceneTree][ChunkedTerrain3D]`.
- Game: `godot --headless --path game --script res://tests/run_all.gd`.
- Hardware: capture matching flyovers of forest hills, flat roads and
  alpine ridges. Check silhouette errors, geomorph edges, CPU build spikes,
  p50/p95 frame time and triangle counts by tier on Apple M1 Forward+
  and Compatibility.

Benefits are architectural expectations, not measured FPS improvements
until the compiled engine runs on representative GPU hardware.
