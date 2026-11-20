# Native camera-projection LOD (engine + Albion After)

Modern engines reduce geometric complexity when a feature contributes too few
pixels to the final image. Unreal's screen-space LOD and Unity's renderer LOD
budgets inspired this implementation; this is **not** a port of Nanite/VSM/Lumen.

## Native engine feature

- `scene/3d/camera_3d.h/.cpp`: `Camera3D.get_pixels_per_meter_at_position(world_point)`
  returns the vertical **viewport** pixel coverage of a one-meter feature at a
  world-space position.
- Uses the renderer's actual `Projection` matrix: `abs(P[1][1]) * height / 2`.
  For perspective/frustum this is divided by camera-space depth. Orthographic
  cameras return a distance-independent value.
- Respects aspect locking, offset frustums, camera transform, positional and
  rotational camera shake. An invalid point / zero-height viewport / behind-camera
  perspective position returns 0. No renderer pass or GPU readback is required.
- This API is public, script-bound and documented in `doc/classes/Camera3D.xml`.
  It is useful for grass, trees, procedural geometry, impostors and particle LOD.
- The result describes logical viewport pixels. A client using 3D dynamic
  resolution multiplies by the active `Viewport.scaling_3d_scale` before using
  the estimate for geometry selection.

## Live game integration

- `chunk_view.gd`: once per grass tile LOD refresh, ask the native camera for
  projected density. A tile on a cliff or a zoomed-out view gets a more accurate
  geometric and instance count than horizontal distance alone.
- `grass_field.gd`: blend 60% projection-derived distance with 40% previous
  horizontal distance to keep the original authored grass layout/visual density.
  The new projection component is capped to **1.15x** the baseline angular pixel
  budget even on ultra-high-resolution screens; no unbounded geometry explosion.
- Profiles still choose their established grass fade radius, three cached
  18/9/4-blade meshes, density transition, per-chunk CPU budget and GPU instancing.
- Cache invalidation now covers FOV/resolution, camera height and camera rotation
  in addition to XZ motion and newly generated grass tiles. No extra per-frame
  queries when the camera is stationary.
- Stock Godot (without the C++ method) continues using the previous horizontal
  distance plus FOV approximation. No engine rebuild is required just to run the
  game, but rebuilding the fork enables the full projection-aware behavior.

## Testing and profiling

The new `tests/test_camera_pixel_density.gd` checks distance monotonicity,
quality caps, fallback, live perspective/orthographic camera behavior on the fork,
and game wiring. Run:

```sh
godot --headless --path game --script res://tests/run_all.gd
```

Use the compiled fork rather than stock Godot to exercise the new native
`Camera3D` method; tests skip only that native probe on stock builds.

Capture representative forest/canyon scenes at 720p, 1080p and 4K; zoom between
0.55x and 1.8x; compare tile pop-in, horizon blade quality and frame-time p95.
A visual/benchmark pass on actual GPU hardware is still necessary before claiming
a measured quality or FPS improvement.
