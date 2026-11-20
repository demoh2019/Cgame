# Screen-space geometry LOD in Albion After (engine + game)

Unreal Engine and Unity base mesh detail selection on **projected screen size**
rather than fixed world distance. The custom Godot fork's `ChunkedTerrain3D`
previously used world-distance-only LOD, which could discard useful geometry
at high pixel density and spend too many triangles at low resolution.

## Native engine capability

The project adds two properties to `ChunkedTerrain3D`:

- `screen_space_lod_enabled` (default `false`, backwards compatible)
- `lod_reference_fov` (default 60 degrees, vertical reference FOV)

For perspective cameras, the LOD distance is scaled **once per scheduled terrain
update**, not once per chunk or pixel:

`clamp((viewport_height / 720) * tan(reference_fov / 2) / tan(vertical_fov / 2), 0.60, 1.65)`

At 720p and the authored reference FOV, geometry selection is identical to the
original algorithm. Higher resolutions and narrower fields of view retain LOD
0 longer; a 360p camera uses coarser mesh levels earlier. Invalid/zero viewport
sizes and orthographic/no-camera views retain the original behavior. With
Camera3D KEEP_WIDTH, horizontal FOV is converted to vertical using viewport
aspect ratio first.

This reuses the engine's cached mesh LODs, culling, terrain skirts and
existing 10% hysteresis. Collision remains server-authoritative in the game.
A newly merged independent **LOD geomorph** feature also uses the *same effective
projected threshold*, ensuring both features can work together without
independent, drifting transition distances.

## Game integration

Every streamed game chunk receives `screen_space_lod_enabled = true` and
`lod_reference_fov = 38`, matching the game's real 38-degree, 720p camera.
The graphics preset selects the baseline geometry distance:

| Graphics tier | LOD0 threshold at 720p, 38° |
| --- | ---: |
| Performance | 55 m |
| Balanced | 70 m (old baseline) |
| High | 90 m |
| Ultra | 112 m |

Quality changes update existing streamed meshes in the
`TERRAIN_LOD_GROUP` without rebuilding world height data. New chunks inherit
the setting and automatic quality decisions use the same path.

No added GPU texture fetches, screen-space shaders, render passes, terrain
colliders or terrain data. On high-end profiles more triangles can remain
visible; on low-res profiles geometry can be reduced earlier.

## Validation and performance acceptance

- Engine C++: run tests tagged `[HeightmapTerrain]` and
  `[SceneTree][ChunkedTerrain3D]`, verifying projection bounds,
  opt-in behavior and unchanged collision state.
- Game: `godot --headless --path game --script res://tests/run_all.gd`.
- On actual GPU: compare 360p, 720p and 1080p around the same rocky ridge,
  settlement and forest at identical camera positions. Try zooming from
  38° to 60° FOV. Check LOD changes, skirt seams, geomorph animation,
  nearby surface quality, and p50/p95 frame times on Forward+ and Compatibility.

No runtime test or FPS gain is claimed without a compiled engine and hardware
measurements.

## Further reading

- https://dev.epicgames.com/documentation/unreal-engine/creating-and-using-lods-in-unreal-engine
- https://docs.unity.cn/6000.0/Documentation/Manual/class-LODGroup.html
- https://docs.godotengine.org/en/stable/classes/class_camera3d.html
